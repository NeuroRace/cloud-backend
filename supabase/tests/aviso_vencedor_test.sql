\set ON_ERROR_STOP on

-- NEU-112 (complemento): o e-mail "voce venceu" (texto 2 da NEU-165). Quando um premio da NEU-167
-- vira avisado, avisos_premio_tick enfileira 1 e-mail na caixa de saida, para o e-mail confirmado
-- da conta, com rodada, codigo e hora limite. So le o premio. Tudo numa transacao com ROLLBACK.
--
-- Seed (UTC): rodada 2020-06-01 10:00-11:00 com A 40 s, B 41 s, C 42 s (C sem e-mail confirmado).
-- O tick da NEU-167 as 11:05 congela o premio de A, com prazo 11:20 (08:20 em Sao Paulo).

begin;

update public.premiacao_config set
  premiacao_ligada = true, ligada_em = '2020-01-01 00:00+00', evento_atual = 'TESTE',
  carencia_min = 5, janela_min = 15, limite_fila = 5, passar_sozinho = false, pausa_geral = false,
  piso_tempo_s = 15;

insert into auth.users (instance_id, id, aud, role, email, email_confirmed_at, created_at, updated_at) values
 ('00000000-0000-0000-0000-000000000000','11280000-0000-0000-0000-00000000000a','authenticated','authenticated','vv_a@neu112.test','2020-01-01 00:00+00','2020-01-01 00:00+00','2020-01-01 00:00+00'),
 ('00000000-0000-0000-0000-000000000000','11280000-0000-0000-0000-00000000000b','authenticated','authenticated','vv_b@neu112.test','2020-01-01 00:00+00','2020-01-01 00:00+00','2020-01-01 00:00+00'),
 ('00000000-0000-0000-0000-000000000000','11280000-0000-0000-0000-00000000000c','authenticated','authenticated','vv_c@neu112.test', null,'2020-01-01 00:00+00','2020-01-01 00:00+00');
update public.profiles set display_name = 'V112A' where id = '11280000-0000-0000-0000-00000000000a';
update public.profiles set display_name = 'V112B' where id = '11280000-0000-0000-0000-00000000000b';
update public.profiles set display_name = 'V112C' where id = '11280000-0000-0000-0000-00000000000c';
insert into public.players (id, email, user_id) values
 ('11290000-0000-0000-0000-00000000000a','vv_a@neu112.test','11280000-0000-0000-0000-00000000000a'),
 ('11290000-0000-0000-0000-00000000000b','vv_b@neu112.test','11280000-0000-0000-0000-00000000000b'),
 ('11290000-0000-0000-0000-00000000000c','vv_c@neu112.test','11280000-0000-0000-0000-00000000000c');
insert into public.ranking_windows (id, name, starts_at, ends_at) values
 ('112a0000-0000-0000-0000-000000000001','V112 Rodada 1','2020-06-01 10:00+00','2020-06-01 11:00+00');

