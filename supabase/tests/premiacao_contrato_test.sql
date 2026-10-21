\set ON_ERROR_STOP on

-- NEU-167: permissao (AC11) e forma exata do contrato que o site ja consome (AC12):
--   get_my_prize()         -> web main lib/prize.ts (NEU-171)
--   get_official_winners() -> web PR #31 lib/ranking-data.ts (NEU-173)
-- Tudo numa transacao com ROLLBACK no fim. Nada usa now(): as rodadas sao de 2020.

-- ===== AC12: assinaturas iguais as do site =====
do $$
begin
  assert pg_get_function_result('public.get_my_prize()'::regprocedure)
       = 'TABLE(round_name text, status text, code text, claim_deadline timestamp with time zone, delivered_at timestamp with time zone)',
    'AC12: get_my_prize mudou de forma: ' || pg_get_function_result('public.get_my_prize()'::regprocedure);
  assert pg_get_function_result('public.get_official_winners()'::regprocedure)
       = 'TABLE(round_id uuid, round_name text, display_name text, score numeric)',
    'AC12: get_official_winners mudou de forma: ' || pg_get_function_result('public.get_official_winners()'::regprocedure);
end $$;

-- ===== AC11: ninguem de fora le ou escreve as tabelas nem chama as funcoes internas =====
do $$
declare t text; r text; p text;
begin
  foreach t in array array['public.premiacao_config','public.premiacao_rodadas','public.premios','public.premiacao_registro'] loop
    foreach r in array array['anon','authenticated'] loop
      foreach p in array array['SELECT','INSERT','UPDATE','DELETE','TRUNCATE'] loop
        assert not has_table_privilege(r, t, p), format('AC11: %s nao pode %s em %s', r, p, t);
      end loop;
    end loop;
  end loop;
  foreach t in array array['public.premiacao_tick(timestamptz)',
                           'public.premiacao_candidatos(uuid, timestamptz)',
                           'public.premio_dar_vez(uuid, timestamptz)',
                           'public.premio_passar(uuid, text, timestamptz, text, text)',
                           'public.premio_novo_codigo()',
                           'public.premiacao_registra_erro(timestamptz, uuid, uuid, text)'] loop
    foreach r in array array['anon','authenticated','public'] loop
      assert not has_function_privilege(r, t, 'EXECUTE'), format('AC11: %s nao pode chamar %s', r, t);
    end loop;
    -- o tick chama as outras: o service_role (servidor) precisa de todas, de forma explicita
    assert exists (select 1 from pg_proc pp, aclexplode(pp.proacl) a
                   where pp.oid = t::regprocedure and a.grantee = 'service_role'::regrole and a.privilege_type = 'EXECUTE'),
      format('service_role precisa de EXECUTE explicito em %s', t);
  end loop;
  assert not has_function_privilege('anon', 'public.get_my_prize()', 'EXECUTE'), 'AC11: anon nao chama get_my_prize';
  assert not has_function_privilege('public', 'public.get_my_prize()', 'EXECUTE'), 'AC11: public nao chama get_my_prize';
  assert has_function_privilege('authenticated', 'public.get_my_prize()', 'EXECUTE'), 'AC11: authenticated chama get_my_prize';
  assert has_function_privilege('anon', 'public.get_official_winners()', 'EXECUTE'), 'AC12: anon chama get_official_winners (telao)';
  assert has_function_privilege('authenticated', 'public.get_official_winners()', 'EXECUTE'), 'AC12: authenticated chama get_official_winners';
end $$;

begin;

update public.premiacao_config set
  premiacao_ligada = true, ligada_em = '2020-01-01 00:00+00', evento_atual = 'TESTE',
  carencia_min = 5, janela_min = 15, limite_fila = 5, passar_sozinho = true, pausa_geral = false;

insert into auth.users (instance_id, id, aud, role, email, created_at, updated_at) values
 ('00000000-0000-0000-0000-000000000000','68a00000-0000-0000-0000-00000000000a','authenticated','authenticated','ct_a@neu167.test','2020-01-01 00:00+00','2020-01-01 00:00+00'),
 ('00000000-0000-0000-0000-000000000000','68a00000-0000-0000-0000-00000000000b','authenticated','authenticated','ct_b@neu167.test','2020-01-01 00:00+00','2020-01-01 00:00+00');
update public.profiles set display_name = 'C167A' where id = '68a00000-0000-0000-0000-00000000000a';
update public.profiles set display_name = 'C167B' where id = '68a00000-0000-0000-0000-00000000000b';
insert into public.players (id, email, user_id) values
 ('68b00000-0000-0000-0000-00000000000a','ct_a@neu167.test','68a00000-0000-0000-0000-00000000000a'),
 ('68b00000-0000-0000-0000-00000000000b','ct_b@neu167.test','68a00000-0000-0000-0000-00000000000b');
insert into public.ranking_windows (id, name, starts_at, ends_at) values
 ('68c00000-0000-0000-0000-000000000000','C167 Antes',   '2019-12-31 10:00+00','2019-12-31 11:00+00'),
 ('68c00000-0000-0000-0000-000000000001','C167 Rodada 1','2020-06-01 14:00+00','2020-06-01 15:00+00'),
 ('68c00000-0000-0000-0000-000000000002','C167 Rodada 2','2020-06-01 15:00+00','2020-06-01 16:00+00');
insert into public.races (id, started_at) values
 ('68d00000-0000-0000-0000-000000000001','2020-06-01 14:29:20+00'),
 ('68d00000-0000-0000-0000-000000000002','2020-06-01 14:39:19+00'),
 ('68d00000-0000-0000-0000-000000000003','2020-06-01 15:29:30+00');
