-- Teste de isolamento das policies de leitura (own-data).
-- Prova: A ve so o seu; B ve so o seu; anon nao ve nada; escrita (service_role) nao regride.
\set ON_ERROR_STOP on

-- ===== SEED (roda como superuser; bypassa RLS) =====
begin;
delete from telemetry_points; delete from race_players; delete from races; delete from players;
delete from auth.users where email in ('rls_a@test.com','rls_b@test.com');

insert into auth.users (instance_id, id, aud, role, email, created_at, updated_at) values
  ('00000000-0000-0000-0000-000000000000','aaaaaaaa-1111-1111-1111-111111111111','authenticated','authenticated','rls_a@test.com',now(),now()),
  ('00000000-0000-0000-0000-000000000000','bbbbbbbb-2222-2222-2222-222222222222','authenticated','authenticated','rls_b@test.com',now(),now());

insert into players (id, email, user_id) values
  ('11111111-aaaa-1111-1111-111111111111','rls_a@test.com','aaaaaaaa-1111-1111-1111-111111111111'),
  ('22222222-bbbb-2222-2222-222222222222','rls_b@test.com','bbbbbbbb-2222-2222-2222-222222222222');

insert into races (id, started_at) values
  ('33333333-aaaa-3333-3333-333333333333',now()),
  ('44444444-bbbb-4444-4444-444444444444',now());

insert into race_players (id, idempotency_key, race_id, player_id, player_slot, started_at) values
  ('55555555-aaaa-5555-5555-555555555555', gen_random_uuid(), '33333333-aaaa-3333-3333-333333333333', '11111111-aaaa-1111-1111-111111111111', 1, now()),
  ('66666666-bbbb-6666-6666-666666666666', gen_random_uuid(), '44444444-bbbb-4444-4444-444444444444', '22222222-bbbb-2222-2222-222222222222', 1, now());

insert into telemetry_points (race_player_id, t) values
  ('55555555-aaaa-5555-5555-555555555555', now()),
  ('55555555-aaaa-5555-5555-555555555555', now()),   -- A: 2 pontos
  ('66666666-bbbb-6666-6666-666666666666', now());   -- B: 1 ponto
commit;

-- ===== como USUARIO A =====
begin;
set local role authenticated;
set local request.jwt.claims to '{"sub":"aaaaaaaa-1111-1111-1111-111111111111","role":"authenticated"}';
do $$ begin
  assert (select count(*) from players) = 1, 'A: deve ver 1 player (o seu)';
  assert (select count(*) from races) = 1, 'A: deve ver 1 corrida (a sua)';
  assert (select count(*) from race_players) = 1, 'A: deve ver 1 race_player';
  assert (select count(*) from telemetry_points) = 2, 'A: deve ver 2 pontos (so os seus)';
  assert (select count(*) from players where email = 'rls_b@test.com') = 0, 'A: NAO pode ver player do B';
end $$;
commit;

-- ===== como USUARIO B =====
begin;
set local role authenticated;
set local request.jwt.claims to '{"sub":"bbbbbbbb-2222-2222-2222-222222222222","role":"authenticated"}';
do $$ begin
  assert (select count(*) from telemetry_points) = 1, 'B: deve ver 1 ponto (so o seu)';
  assert (select count(*) from races) = 1, 'B: deve ver 1 corrida (a sua)';
  assert (select count(*) from players where email = 'rls_a@test.com') = 0, 'B: NAO pode ver player do A';
end $$;
commit;

-- ===== como ANON =====
begin;
set local role anon;
do $$ begin
  assert (select count(*) from players) = 0, 'anon: nao ve players';
  assert (select count(*) from telemetry_points) = 0, 'anon: nao ve telemetria';
  assert (select count(*) from races) = 0, 'anon: nao ve corridas';
end $$;
commit;

-- ===== nao-regressao: service_role (que o ingest usa) continua vendo tudo =====
begin;
set local role service_role;
do $$ begin
  assert (select count(*) from telemetry_points) = 3, 'service_role: bypassa RLS = 3 pontos';
end $$;
commit;

-- limpeza do seed
delete from telemetry_points; delete from race_players; delete from races; delete from players;
delete from auth.users where email in ('rls_a@test.com','rls_b@test.com');

select 'rls_read_test OK' as result;
