\set ON_ERROR_STOP on

-- NEU-167: fechar a rodada, congelar o vencedor e gerar o codigo do premio.
-- Tudo numa transacao com ROLLBACK no fim: o seed e a configuracao nunca ficam.
-- O horario entra sempre por parametro (premiacao_tick(p_agora)); nada usa now().
--
-- Seed (UTC), evento 'TESTE', premiacao ligada em 2020-01-01:
--   R0 2019-12-31 10:00-11:00 (antes de ligada_em)
--   R1 2020-06-01 14:00-15:00: A 40,1 s (14:30) | A pelo celular 40,5 s (14:50) | B 41,0 s (14:40)
--                              D 42 s | E 43 s | F 44 s | G 45 s | C 39 s terminou 14:59 e CHEGOU 15:06
--                              D 0,45 s (14:55): abaixo do piso de tempo (NEU-179), nao vale
--   R2 2020-06-01 15:00-16:00: B 30 s | A 31 s | C 32 s
--   R3 2020-06-01 16:00-17:00: so um jogador sem conta (ligado a conta depois do fechamento)

begin;

update public.premiacao_config set
  premiacao_ligada = true, ligada_em = '2020-01-01 00:00+00', evento_atual = 'TESTE',
  carencia_min = 5, janela_min = 15, lembrete_min = 10, limite_fila = 5,
  passar_sozinho = false, pausa_geral = false;

insert into auth.users (instance_id, id, aud, role, email, created_at, updated_at) values
 ('00000000-0000-0000-0000-000000000000','67a00000-0000-0000-0000-00000000000a','authenticated','authenticated','pr_a@neu167.test','2020-01-01 00:00+00','2020-01-01 00:00+00'),
 ('00000000-0000-0000-0000-000000000000','67a00000-0000-0000-0000-00000000000b','authenticated','authenticated','pr_b@neu167.test','2020-01-01 00:00+00','2020-01-01 00:00+00'),
 ('00000000-0000-0000-0000-000000000000','67a00000-0000-0000-0000-00000000000c','authenticated','authenticated','pr_c@neu167.test','2020-01-01 00:00+00','2020-01-01 00:00+00'),
 ('00000000-0000-0000-0000-000000000000','67a00000-0000-0000-0000-00000000000d','authenticated','authenticated','pr_d@neu167.test','2020-01-01 00:00+00','2020-01-01 00:00+00'),
 ('00000000-0000-0000-0000-000000000000','67a00000-0000-0000-0000-00000000000e','authenticated','authenticated','pr_e@neu167.test','2020-01-01 00:00+00','2020-01-01 00:00+00'),
 ('00000000-0000-0000-0000-000000000000','67a00000-0000-0000-0000-00000000000f','authenticated','authenticated','pr_f@neu167.test','2020-01-01 00:00+00','2020-01-01 00:00+00'),
 ('00000000-0000-0000-0000-000000000000','67a00000-0000-0000-0000-000000000010','authenticated','authenticated','pr_g@neu167.test','2020-01-01 00:00+00','2020-01-01 00:00+00');
update public.profiles set display_name = 'P167A' where id = '67a00000-0000-0000-0000-00000000000a';
update public.profiles set display_name = 'P167B' where id = '67a00000-0000-0000-0000-00000000000b';
update public.profiles set display_name = 'P167C' where id = '67a00000-0000-0000-0000-00000000000c';
update public.profiles set display_name = 'P167D' where id = '67a00000-0000-0000-0000-00000000000d';
update public.profiles set display_name = 'P167E' where id = '67a00000-0000-0000-0000-00000000000e';
update public.profiles set display_name = 'P167F' where id = '67a00000-0000-0000-0000-00000000000f';
update public.profiles set display_name = 'P167G' where id = '67a00000-0000-0000-0000-000000000010';