create function pg_temp.corrida(n int, jogador uuid, segundos numeric, terminou timestamptz)
returns void language sql as $$
  insert into public.races (id, started_at)
  values (('112b0000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid, terminou - make_interval(secs => segundos));
  insert into public.race_players (id, idempotency_key, race_id, player_id, player_slot, source, started_at, finished_at, created_at)
  values (('112c0000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
          ('112d0000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
          ('112b0000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
          jogador, 1, 'real', terminou - make_interval(secs => segundos), terminou, terminou);
$$;
select pg_temp.corrida(1,'11290000-0000-0000-0000-00000000000a',40,'2020-06-01 10:30+00');
select pg_temp.corrida(2,'11290000-0000-0000-0000-00000000000b',41,'2020-06-01 10:40+00');
select pg_temp.corrida(3,'11290000-0000-0000-0000-00000000000c',42,'2020-06-01 10:50+00');
select public.premiacao_tick('2020-06-01 11:05+00');

create function pg_temp.premio_de(conta uuid) returns public.premios language sql as $$
  select * from public.premios where user_id = conta order by criado_em desc limit 1;
$$;
create function pg_temp.avisos(destino text) returns setof public.mensagens language sql as $$
  select * from public.mensagens where destino = $1 and tipo = 'premio_venceu' order by criada_em;
$$;

-- ===== O vencedor recebe o texto 2, com rodada, codigo e hora limite (horario de Sao Paulo) =====
do $$
declare p public.premios := pg_temp.premio_de('11280000-0000-0000-0000-00000000000a'); m public.mensagens; r jsonb;
begin
  assert p.status = 'avisado' and p.prazo = '2020-06-01 11:20+00', 'seed: premio de A avisado ate 11:20';
  r := public.avisos_premio_tick('2020-06-01 11:06+00');
  assert (r ->> 'avisos')::int = 1 and (r ->> 'erros')::int = 0, 'tick: um aviso, sem erros; veio ' || r::text;
  select * into m from pg_temp.avisos('vv_a@neu112.test');
  assert m.id is not null, 'A recebe o aviso';
  assert m.canal = 'email' and m.estado = 'pendente', 'aviso por e-mail, pendente';
  assert m.premio_id = p.id and m.round_id = p.round_id and m.user_id = p.user_id, 'ligado ao premio, a rodada e a conta';
  assert m.validade = p.prazo, 'vale ate o prazo de retirada';
  assert m.assunto = 'Você venceu a V112 Rodada 1 do NeuroRace!', 'assunto, veio ' || m.assunto;
  assert m.corpo_texto = 'Você venceu a V112 Rodada 1 do NeuroRace, V112A! Venha ao estande até 08:20 '
                        || 'e mostre o código ' || p.code || '.',
    'texto 2 com rodada, apelido, hora limite e codigo; veio ' || m.corpo_texto;
end $$;

-- ===== Tick repetido nao duplica =====
do $$
begin
  perform public.avisos_premio_tick('2020-06-01 11:07+00');
  assert (select count(*) from pg_temp.avisos('vv_a@neu112.test')) = 1, 'tick repetido: um aviso so';
end $$;

-- ===== O premio passa: o proximo recebe o aviso dele, com o codigo novo =====
do $$
declare b public.premios;
begin
  perform public.premio_passar(pg_temp.premio_de('11280000-0000-0000-0000-00000000000a').id, 'recusado',
                               '2020-06-01 11:10+00', 'teste', 'Nao vou poder');
  b := pg_temp.premio_de('11280000-0000-0000-0000-00000000000b');
  assert b.status = 'avisado', 'seed: B tem a vez';
  perform public.avisos_premio_tick('2020-06-01 11:11+00');
  assert (select count(*) from pg_temp.avisos('vv_b@neu112.test')) = 1, 'B recebe o aviso';
  assert (select corpo_texto from pg_temp.avisos('vv_b@neu112.test')) like '%código ' || b.code || '.',
    'B recebe o codigo dele';
end $$;

-- ===== Conta sem e-mail confirmado: nada sai (e nao e erro) =====
do $$
declare r jsonb;
begin
  perform public.premio_passar(pg_temp.premio_de('11280000-0000-0000-0000-00000000000b').id, 'recusado',
                               '2020-06-01 11:12+00', 'teste', 'Nao vou poder');
  assert pg_temp.premio_de('11280000-0000-0000-0000-00000000000c').status = 'avisado', 'seed: C tem a vez';
  r := public.avisos_premio_tick('2020-06-01 11:13+00');
  assert (r ->> 'erros')::int = 0 and (r ->> 'sem_contato')::int = 1, 'C sem e-mail confirmado: sem_contato; veio ' || r::text;
  assert not exists (select 1 from pg_temp.avisos('vv_c@neu112.test')), 'C nao recebe';
end $$;

-- ===== Prazo vencido: nao avisa (o aviso chegaria tarde) =====
do $$
declare r jsonb;
begin
  delete from public.mensagens;
  r := public.avisos_premio_tick('2020-06-01 12:00+00');
  assert (r ->> 'avisos')::int = 0, 'prazo vencido: nenhum aviso novo; veio ' || r::text;
end $$;

-- ===== Premiacao desligada ou em pausa geral: nao roda =====
do $$
declare r jsonb;
begin
  update public.premiacao_config set pausa_geral = true;
  r := public.avisos_premio_tick('2020-06-01 11:14+00');
  assert (r ->> 'rodou')::boolean = false, 'pausa geral: nao roda; veio ' || r::text;
  update public.premiacao_config set pausa_geral = false, premiacao_ligada = false;
  r := public.avisos_premio_tick('2020-06-01 11:14+00');
  assert (r ->> 'rodou')::boolean = false, 'premiacao desligada: nao roda; veio ' || r::text;
end $$;

-- ===== O site nao chama =====
do $$
begin
  assert not has_function_privilege('anon', 'public.avisos_premio_tick(timestamptz)', 'execute'), 'anon nao roda';
  assert not has_function_privilege('authenticated', 'public.avisos_premio_tick(timestamptz)', 'execute'),
    'authenticated nao roda';
end $$;

rollback;
select 'aviso_vencedor_test OK' as result;
