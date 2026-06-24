\set ON_ERROR_STOP on

-- SEED (superuser). Alice melhor=60s; Bob melhor=30s (tem outra de 90s); Carol SEM nome (deve sumir);
-- Dave melhor=30s (EMPATE com Bob); Alice tem tambem uma corrida com finished_at NULL (deve ser ignorada).
begin;
delete from telemetry_points; delete from race_players; delete from races; delete from players;
delete from public.profiles where id in ('a0000000-0000-0000-0000-0000000000a1','b0000000-0000-0000-0000-0000000000b2','c0000000-0000-0000-0000-0000000000c3','d0000000-0000-0000-0000-0000000000d4');
delete from auth.users where email in ('lb_a@test.com','lb_b@test.com','lb_c@test.com','lb_d@test.com');

insert into auth.users (instance_id, id, aud, role, email, created_at, updated_at) values
 ('00000000-0000-0000-0000-000000000000','a0000000-0000-0000-0000-0000000000a1','authenticated','authenticated','lb_a@test.com',now(),now()),
 ('00000000-0000-0000-0000-000000000000','b0000000-0000-0000-0000-0000000000b2','authenticated','authenticated','lb_b@test.com',now(),now()),
 ('00000000-0000-0000-0000-000000000000','c0000000-0000-0000-0000-0000000000c3','authenticated','authenticated','lb_c@test.com',now(),now()),
 ('00000000-0000-0000-0000-000000000000','d0000000-0000-0000-0000-0000000000d4','authenticated','authenticated','lb_d@test.com',now(),now());
update public.profiles set display_name='Alice' where id='a0000000-0000-0000-0000-0000000000a1';
update public.profiles set display_name='Bob'   where id='b0000000-0000-0000-0000-0000000000b2';
update public.profiles set display_name='Dave'  where id='d0000000-0000-0000-0000-0000000000d4';
-- Carol fica sem display_name (NULL) de proposito.

insert into players (id, email, user_id) values
 ('11111111-aaaa-1111-1111-111111111111','lb_a@test.com','a0000000-0000-0000-0000-0000000000a1'),
 ('22222222-bbbb-2222-2222-222222222222','lb_b@test.com','b0000000-0000-0000-0000-0000000000b2'),
 ('33333333-cccc-3333-3333-333333333333','lb_c@test.com','c0000000-0000-0000-0000-0000000000c3'),
 ('44444444-dddd-4444-4444-444444444444','lb_d@test.com','d0000000-0000-0000-0000-0000000000d4');

insert into races (id, started_at) values
 ('aa000000-0000-0000-0000-0000000000a1','2026-01-01 00:00:00+00'),
 ('aa000000-0000-0000-0000-0000000000a2','2026-01-01 00:00:00+00'),
 ('bb000000-0000-0000-0000-0000000000b1','2026-01-01 00:00:00+00'),
 ('bb000000-0000-0000-0000-0000000000b2','2026-01-01 00:00:00+00'),
 ('cc000000-0000-0000-0000-0000000000c1','2026-01-01 00:00:00+00'),
 ('dd000000-0000-0000-0000-0000000000d1','2026-01-01 00:00:00+00');

-- race_players: (started_at, finished_at) -> duracao
insert into race_players (id, idempotency_key, race_id, player_id, player_slot, started_at, finished_at) values
 -- Alice: 60s e uma NULL (ignorada)
 ('d1000000-0000-0000-0000-0000000000a1', gen_random_uuid(), 'aa000000-0000-0000-0000-0000000000a1','11111111-aaaa-1111-1111-111111111111',1,'2026-01-01 00:00:00+00','2026-01-01 00:01:00+00'),
 ('d1000000-0000-0000-0000-0000000000a2', gen_random_uuid(), 'aa000000-0000-0000-0000-0000000000a2','11111111-aaaa-1111-1111-111111111111',1,'2026-01-01 00:00:00+00',null),
 -- Bob: 30s (melhor) e 90s
 ('d2000000-0000-0000-0000-0000000000b1', gen_random_uuid(), 'bb000000-0000-0000-0000-0000000000b1','22222222-bbbb-2222-2222-222222222222',1,'2026-01-01 00:00:00+00','2026-01-01 00:00:30+00'),
 ('d2000000-0000-0000-0000-0000000000b2', gen_random_uuid(), 'bb000000-0000-0000-0000-0000000000b2','22222222-bbbb-2222-2222-222222222222',1,'2026-01-01 00:00:00+00','2026-01-01 00:01:30+00'),
 -- Carol: 10s (melhor de todos) MAS sem display_name -> deve sumir
 ('d3000000-0000-0000-0000-0000000000c1', gen_random_uuid(), 'cc000000-0000-0000-0000-0000000000c1','33333333-cccc-3333-3333-333333333333',1,'2026-01-01 00:00:00+00','2026-01-01 00:00:10+00'),
 -- Dave: 30s (EMPATE com Bob)
 ('d4000000-0000-0000-0000-0000000000d1', gen_random_uuid(), 'dd000000-0000-0000-0000-0000000000d1','44444444-dddd-4444-4444-444444444444',1,'2026-01-01 00:00:00+00','2026-01-01 00:00:30+00');