-- A tem dois jogadores na mesma conta: o do e-mail e o do celular (NEU-159).
insert into public.players (id, email, phone, user_id) values
 ('67b00000-0000-0000-0000-00000000000a','pr_a@neu167.test', null,'67a00000-0000-0000-0000-00000000000a'),
 ('67b00000-0000-0000-0000-0000000000a2', null,'+5511912345670','67a00000-0000-0000-0000-00000000000a'),
 ('67b00000-0000-0000-0000-00000000000b','pr_b@neu167.test', null,'67a00000-0000-0000-0000-00000000000b'),
 ('67b00000-0000-0000-0000-00000000000c','pr_c@neu167.test', null,'67a00000-0000-0000-0000-00000000000c'),
 ('67b00000-0000-0000-0000-00000000000d','pr_d@neu167.test', null,'67a00000-0000-0000-0000-00000000000d'),
 ('67b00000-0000-0000-0000-00000000000e','pr_e@neu167.test', null,'67a00000-0000-0000-0000-00000000000e'),
 ('67b00000-0000-0000-0000-00000000000f','pr_f@neu167.test', null,'67a00000-0000-0000-0000-00000000000f'),
 ('67b00000-0000-0000-0000-000000000010','pr_g@neu167.test', null,'67a00000-0000-0000-0000-000000000010'),
 ('67b00000-0000-0000-0000-000000000099','pr_semconta@neu167.test', null, null);

insert into public.ranking_windows (id, name, starts_at, ends_at) values
 ('67c00000-0000-0000-0000-000000000000','P167 Rodada 0','2019-12-31 10:00+00','2019-12-31 11:00+00'),
 ('67c00000-0000-0000-0000-000000000001','P167 Rodada 1','2020-06-01 14:00+00','2020-06-01 15:00+00'),
 ('67c00000-0000-0000-0000-000000000002','P167 Rodada 2','2020-06-01 15:00+00','2020-06-01 16:00+00'),
 ('67c00000-0000-0000-0000-000000000003','P167 Rodada 3','2020-06-01 16:00+00','2020-06-01 17:00+00');