insert into public.race_players (id, idempotency_key, race_id, player_id, player_slot, source, started_at, finished_at, created_at) values
 ('68e00000-0000-0000-0000-000000000001','68f00000-0000-0000-0000-000000000001','68d00000-0000-0000-0000-000000000001',
  '68b00000-0000-0000-0000-00000000000a',1,'real','2020-06-01 14:29:20+00','2020-06-01 14:30:00.125+00','2020-06-01 14:30:01+00'),
 ('68e00000-0000-0000-0000-000000000002','68f00000-0000-0000-0000-000000000002','68d00000-0000-0000-0000-000000000002',
  '68b00000-0000-0000-0000-00000000000b',1,'real','2020-06-01 14:39:19+00','2020-06-01 14:40:00+00','2020-06-01 14:40:01+00'),
 ('68e00000-0000-0000-0000-000000000003','68f00000-0000-0000-0000-000000000003','68d00000-0000-0000-0000-000000000003',
  '68b00000-0000-0000-0000-00000000000a',1,'real','2020-06-01 15:29:30+00','2020-06-01 15:30:00+00','2020-06-01 15:30:01+00');

-- R1 fecha (A 40,125 s), A estoura o prazo e o premio passa para B. R2 ainda na carencia.
select public.premiacao_tick('2020-06-01 15:05+00');
select public.premiacao_tick('2020-06-01 15:20+00');
update public.premiacao_config set passar_sozinho = false;

-- ===== AC12: get_official_winners (anon, como o telao) =====
set local role anon;
do $$
declare r1 record; r2 record;
begin
  assert (select count(*) from public.get_official_winners() where round_id = '68c00000-0000-0000-0000-000000000000') = 0,
    'AC12: rodada anterior a ligada_em nao tem linha (letreiro como hoje)';
  select * into r1 from public.get_official_winners() where round_id = '68c00000-0000-0000-0000-000000000001';
  assert r1.round_name = 'C167 Rodada 1' and r1.display_name = 'C167B' and r1.score = 41,
    format('AC12: R1 mostra o dono atual (B, 41 s), veio %s %s', r1.display_name, r1.score);
  select * into r2 from public.get_official_winners() where round_id = '68c00000-0000-0000-0000-000000000002';
  assert r2.round_id is not null and r2.display_name is null and r2.score is null,
    'AC12: R2 na carencia tem linha com apelido e tempo nulos (letreiro some)';
end $$;
reset role;

-- ===== AC11/AC12: get_my_prize como a pessoa logada =====
set local role authenticated;
set local request.jwt.claims to '{"sub":"68a00000-0000-0000-0000-00000000000a","role":"authenticated"}';
do $$
declare r record;
begin
  assert (select count(*) from public.get_my_prize()) = 1, 'AC11: A ve so a propria linha';
  select * into r from public.get_my_prize();
  assert r.round_name = 'C167 Rodada 1' and r.status = 'passou' and r.code is null,
    format('AC12: A perdeu a vez -> passou, sem codigo; veio %s %s', r.status, r.code);
end $$;
set local request.jwt.claims to '{"sub":"68a00000-0000-0000-0000-00000000000b","role":"authenticated"}';
do $$
declare r record;
begin
  assert (select count(*) from public.get_my_prize()) = 1, 'AC11: B ve so a propria linha';
  select * into r from public.get_my_prize();
  assert r.status = 'avisado' and r.code ~ '^[0-9]{6}$' and r.claim_deadline = '2020-06-01 15:35+00' and r.delivered_at is null,
    'AC12: B ve o codigo e a hora limite';
end $$;
set local request.jwt.claims to '{"role":"authenticated"}';
do $$
begin
  assert (select count(*) from public.get_my_prize()) = 0, 'AC11: sem sub na sessao, nenhuma linha';
end $$;
reset role;

-- Entregue: codigo some, delivered_at aparece. Fila esgotada: a pessoa ve passou.
update public.premios set status = 'entregue', entregue_em = '2020-06-01 15:25+00'
 where round_id = '68c00000-0000-0000-0000-000000000001' and user_id = '68a00000-0000-0000-0000-00000000000b';
set local role authenticated;
set local request.jwt.claims to '{"sub":"68a00000-0000-0000-0000-00000000000b","role":"authenticated"}';
do $$
declare r record;
begin
  select * into r from public.get_my_prize();
  assert r.status = 'entregue' and r.code is null and r.delivered_at = '2020-06-01 15:25+00', 'AC12: entregue sem codigo, com a hora';
end $$;
reset role;
update public.premios set status = 'sem_retirada', entregue_em = null
 where round_id = '68c00000-0000-0000-0000-000000000001' and user_id = '68a00000-0000-0000-0000-00000000000b';
set local role authenticated;
set local request.jwt.claims to '{"sub":"68a00000-0000-0000-0000-00000000000b","role":"authenticated"}';
do $$
begin
  assert (select status from public.get_my_prize()) = 'passou', 'AC12: para a pessoa, sem_retirada aparece como passou';
end $$;
reset role;
set local role anon;
do $$
begin
  assert (select display_name from public.get_official_winners() where round_id = '68c00000-0000-0000-0000-000000000001') is null,
    'AC12: sem_retirada -> letreiro some';
end $$;
reset role;

-- Premiacao desligada: nenhuma linha (o telao volta ao 1o ao vivo).
update public.premiacao_config set premiacao_ligada = false;
set local role anon;
do $$
begin
  assert (select count(*) from public.get_official_winners()) = 0, 'AC12: premiacao desligada -> nenhuma linha';
end $$;
reset role;

rollback;
select 'premiacao_contrato_test OK' as result;
