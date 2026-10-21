\set ON_ERROR_STOP on

-- NEU-168: operadores da premiacao e as funcoes op_* do painel /operador (web#33).
-- Contrato: comentario da NEU-114 (21/10). Tudo numa transacao com ROLLBACK no fim.
-- A parte que depende de horario usa as funcoes internas com p_agora; os op_* publicos
-- (que usam now()) sao testados so em permissao e forma.

begin;

update public.premiacao_config set
  premiacao_ligada = true, ligada_em = '2020-01-01 00:00+00', evento_atual = 'TESTE',
  carencia_min = 5, janela_min = 15, limite_fila = 5, passar_sozinho = false, pausa_geral = false, piso_tempo_s = 15;

insert into public.operadores (email) values ('op@neu168.test'), ('semconfirmar@neu168.test');

-- op: operador confirmado | naoop: conta comum | semconfirmar: e-mail na lista mas nao confirmado
-- cel: so celular | X (com celular), Y, Z, W: jogadores
insert into auth.users (instance_id, id, aud, role, email, phone, email_confirmed_at, phone_confirmed_at, created_at, updated_at) values
 ('00000000-0000-0000-0000-000000000000','6b000000-0000-0000-0000-0000000000a1','authenticated','authenticated','op@neu168.test', null,'2020-01-01',null,'2020-01-01','2020-01-01'),
 ('00000000-0000-0000-0000-000000000000','6b000000-0000-0000-0000-0000000000a2','authenticated','authenticated','naoop@neu168.test', null,'2020-01-01',null,'2020-01-01','2020-01-01'),
 ('00000000-0000-0000-0000-000000000000','6b000000-0000-0000-0000-0000000000a3','authenticated','authenticated','semconfirmar@neu168.test', null,null,null,'2020-01-01','2020-01-01'),
 ('00000000-0000-0000-0000-000000000000','6b000000-0000-0000-0000-0000000000a4','authenticated','authenticated',null,'5511900000004',null,'2020-01-01','2020-01-01','2020-01-01'),
 ('00000000-0000-0000-0000-000000000000','6b000000-0000-0000-0000-00000000000a','authenticated','authenticated','x1@neu168.test','5511987654321','2020-01-01','2020-01-01','2020-01-01','2020-01-01'),
 ('00000000-0000-0000-0000-000000000000','6b000000-0000-0000-0000-00000000000b','authenticated','authenticated','yy@neu168.test', null,'2020-01-01',null,'2020-01-01','2020-01-01'),
 ('00000000-0000-0000-0000-000000000000','6b000000-0000-0000-0000-00000000000c','authenticated','authenticated','zz@neu168.test', null,'2020-01-01',null,'2020-01-01','2020-01-01'),
 ('00000000-0000-0000-0000-000000000000','6b000000-0000-0000-0000-00000000000d','authenticated','authenticated','ww@neu168.test', null,'2020-01-01',null,'2020-01-01','2020-01-01');
update public.profiles set display_name = 'O168X' where id = '6b000000-0000-0000-0000-00000000000a';
update public.profiles set display_name = 'O168Y' where id = '6b000000-0000-0000-0000-00000000000b';
update public.profiles set display_name = 'O168Z' where id = '6b000000-0000-0000-0000-00000000000c';
update public.profiles set display_name = 'O168W' where id = '6b000000-0000-0000-0000-00000000000d';
insert into public.players (id, email, user_id) values
 ('6b100000-0000-0000-0000-00000000000a','x1@neu168.test','6b000000-0000-0000-0000-00000000000a'),
 ('6b100000-0000-0000-0000-00000000000b','yy@neu168.test','6b000000-0000-0000-0000-00000000000b'),
 ('6b100000-0000-0000-0000-00000000000c','zz@neu168.test','6b000000-0000-0000-0000-00000000000c'),
 ('6b100000-0000-0000-0000-00000000000d','ww@neu168.test','6b000000-0000-0000-0000-00000000000d');
insert into public.ranking_windows (id, name, starts_at, ends_at) values
 ('6b200000-0000-0000-0000-000000000000','O168 Antiga',  '2019-12-31 10:00+00','2019-12-31 11:00+00'),
 ('6b200000-0000-0000-0000-000000000001','O168 Rodada 1','2020-06-01 14:00+00','2020-06-01 15:00+00');

create function pg_temp.corrida(n int, jogador uuid, segundos numeric, terminou timestamptz)
returns void language sql as $$
  insert into public.races (id, started_at)
  values (('6b300000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid, terminou - make_interval(secs => segundos));
  insert into public.race_players (id, idempotency_key, race_id, player_id, player_slot, source, started_at, finished_at, created_at)
  values (('6b400000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
          ('6b500000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
          ('6b300000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
          jogador, 1, 'real', terminou - make_interval(secs => segundos), terminou, terminou);
$$;
select pg_temp.corrida(1,'6b100000-0000-0000-0000-00000000000a',40.125,'2020-06-01 14:30+00');
select pg_temp.corrida(2,'6b100000-0000-0000-0000-00000000000b',41.0,'2020-06-01 14:31+00');
select pg_temp.corrida(3,'6b100000-0000-0000-0000-00000000000c',42.0,'2020-06-01 14:32+00');
select pg_temp.corrida(4,'6b100000-0000-0000-0000-00000000000d',43.0,'2020-06-01 14:33+00');
insert into public.telemetry_points (race_player_id, t, attention) values
 ('6b400000-0000-0000-0000-000000000001','2020-06-01 14:29:50+00',70),
 ('6b400000-0000-0000-0000-000000000001','2020-06-01 14:29:55+00',80);

create function pg_temp.limpa() returns void language sql as $$
  delete from public.premios;
  delete from public.premiacao_rodadas;
  delete from public.premiacao_registro;
  update public.premiacao_config set passar_sozinho = false, pausa_geral = false, limite_fila = 5,
    premiacao_ligada = true, ligada_em = '2020-01-01 00:00+00', evento_atual = 'TESTE';
$$;
create function pg_temp.dono() returns table (id uuid, user_id uuid, status text, code text, prazo timestamptz, posicao int)
language sql as $$
  select p.id, p.user_id, p.status, p.code, p.prazo, p.posicao from public.premios p
  where p.round_id = '6b200000-0000-0000-0000-000000000001'
    and p.status in ('avisando','avisado','prazo_estourou','aviso_falhou','entregue');
$$;
create function pg_temp.premio_de(u uuid) returns uuid language sql as $$
  select id from public.premios where round_id = '6b200000-0000-0000-0000-000000000001' and user_id = u;
$$;

-- ===== AC1/AC2/AC8: permissao =====
do $$
declare f text; r text;
begin
  foreach f in array array['public.op_painel()','public.op_validar_codigo(text)','public.op_acao(uuid, text, text)','public.op_config(jsonb)'] loop
    assert not has_function_privilege('anon', f, 'EXECUTE'), 'AC1: anon nao chama ' || f;
    assert not has_function_privilege('public', f, 'EXECUTE'), 'AC1: public nao chama ' || f;
    assert has_function_privilege('authenticated', f, 'EXECUTE'), 'o site (authenticated) chama ' || f;
  end loop;
  foreach f in array array['public.premiacao_operador_atual()',
                           'public.premiacao_op_painel(timestamptz)',
                           'public.premiacao_op_validar(text, text, timestamptz)',
                           'public.premiacao_op_acao(text, uuid, text, text, timestamptz)',
                           'public.premiacao_op_config(text, jsonb, timestamptz)',
                           'public.premio_dar_vez_ate(uuid, timestamptz, int, boolean)',
                           'public.premiacao_mascara_contato(text, text)'] loop
    foreach r in array array['anon','authenticated','public'] loop
      assert not has_function_privilege(r, f, 'EXECUTE'), format('AC8: %s nao chama %s', r, f);
    end loop;
  end loop;
  foreach r in array array['anon','authenticated'] loop
    foreach f in array array['SELECT','INSERT','UPDATE','DELETE','TRUNCATE'] loop
      assert not has_table_privilege(r, 'public.operadores', f), format('AC8: %s nao pode %s em operadores', r, f);
    end loop;
  end loop;
end $$;

create function pg_temp.negado(chamada text) returns boolean language plpgsql as $$
begin
  execute chamada;
  return false;
exception when insufficient_privilege then
  return true;
end $$;

-- conta comum, e-mail na lista sem confirmar, conta so de celular: 42501 em todas
do $$
declare quem text; c text;
begin
  foreach quem in array array['6b000000-0000-0000-0000-0000000000a2','6b000000-0000-0000-0000-0000000000a3','6b000000-0000-0000-0000-0000000000a4'] loop
    perform set_config('request.jwt.claims', json_build_object('sub', quem, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    foreach c in array array['select public.op_painel()',
                             'select public.op_validar_codigo(''123456'')',
                             'select public.op_acao(''00000000-0000-0000-0000-000000000000'', ''passar'')',
                             'select public.op_config(''{"pausa_geral": true}'')'] loop
      assert pg_temp.negado(c), format('AC1/AC2: %s deve receber 42501 em: %s', quem, c);
    end loop;
    perform set_config('role', 'postgres', true);
  end loop;
end $$;
reset role;
do $$ begin
  assert (select pausa_geral from public.premiacao_config) = false, 'AC1: nenhuma tentativa negada mudou a config';
end $$;

-- ===== AC6: forma do op_painel, chamado pelo operador =====
select public.premiacao_tick('2020-06-01 15:05+00');   -- R1: X avisado
set local role authenticated;
set local request.jwt.claims to '{"sub":"6b000000-0000-0000-0000-0000000000a1","role":"authenticated"}';
do $$
declare j jsonb; p jsonb; g jsonb;
begin
  j := public.op_painel();
  assert (select array_agg(k order by k) from jsonb_object_keys(j) k) = array['agora','config','premios','registro'],
    'AC6: chaves do painel ' || (select string_agg(k, ',') from jsonb_object_keys(j) k);
  assert jsonb_typeof(j->'agora') = 'string', 'AC6: agora e texto';
  assert (select array_agg(k order by k) from jsonb_object_keys(j->'config') k)
       = array['carencia_min','evento_atual','janela_min','lembrete_min','ligada_em','limite_fila','passar_sozinho','pausa_geral','premiacao_ligada'],
    'AC6: config com as 9 chaves do contrato (piso_tempo_s fica fora): ' || (select string_agg(k, ',') from jsonb_object_keys(j->'config') k);
  assert jsonb_typeof(j->'config'->'carencia_min') = 'number' and jsonb_typeof(j->'config'->'premiacao_ligada') = 'boolean', 'AC6: tipos da config';
  assert jsonb_array_length(j->'premios') = 1, 'AC6: um premio';
  p := j->'premios'->0;
  assert (select array_agg(k order by k) from jsonb_object_keys(p) k)
       = array['atencao_media','contato','display_name','entregue_em','id','posicao','prazo','round_ends_at','round_id','round_name','score','sem_canal','status'],
    'AC6: chaves do premio ' || (select string_agg(k, ',') from jsonb_object_keys(p) k);
  assert p->>'display_name' = 'O168X' and p->>'status' = 'avisado' and p->>'round_name' = 'O168 Rodada 1', 'AC6: valores do premio';
  assert jsonb_typeof(p->'score') = 'number' and (p->>'score')::numeric = 40.125, 'AC6: score numero com milesimo';
  assert jsonb_typeof(p->'posicao') = 'number' and (p->>'posicao')::int = 1, 'AC6: posicao numero';
  assert (p->>'atencao_media')::numeric = 75, 'AC6: atencao media da corrida vencedora';
  assert p->>'contato' = 'x1***@neu168.test | (11) *****-4321', 'AC6: contato mascarado, veio ' || coalesce(p->>'contato','null');
  assert p->'sem_canal' = 'false'::jsonb, 'AC6: sem_canal booleano';
  assert jsonb_typeof(p->'prazo') = 'string' and p->'entregue_em' = 'null'::jsonb, 'AC6: prazo texto, entregue_em null';
  assert jsonb_array_length(j->'registro') >= 1, 'AC6: registro com o fechamento';
  g := j->'registro'->0;
  assert (select array_agg(k order by k) from jsonb_object_keys(g) k) = array['acao','detalhe','em','operador','round_name'],
    'AC6: chaves do registro ' || (select string_agg(k, ',') from jsonb_object_keys(g) k);
end $$;
reset role;

-- ===== AC3: validar codigo =====
do $$
declare r jsonb; cod text; i int;
begin
  select code into cod from pg_temp.dono();
  r := public.premiacao_op_validar('op@neu168.test', '000000', '2020-06-01 15:06:00+00');
  if cod = '000000' then
    r := public.premiacao_op_validar('op@neu168.test', '000001', '2020-06-01 15:06:00+00');
  end if;
  assert r->>'resultado' = 'invalido', 'AC3: codigo errado -> invalido, veio ' || r::text;
  for i in 1..4 loop
    r := public.premiacao_op_validar('op@neu168.test', case when cod = '999999' then '999998' else '999999' end,
                                     '2020-06-01 15:06:00+00'::timestamptz + make_interval(secs => i));
  end loop;
  -- 5 erros entre 15:06:00 e 15:06:04: a 6a tentativa espera, ate com o codigo certo
  r := public.premiacao_op_validar('op@neu168.test', cod, '2020-06-01 15:06:30+00');
  assert r->>'resultado' = 'espere', 'AC3: 6a tentativa em 1 min espera, veio ' || r::text;
  assert (r->>'espere_ate')::timestamptz = '2020-06-01 15:07:00+00', 'AC3: espera 1 min a partir do 1o dos 5 erros, veio ' || (r->>'espere_ate');
  assert (select status from pg_temp.dono()) = 'avisado', 'AC3: espere nao entrega';
  r := public.premiacao_op_validar('op@neu168.test', cod, '2020-06-01 15:07:01+00');
  assert r->>'resultado' = 'entregue' and r->>'display_name' = 'O168X' and r->>'round_name' = 'O168 Rodada 1'
     and (r->>'entregue_em')::timestamptz = '2020-06-01 15:07:01+00', 'AC3: codigo certo -> entregue, veio ' || r::text;
  assert (select status from pg_temp.dono()) = 'entregue', 'AC3: premio entregue';
  r := public.premiacao_op_validar('op@neu168.test', cod, '2020-06-01 15:08:00+00');
  assert r->>'resultado' = 'ja_entregue' and (r->>'entregue_em')::timestamptz = '2020-06-01 15:07:01+00',
    'AC3: repetido -> ja_entregue com a hora, veio ' || r::text;
  assert (select count(*) from public.premiacao_registro where operador = 'op@neu168.test') >= 7,
    'AC7: cada tentativa fica no registro com o e-mail do operador';
  assert not exists (select 1 from public.premiacao_registro where detalhe like '%' || cod || '%'),
    'o codigo nao vai para o registro';
end $$;

-- ===== AC4: acoes =====
select pg_temp.limpa();
do $$
declare r jsonb; px uuid; cx text;
begin
  perform public.premiacao_tick('2020-06-01 15:05+00');
  select id, code into px, cx from pg_temp.dono();

  r := public.premiacao_op_acao('op@neu168.test', px, 'mais_10_min', null, '2020-06-01 15:10+00');
  assert r = '{"ok": true}'::jsonb and (select prazo from pg_temp.dono()) = '2020-06-01 15:30+00', 'AC4: +10 min soma no prazo';
  perform public.premiacao_tick('2020-06-01 15:31+00');
  assert (select status from pg_temp.dono()) = 'prazo_estourou', 'AC4: estourou';
  r := public.premiacao_op_acao('op@neu168.test', px, 'mais_10_min', null, '2020-06-01 15:32+00');
  assert (select status from pg_temp.dono()) = 'avisado' and (select prazo from pg_temp.dono()) = '2020-06-01 15:42+00',
    'AC4: +10 min depois do prazo volta a avisado, 10 min a partir de agora';

  r := public.premiacao_op_acao('op@neu168.test', px, 'entregue_sem_codigo', '  ', '2020-06-01 15:33+00');
  assert r->>'ok' = 'false' and r->>'erro' is not null, 'AC4: entregue sem codigo pede motivo';
  r := public.premiacao_op_acao('op@neu168.test', px, 'xyz', null, '2020-06-01 15:33+00');
  assert r->>'ok' = 'false', 'AC4: acao desconhecida -> ok false';
  r := public.premiacao_op_acao('op@neu168.test', px, 'continuar', null, '2020-06-01 15:33+00');
  assert r->>'ok' = 'false', 'AC4: continuar so depois do limite (sem_retirada)';

  r := public.premiacao_op_acao('op@neu168.test', px, 'passar', null, '2020-06-01 15:34+00');
  assert r->>'ok' = 'true', 'AC4: passar';
  assert (select status from public.premios where id = px) = 'passou', 'AC4: X passou';
  assert (select user_id from pg_temp.dono()) = '6b000000-0000-0000-0000-00000000000b', 'AC4: Y recebe';
  r := public.premiacao_op_validar('op@neu168.test', cx, '2020-06-01 15:35+00');
  assert r->>'resultado' = 'invalido', 'AC3: codigo de premio que passou -> invalido';

  r := public.premiacao_op_acao('op@neu168.test', pg_temp.premio_de('6b000000-0000-0000-0000-00000000000b'), 'cancelar', null, '2020-06-01 15:36+00');
  assert r->>'ok' = 'false', 'AC4: cancelar pede motivo';
  r := public.premiacao_op_acao('op@neu168.test', pg_temp.premio_de('6b000000-0000-0000-0000-00000000000b'), 'cancelar', 'premio acabou', '2020-06-01 15:36+00');
  assert r->>'ok' = 'true' and not exists (select 1 from pg_temp.dono()), 'AC4: cancelado encerra a rodada';
  r := public.premiacao_op_acao('op@neu168.test', pg_temp.premio_de('6b000000-0000-0000-0000-00000000000b'), 'passar', null, '2020-06-01 15:37+00');
  assert r->>'ok' = 'false', 'AC4: passar um premio cancelado -> ok false';
  assert exists (select 1 from public.premiacao_registro where operador = 'op@neu168.test' and acao = 'cancelar' and detalhe = 'premio acabou'),
    'AC7: cancelar fica no registro com o motivo';
end $$;

-- premio de outro evento: nenhuma acao vale (o painel so mostra o evento atual)
select pg_temp.limpa();
do $$
declare r jsonb; px uuid;
begin
  perform public.premiacao_tick('2020-06-01 15:05+00');
  px := (select id from pg_temp.dono());
  update public.premiacao_config set evento_atual = 'OUTRO';
  r := public.premiacao_op_acao('op@neu168.test', px, 'passar', null, '2020-06-01 15:06+00');
  assert r->>'ok' = 'false', 'acao em premio de outro evento -> ok false, veio ' || r::text;
  assert (select status from public.premios where id = px) = 'avisado', 'premio de outro evento nao muda';
  update public.premiacao_config set evento_atual = 'TESTE';
end $$;

-- prazo estourado e ninguem passou: o codigo ainda vale e o operador entrega (duvida do Pedro, 21/10)
select pg_temp.limpa();
do $$
declare r jsonb; cx text;
begin
  perform public.premiacao_tick('2020-06-01 15:05+00');
  cx := (select code from pg_temp.dono());
  perform public.premiacao_tick('2020-06-01 15:21+00');
  assert (select status from pg_temp.dono()) = 'prazo_estourou', 'prazo estourou';
  r := public.premiacao_op_validar('op@neu168.test', cx, '2020-06-01 15:25+00');
  assert r->>'resultado' = 'entregue' and (select status from pg_temp.dono()) = 'entregue',
    'AC3: codigo de prazo estourado ainda vale ate o operador passar, veio ' || r::text;
end $$;

-- entregue sem codigo
select pg_temp.limpa();
do $$
declare r jsonb;
begin
  perform public.premiacao_tick('2020-06-01 15:05+00');
  r := public.premiacao_op_acao('op@neu168.test', (select id from pg_temp.dono()), 'entregue_sem_codigo', 'esqueceu o celular', '2020-06-01 15:08+00');
  assert r->>'ok' = 'true' and (select status from pg_temp.dono()) = 'entregue', 'AC4: entregue sem codigo';
end $$;

-- continuar respeita os elegiveis: Y ja ganhou no evento -> pula para Z
select pg_temp.limpa();
do $$
declare r jsonb; px uuid;
begin
  insert into public.premiacao_rodadas (round_id, evento, fechada_em, corte_em)
  values ('6b200000-0000-0000-0000-000000000000', 'TESTE', '2019-12-31 11:05+00', '2019-12-31 11:05+00');
  insert into public.premios (round_id, evento, user_id, posicao, display_name, score, status, entregue_em, criado_em, atualizado_em)
  values ('6b200000-0000-0000-0000-000000000000', 'TESTE', '6b000000-0000-0000-0000-00000000000b', 1, 'O168Y', 20, 'entregue',
          '2019-12-31 11:10+00', '2019-12-31 11:05+00', '2019-12-31 11:10+00');
  update public.premiacao_config set limite_fila = 1;
  perform public.premiacao_tick('2020-06-01 15:05+00');            -- X, 1a vez
  px := (select id from pg_temp.dono());
  r := public.premiacao_op_acao('op@neu168.test', px, 'passar', null, '2020-06-01 15:06+00');
  assert (select status from public.premios where id = px) = 'sem_retirada', 'AC4: com limite 1, passar esgota a fila';
  r := public.premiacao_op_acao('op@neu168.test', px, 'continuar', null, '2020-06-01 15:07+00');
  assert r->>'ok' = 'true', 'AC4: continuar depois do limite, veio ' || r::text;
  assert (select user_id from pg_temp.dono()) = '6b000000-0000-0000-0000-00000000000c', 'AC4: continuar pula Y (ja ganhou) e da a vez a Z';
  assert (select posicao from pg_temp.dono()) = 2, 'AC4: Z na 2a vez';
  assert (select status from public.premios where id = px) = 'passou', 'AC4: o turno esgotado vira passou';
end $$;

-- sortear entre quem jogou e e elegivel; guardar encerra
select pg_temp.limpa();
do $$
declare r jsonb; px uuid; sorteado uuid;
begin
  update public.premiacao_config set limite_fila = 1;
  perform public.premiacao_tick('2020-06-01 15:05+00');
  px := (select id from pg_temp.dono());
  perform public.premiacao_op_acao('op@neu168.test', px, 'passar', null, '2020-06-01 15:06+00');
  r := public.premiacao_op_acao('op@neu168.test', px, 'sortear', null, '2020-06-01 15:07+00');
  assert r->>'ok' = 'true', 'AC4: sortear, veio ' || r::text;
  sorteado := (select user_id from pg_temp.dono());
  assert sorteado in ('6b000000-0000-0000-0000-00000000000b','6b000000-0000-0000-0000-00000000000c','6b000000-0000-0000-0000-00000000000d'),
    'AC4: sorteio entre quem jogou e ainda nao teve a vez';
end $$;
select pg_temp.limpa();
do $$
declare r jsonb; px uuid;
begin
  update public.premiacao_config set limite_fila = 1;
  perform public.premiacao_tick('2020-06-01 15:05+00');
  px := (select id from pg_temp.dono());
  perform public.premiacao_op_acao('op@neu168.test', px, 'passar', null, '2020-06-01 15:06+00');
  r := public.premiacao_op_acao('op@neu168.test', px, 'guardar', null, '2020-06-01 15:07+00');
  assert r->>'ok' = 'true' and (select status from public.premios where id = px) = 'cancelado'
     and not exists (select 1 from pg_temp.dono()), 'AC4: guardar encerra a rodada sem dono';
end $$;

-- ===== AC5: config =====
select pg_temp.limpa();
do $$
declare c jsonb; falhou boolean; m text;
begin
  update public.premiacao_config set premiacao_ligada = false, ligada_em = null;
  c := public.premiacao_op_config('op@neu168.test', '{"pausa_geral": true}', '2020-06-01 15:00+00');
  assert (c->>'pausa_geral')::boolean and (select count(*) from jsonb_object_keys(c)) = 9, 'AC5: merge parcial devolve a config inteira (9 chaves)';
  assert exists (select 1 from public.premiacao_registro where operador = 'op@neu168.test' and acao = 'config'
                  and antes->>'pausa_geral' = 'false' and depois->>'pausa_geral' = 'true'), 'AC7: config no registro com antes e depois';
  c := public.premiacao_op_config('op@neu168.test', '{"premiacao_ligada": true}', '2020-06-01 15:00+00');
  assert (c->>'premiacao_ligada')::boolean and (c->>'ligada_em')::timestamptz = '2020-06-01 15:00+00', 'AC5: ligar grava ligada_em = agora';
  foreach m in array array['{"piso_tempo_s": 1}', '{"limite_fila": 0}', '{"nao_existe": 1}', '{"premiacao_ligada": "sim"}', '{"id": false}',
                            '{"limite_fila": "5"}', '{"pausa_geral": "true"}', '{"carencia_min": 2.5}', '{"evento_atual": 7}', '{"ligada_em": 5}'] loop
    falhou := false;
    begin
      perform public.premiacao_op_config('op@neu168.test', m::jsonb, '2020-06-01 15:00+00');
    exception when others then falhou := true;
    end;
    assert falhou, 'AC5: op_config recusa ' || m;
  end loop;
  assert (select piso_tempo_s from public.premiacao_config) = 15 and (select limite_fila from public.premiacao_config) = 5,
    'AC5: nada recusado foi gravado';
end $$;

-- os op_* publicos funcionam para o operador (forma da resposta)
set local role authenticated;
set local request.jwt.claims to '{"sub":"6b000000-0000-0000-0000-0000000000a1","role":"authenticated"}';
do $$
declare r jsonb;
begin
  r := public.op_validar_codigo('12a');
  assert r->>'resultado' = 'invalido', 'op_validar_codigo publico responde, veio ' || r::text;
  r := public.op_acao('00000000-0000-0000-0000-000000000000', 'passar');
  assert r->>'ok' = 'false' and r ? 'erro', 'op_acao publico: premio inexistente -> ok false';
  r := public.op_config('{"pausa_geral": false}');
  assert (r->>'pausa_geral')::boolean = false, 'op_config publico devolve a config';
end $$;
reset role;

rollback;
select 'premiacao_operadores_test OK' as result;