-- corrida: (n, jogador, segundos, terminou, chegou na nuvem)
create function pg_temp.corrida(n int, jogador uuid, segundos numeric, terminou timestamptz, chegou timestamptz)
returns void language sql as $$
  insert into public.races (id, started_at)
  values (('67d00000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid, terminou - make_interval(secs => segundos));
  insert into public.race_players (id, idempotency_key, race_id, player_id, player_slot, source, started_at, finished_at, created_at)
  values (('67e00000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
          ('67f00000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
          ('67d00000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
          jogador, 1, 'real', terminou - make_interval(secs => segundos), terminou, chegou);
$$;
select pg_temp.corrida( 1,'67b00000-0000-0000-0000-00000000000b',10.0,'2019-12-31 10:30+00','2019-12-31 10:30+00');
select pg_temp.corrida(11,'67b00000-0000-0000-0000-00000000000a',40.1,'2020-06-01 14:30+00','2020-06-01 14:30+00');
select pg_temp.corrida(12,'67b00000-0000-0000-0000-0000000000a2',40.5,'2020-06-01 14:50+00','2020-06-01 14:50+00');
select pg_temp.corrida(13,'67b00000-0000-0000-0000-00000000000b',41.0,'2020-06-01 14:40+00','2020-06-01 14:40+00');
select pg_temp.corrida(14,'67b00000-0000-0000-0000-00000000000d',42.0,'2020-06-01 14:41+00','2020-06-01 14:41+00');
select pg_temp.corrida(15,'67b00000-0000-0000-0000-00000000000e',43.0,'2020-06-01 14:42+00','2020-06-01 14:42+00');
select pg_temp.corrida(16,'67b00000-0000-0000-0000-00000000000f',44.0,'2020-06-01 14:43+00','2020-06-01 14:43+00');
select pg_temp.corrida(17,'67b00000-0000-0000-0000-00000000000c',39.0,'2020-06-01 14:59+00','2020-06-01 15:06+00');
select pg_temp.corrida(18,'67b00000-0000-0000-0000-000000000010',45.0,'2020-06-01 14:44+00','2020-06-01 14:44+00');
select pg_temp.corrida(19,'67b00000-0000-0000-0000-00000000000d', 0.45,'2020-06-01 14:55+00','2020-06-01 14:55+00');
select pg_temp.corrida(21,'67b00000-0000-0000-0000-00000000000b',30.0,'2020-06-01 15:30+00','2020-06-01 15:30+00');
select pg_temp.corrida(22,'67b00000-0000-0000-0000-00000000000a',31.0,'2020-06-01 15:31+00','2020-06-01 15:31+00');
select pg_temp.corrida(23,'67b00000-0000-0000-0000-00000000000c',32.0,'2020-06-01 15:32+00','2020-06-01 15:32+00');
select pg_temp.corrida(31,'67b00000-0000-0000-0000-000000000099',20.0,'2020-06-01 16:30+00','2020-06-01 16:30+00');

-- Volta ao estado inicial entre cenarios (dentro da mesma transacao).
create function pg_temp.limpa() returns void language sql as $$
  delete from public.premios;
  delete from public.premiacao_rodadas;
  delete from public.premiacao_registro;
  update public.premiacao_config set passar_sozinho = false, pausa_geral = false, limite_fila = 5, piso_tempo_s = 15,
    premiacao_ligada = true, ligada_em = '2020-01-01 00:00+00', evento_atual = 'TESTE';
$$;

create function pg_temp.dono(rodada uuid) returns table (user_id uuid, status text, code text, prazo timestamptz, posicao int, score numeric, display_name text)
language sql as $$
  select p.user_id, p.status, p.code, p.prazo, p.posicao, p.score, p.display_name
  from public.premios p
  where p.round_id = rodada and p.status in ('avisando','avisado','prazo_estourou','aviso_falhou','entregue');
$$;

-- ===== AC1, AC2, AC5, AC6, AC10, AC14: congelamento =====
do $$
declare d record; n int;
begin
  perform public.premiacao_tick('2020-06-01 15:04+00');
  assert (select count(*) from public.premios) = 0, 'AC1: antes de fim + carencia nao ha premio';
  assert (select count(*) from public.premiacao_rodadas) = 0, 'AC1: rodada ainda nao fechou';

  perform public.premiacao_tick('2020-06-01 15:05+00');
  select * into d from pg_temp.dono('67c00000-0000-0000-0000-000000000001');
  assert d.user_id = '67a00000-0000-0000-0000-00000000000a', 'AC1/AC2: o premio da R1 e de A (C chegou depois do corte), veio ' || coalesce(d.user_id::text,'ninguem');
  assert d.status = 'avisado', 'AC6/D3: sem canal, o premio nasce avisado, veio ' || d.status;
  assert d.code ~ '^[0-9]{6}$', 'AC1: codigo de 6 digitos, veio ' || coalesce(d.code,'null');
  assert d.prazo = '2020-06-01 15:20+00', 'D3: a janela de 15 min comeca no congelamento, veio ' || d.prazo;
  assert d.posicao = 1 and d.score = 40.1 and d.display_name = 'P167A', 'AC1: posicao, tempo e apelido congelados';
  assert not exists (select 1 from public.premios where status in ('avisando','aviso_falhou','aguardando_fechamento')),
    'AC6/D3: sem canal, nenhum premio fica avisando/aviso_falhou';
  assert not exists (select 1 from public.premiacao_rodadas where round_id = '67c00000-0000-0000-0000-000000000000'),
    'AC10: rodada que acabou antes de ligada_em fica de fora';

  select count(*) into n from public.premiacao_candidatos('67c00000-0000-0000-0000-000000000001', '2020-06-01 15:05+00')
   where user_id = '67a00000-0000-0000-0000-00000000000a';
  assert n = 1, 'AC5: a conta de A com dois jogadores e um candidato so, veio ' || n;
  assert (select score from public.premiacao_candidatos('67c00000-0000-0000-0000-000000000001', '2020-06-01 15:05+00')
           where user_id = '67a00000-0000-0000-0000-00000000000a') = 40.1, 'AC5: vale a melhor corrida da conta';

  perform public.premiacao_tick('2020-06-01 15:05+00');
  assert (select piso_tempo_s from public.premiacao_config) = 15, 'piso: padrao de 15 s';
  assert not exists (select 1 from public.premiacao_candidatos('67c00000-0000-0000-0000-000000000001', '2020-06-01 15:05+00')
                      where score < 15), 'piso: corrida de 0,45 s (NEU-179) nao entra';
  assert (select score from public.premiacao_candidatos('67c00000-0000-0000-0000-000000000001', '2020-06-01 15:05+00')
           where user_id = '67a00000-0000-0000-0000-00000000000d') = 42,
    'piso: D continua concorrendo com a corrida valida (42 s)';

  perform public.premiacao_tick('2020-06-01 15:06+00');
  assert (select count(*) from public.premios) = 1, 'AC14: tick repetido nao duplica premio';
  assert (select count(*) from public.premiacao_rodadas) = 1, 'AC14: tick repetido nao duplica fechamento';
  assert exists (select 1 from public.premiacao_registro where acao = 'fechou_rodada'
                  and round_id = '67c00000-0000-0000-0000-000000000001' and operador = 'automacao'),
    'registro: o fechamento fica gravado';
end $$;

-- ===== AC7: prazo estourado, sem e com passar_sozinho =====
do $$
declare d record; antes text; b record;
begin
  select code into antes from pg_temp.dono('67c00000-0000-0000-0000-000000000001');
  perform public.premiacao_tick('2020-06-01 15:19+00');
  assert (select status from pg_temp.dono('67c00000-0000-0000-0000-000000000001')) = 'avisado', 'AC7: antes do prazo segue avisado';

  perform public.premiacao_tick('2020-06-01 15:20+00');
  select * into d from pg_temp.dono('67c00000-0000-0000-0000-000000000001');
  assert d.user_id = '67a00000-0000-0000-0000-00000000000a' and d.status = 'prazo_estourou',
    'AC7: prazo estourado sem passar_sozinho fica com A em prazo_estourou';
  assert d.code = antes, 'AC7: o codigo de A continua o mesmo e valendo';
  perform public.premiacao_tick('2020-06-01 15:40+00');
  assert (select user_id from pg_temp.dono('67c00000-0000-0000-0000-000000000001')) = '67a00000-0000-0000-0000-00000000000a',
    'AC7: sem passar_sozinho o premio nao passa sozinho';

  update public.premiacao_config set passar_sozinho = true;
  perform public.premiacao_tick('2020-06-01 15:41+00');
  assert (select status from public.premios where round_id = '67c00000-0000-0000-0000-000000000001'
           and user_id = '67a00000-0000-0000-0000-00000000000a') = 'passou', 'AC7: com passar_sozinho o turno de A vira passou';
  select * into b from pg_temp.dono('67c00000-0000-0000-0000-000000000001');
  assert b.user_id = '67a00000-0000-0000-0000-00000000000b', 'AC7: o premio vai para B';
  assert b.status = 'avisado' and b.code ~ '^[0-9]{6}$' and b.prazo = '2020-06-01 15:56+00' and b.posicao = 2,
    'AC7: B ganha turno avisado, codigo novo, janela a partir de agora';
end $$;

-- ===== AC8: fila esgotada e rodada sem candidato =====
select pg_temp.limpa();
do $$
begin
  update public.premiacao_config set limite_fila = 2, passar_sozinho = true;
  perform public.premiacao_tick('2020-06-01 15:05+00');   -- A
  perform public.premiacao_tick('2020-06-01 15:20+00');   -- A estoura e passa para B (2o)
  assert (select user_id from pg_temp.dono('67c00000-0000-0000-0000-000000000001')) = '67a00000-0000-0000-0000-00000000000b',
    'AC8: com limite 2 o premio desce ate B';
  perform public.premiacao_tick('2020-06-01 15:35+00');   -- B estoura; o 3o passa do limite
  assert not exists (select 1 from pg_temp.dono('67c00000-0000-0000-0000-000000000001')), 'AC8: depois do limite ninguem fica com o premio';
  assert (select status from public.premios where round_id = '67c00000-0000-0000-0000-000000000001'
           and user_id = '67a00000-0000-0000-0000-00000000000b') = 'sem_retirada', 'AC8: o ultimo turno fica sem_retirada';
  assert (select count(*) from public.premios where round_id = '67c00000-0000-0000-0000-000000000001') = 2,
    'AC8: nenhum turno alem do limite';

  -- R3: so um jogador sem conta. Fecha sem premio e nao reabre quando ele cria a conta.
  perform public.premiacao_tick('2020-06-01 17:05+00');
  assert exists (select 1 from public.premiacao_rodadas where round_id = '67c00000-0000-0000-0000-000000000003'),
    'AC8: rodada sem candidato tambem fecha';
  update public.players set user_id = '67a00000-0000-0000-0000-000000000010' where id = '67b00000-0000-0000-0000-000000000099';
  perform public.premiacao_tick('2020-06-01 17:10+00');
  assert not exists (select 1 from public.premios where round_id = '67c00000-0000-0000-0000-000000000003'),
    'AC14: rodada fechada nao reabre';
  update public.players set user_id = null where id = '67b00000-0000-0000-0000-000000000099';
end $$;

-- ===== AC3, AC13 (D2, D4): quem ja ganhou no evento nao ganha de novo =====
select pg_temp.limpa();
do $$
declare s text;
begin
  perform public.premiacao_tick('2020-06-01 15:05+00');                 -- R1: A
  -- R2: B 30 s, A 31 s. Para cada estado de D2, B ainda e o dono da R1.
  update public.premios set user_id = '67a00000-0000-0000-0000-00000000000b', display_name = 'P167B'
   where round_id = '67c00000-0000-0000-0000-000000000001';
  foreach s in array array['avisando','avisado','prazo_estourou','aviso_falhou','entregue'] loop
    update public.premios set status = s, entregue_em = case when s = 'entregue' then '2020-06-01 15:10+00'::timestamptz end
     where round_id = '67c00000-0000-0000-0000-000000000001';
    delete from public.premios where round_id = '67c00000-0000-0000-0000-000000000002';
    delete from public.premiacao_rodadas where round_id = '67c00000-0000-0000-0000-000000000002';
    perform public.premiacao_tick('2020-06-01 16:05+00');
    assert (select user_id from pg_temp.dono('67c00000-0000-0000-0000-000000000002')) = '67a00000-0000-0000-0000-00000000000a',
      'AC3/D2: com B em ' || s || ' na R1, a R2 vai para A';
  end loop;

  -- D4: quem recusou, perdeu a vez ou ficou sem retirada volta a ser elegivel.
  foreach s in array array['recusado','passou','sem_retirada','cancelado'] loop
    update public.premios set status = s, entregue_em = null where round_id = '67c00000-0000-0000-0000-000000000001';
    delete from public.premios where round_id = '67c00000-0000-0000-0000-000000000002';
    delete from public.premiacao_rodadas where round_id = '67c00000-0000-0000-0000-000000000002';
    perform public.premiacao_tick('2020-06-01 16:05+00');
    assert (select user_id from pg_temp.dono('67c00000-0000-0000-0000-000000000002')) = '67a00000-0000-0000-0000-00000000000b',
      'AC13/D4: com B em ' || s || ' na R1, B volta a poder ganhar a R2';
  end loop;
end $$;

-- ===== limite da fila = 5 vezes entre os ELEGIVEIS (revisao do #15) =====
-- Os 5 primeiros da R1 (A, B, D, E, F) ja ganharam no evento -> o 6o (G) ganha, na 1a vez.
select pg_temp.limpa();
do $$
declare d record;
begin
  -- uma rodada antiga por premio (um dono por rodada)
  insert into public.ranking_windows (id, name, starts_at, ends_at)
  select ('67c10000-0000-0000-0000-00000000000' || i)::uuid, 'P167 Antiga ' || i,
         '2019-11-01 00:00+00'::timestamptz + make_interval(hours => i), '2019-11-01 00:30+00'::timestamptz + make_interval(hours => i)
  from generate_series(1, 5) as i;
  insert into public.premiacao_rodadas (round_id, evento, fechada_em, corte_em)
  select ('67c10000-0000-0000-0000-00000000000' || i)::uuid, 'TESTE', '2019-11-02 00:00+00', '2019-11-02 00:00+00'
  from generate_series(1, 5) as i;
  insert into public.premios (round_id, evento, user_id, posicao, display_name, score, status, entregue_em, criado_em, atualizado_em)
  select ('67c10000-0000-0000-0000-00000000000' || x.i)::uuid, 'TESTE', x.u, 1, 'x', 20, 'entregue',
         '2019-11-02 00:10+00', '2019-11-02 00:00+00', '2019-11-02 00:10+00'
  from unnest(array['67a00000-0000-0000-0000-00000000000a','67a00000-0000-0000-0000-00000000000b','67a00000-0000-0000-0000-00000000000d',
                    '67a00000-0000-0000-0000-00000000000e','67a00000-0000-0000-0000-00000000000f']::uuid[]) with ordinality as x(u, i);
  perform public.premiacao_tick('2020-06-01 15:05+00');
  select * into d from pg_temp.dono('67c00000-0000-0000-0000-000000000001');
  assert d.user_id = '67a00000-0000-0000-0000-000000000010', 'limite: com os 5 primeiros ja premiados, o 6o (G) ganha; veio ' || coalesce(d.user_id::text, 'ninguem');
  assert d.posicao = 1, 'limite: posicao e a vez na fila (1a), nao a colocacao; veio ' || d.posicao;
end $$;

-- ===== AC4: premio em outro evento nao conta =====
select pg_temp.limpa();
do $$
begin
  insert into public.premiacao_rodadas (round_id, evento, fechada_em, corte_em)
  values ('67c00000-0000-0000-0000-000000000000', 'BANCA', '2019-12-31 11:05+00', '2019-12-31 11:05+00');
  insert into public.premios (round_id, evento, user_id, posicao, display_name, score, status, entregue_em, criado_em, atualizado_em)
  values ('67c00000-0000-0000-0000-000000000000', 'BANCA', '67a00000-0000-0000-0000-00000000000a', 1, 'P167A', 9.9,
          'entregue', '2019-12-31 11:10+00', '2019-12-31 11:05+00', '2019-12-31 11:10+00');
  perform public.premiacao_tick('2020-06-01 15:05+00');
  assert (select user_id from pg_temp.dono('67c00000-0000-0000-0000-000000000001')) = '67a00000-0000-0000-0000-00000000000a',
    'AC4: premio da banca (outro evento) nao impede A de ganhar no evento atual';
end $$;

-- ===== AC9: pausa geral; AC10: premiacao desligada =====
select pg_temp.limpa();
do $$
begin
  update public.premiacao_config set pausa_geral = true;
  perform public.premiacao_tick('2020-06-01 15:05+00');
  assert (select count(*) from public.premios) = 0 and (select count(*) from public.premiacao_rodadas) = 0,
    'AC9: pausa geral nao fecha rodada';

  update public.premiacao_config set pausa_geral = false;
  perform public.premiacao_tick('2020-06-01 15:05+00');
  update public.premiacao_config set pausa_geral = true;
  perform public.premiacao_tick('2020-06-01 15:30+00');
  assert (select status from pg_temp.dono('67c00000-0000-0000-0000-000000000001')) = 'avisado',
    'AC9: pausa geral nao muda estado nem com o prazo vencido';

  update public.premiacao_config set pausa_geral = false, premiacao_ligada = false;
  perform public.premiacao_tick('2020-06-01 17:05+00');
  assert not exists (select 1 from public.premiacao_rodadas where round_id <> '67c00000-0000-0000-0000-000000000001'),
    'AC10: premiacao desligada nao fecha rodada';
end $$;

-- ===== invariantes no banco =====
select pg_temp.limpa();
do $$
declare bloqueado boolean;
begin
  perform public.premiacao_tick('2020-06-01 15:05+00');   -- R1: A avisado
  bloqueado := false;
  begin
    insert into public.premios (round_id, evento, user_id, posicao, display_name, score, status, code, prazo, criado_em, atualizado_em)
    values ('67c00000-0000-0000-0000-000000000001','TESTE','67a00000-0000-0000-0000-00000000000b',2,'P167B',41.0,'avisado','000001',
            '2020-06-01 15:20+00','2020-06-01 15:05+00','2020-06-01 15:05+00');
  exception when unique_violation then bloqueado := true;
  end;
  assert bloqueado, 'invariante: no maximo um dono valendo por rodada';

  bloqueado := false;
  begin
    insert into public.premiacao_rodadas (round_id, evento, fechada_em, corte_em)
    values ('67c00000-0000-0000-0000-000000000002','TESTE','2020-06-01 16:05+00','2020-06-01 16:05+00');
    insert into public.premios (round_id, evento, user_id, posicao, display_name, score, status, code, prazo, criado_em, atualizado_em)
    values ('67c00000-0000-0000-0000-000000000002','TESTE','67a00000-0000-0000-0000-00000000000a',2,'P167A',31.0,'avisado','000002',
            '2020-06-01 16:20+00','2020-06-01 16:05+00','2020-06-01 16:05+00');
  exception when unique_violation then bloqueado := true;
  end;
  assert bloqueado, 'invariante: no maximo um premio valendo por conta no evento';

  bloqueado := false;
  begin
    update public.premios set status = 'prazo estourou' where round_id = '67c00000-0000-0000-0000-000000000001';
  exception when check_violation then bloqueado := true;
  end;
  assert bloqueado, 'contrato: estados so em snake_case';
end $$;

-- ===== o servidor (service_role) consegue rodar o tick inteiro =====
select pg_temp.limpa();
set local role service_role;
do $$
begin
  assert (public.premiacao_tick('2020-06-01 16:05+00') ->> 'fechou')::int = 2, 'service_role: tick fecha R1 e R2';
end $$;
reset role;
do $$
begin
  assert (select user_id from pg_temp.dono('67c00000-0000-0000-0000-000000000001')) = '67a00000-0000-0000-0000-00000000000a',
    'service_role: R1 com A';
end $$;

-- ===== um erro numa rodada nao trava o tick =====
-- Simula uma falha ao gerar o codigo (a troca da funcao e desfeita no ROLLBACK do fim).
select pg_temp.limpa();
create or replace function public.premio_novo_codigo() returns text language plpgsql as $$
begin raise exception 'falha simulada'; end $$;
do $$
declare r jsonb;
begin
  r := public.premiacao_tick('2020-06-01 17:05+00');
  assert (r ->> 'erros')::int = 2 and (r ->> 'fechou')::int = 1,
    'isolamento: R1 e R2 falham, R3 (sem candidato) fecha; veio ' || r::text;
  assert (select count(*) from public.premiacao_rodadas) = 1, 'isolamento: rodada que falhou nao fica meio fechada';
  assert (select count(*) from public.premiacao_registro where acao = 'erro' and detalhe like '%falha simulada%') = 2,
    'isolamento: o erro fica no registro';
  -- o tick tenta de novo no minuto seguinte, mas o mesmo erro nao e gravado de novo
  r := public.premiacao_tick('2020-06-01 17:06+00');
  assert (r ->> 'erros')::int = 2, 'isolamento: tenta de novo a cada minuto';
  assert (select count(*) from public.premiacao_registro where acao = 'erro') = 2,
    'isolamento: o mesmo erro nao enche o registro';
end $$;

rollback;
select 'premiacao_test OK' as result;