commit;

-- chamada como ANON (leaderboard publico)
begin;
set local role anon;
do $$
declare r record; n int;
begin
  -- ordenacao + filtragem: Bob, Dave (rank=1 empatados), Alice (rank=3 por rank() com gap)
  select count(*) into n from get_leaderboard('best_time', 50);
  assert n = 3, 'leaderboard deve ter 3 (Bob, Dave, Alice) — Carol sem nome sai. veio '||n;

  -- Bob e Dave empatam no rank 1; Dave aparece antes de Bob (order by display_name)
  select * into r from get_leaderboard('best_time', 50) where rank = 1 and display_name = 'Bob';
  assert r.display_name = 'Bob' and r.score = 30, 'Bob deve estar no rank 1 com 30s. veio '||coalesce(r.display_name,'NULL')||'/'||coalesce(r.score::text,'NULL');

  select * into r from get_leaderboard('best_time', 50) where rank = 1 and display_name = 'Dave';
  assert r.display_name = 'Dave' and r.score = 30, 'Dave deve estar no rank 1 com 30s (empate). veio '||coalesce(r.display_name,'NULL')||'/'||coalesce(r.score::text,'NULL');

  -- Alice e rank 3 (rank() deixa gap apos empate de 2)
  select * into r from get_leaderboard('best_time', 50) where rank = 3;
  assert r.display_name = 'Alice' and r.score = 60, 'rank 3 = Alice (60s, ignora a corrida NULL). veio '||coalesce(r.display_name,'NULL')||'/'||coalesce(r.score::text,'NULL');

  -- (F) empate deterministico: Bob e Dave (30s) devem compartilhar o mesmo rank
  assert (select count(distinct rank) from get_leaderboard('best_time',50) where score=30) = 1,
    'empatados com 30s devem ter o mesmo rank';
  assert (select count(*) from get_leaderboard('best_time',50) where score=30 and rank=1) = 2,
    'dois jogadores com 30s devem ter rank=1';

  -- Carol (10s, melhor) NAO aparece por nao ter nome
  assert (select count(*) from get_leaderboard('best_time',50) where display_name is null) = 0, 'sem nome nao aparece';

  -- metrica desconhecida -> vazio (sem erro)
  assert (select count(*) from get_leaderboard('xxx', 50)) = 0, 'metrica desconhecida retorna vazio';
end $$;
commit;

-- nao vaza PII: as colunas de retorno sao exatamente rank, display_name, score
do $$
declare cols text;
begin
  select string_agg(a.attname, ',' order by a.attnum) into cols
  from pg_proc p
  join lateral unnest(p.proargnames, p.proargmodes) with ordinality as a(attname, mode, attnum) on true
  where p.proname='get_leaderboard' and a.mode in ('t','o');  -- table/out columns
  assert cols = 'rank,display_name,score', 'retorno deve ser exatamente rank,display_name,score (sem email/ids). veio: '||coalesce(cols,'NULL');
end $$;

-- nao vaza PII (2, robusto): pedir email/user_id da funcao deve ERRAR (prova direta de ausencia de PII)
do $$
declare leaked boolean;
begin
  leaked := true;
  begin perform email   from get_leaderboard('best_time',1); exception when undefined_column then leaked := false; end;
  assert not leaked, 'funcao NAO pode expor coluna email';
  leaked := true;
  begin perform user_id from get_leaderboard('best_time',1); exception when undefined_column then leaked := false; end;
  assert not leaked, 'funcao NAO pode expor user_id';
end $$;

-- limpeza
delete from telemetry_points; delete from race_players; delete from races; delete from players;
delete from public.profiles where id in ('a0000000-0000-0000-0000-0000000000a1','b0000000-0000-0000-0000-0000000000b2','c0000000-0000-0000-0000-0000000000c3','d0000000-0000-0000-0000-0000000000d4');
delete from auth.users where email in ('lb_a@test.com','lb_b@test.com','lb_c@test.com','lb_d@test.com');
select 'leaderboard_test OK' as result;
