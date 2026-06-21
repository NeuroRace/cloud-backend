\set ON_ERROR_STOP on
do $$
declare
  r jsonb;
  base jsonb := jsonb_build_object(
    'schema_version','1.0',
    'idempotency_key','11111111-1111-1111-1111-111111111111',
    'race_id','22222222-2222-2222-2222-222222222222',
    'player_slot',1,'player_email','A@Test.com ','player_uuid',null,'source','real',
    'started_at',1735689600000::bigint,'finished_at',1735689660000::bigint,
    'telemetry_points', jsonb_build_array(
      jsonb_build_object('t',1735689601000::bigint,'attention',80,'meditation',55,
        'poor_signal_level',0,'signal_status','ok',
        'eeg_power',jsonb_build_object('delta',1,'theta',2))));
begin
  delete from telemetry_points; delete from race_players; delete from races; delete from players;

  r := ingest_race(base);
  assert r->>'status' = 'created', '1o ingest = created';
  assert (select count(*) from races) = 1, 'uma race';
  assert (select count(*) from race_players) = 1, 'um race_player';
  assert (select count(*) from telemetry_points) = 1, 'um ponto';
  assert (select email from players limit 1) = 'a@test.com', 'email normalizado lower+trim';

  r := ingest_race(base);  -- replay mesma idempotency_key
  assert r->>'status' = 'duplicate', 'replay = duplicate';
  assert (select count(*) from race_players) = 1, 'sem dup no replay';
  assert (select count(*) from telemetry_points) = 1, 'sem dup de telemetria';

  -- mesma (race_id, player_slot), idempotency_key diferente -> ainda duplicate
  r := ingest_race(jsonb_set(base,'{idempotency_key}','"33333333-3333-3333-3333-333333333333"'));
  assert r->>'status' = 'duplicate', '2a trava (race_id,slot) bloqueia';
  assert (select count(*) from race_players) = 1, 'sem dup pela 2a trava';

  -- player 2, mesmo email -> 2 race_players, 1 player
  r := ingest_race(jsonb_build_object(
    'schema_version','1.0','idempotency_key','44444444-4444-4444-4444-444444444444',
    'race_id','22222222-2222-2222-2222-222222222222','player_slot',2,
    'player_email','a@test.com','player_uuid',null,'source','real',
    'started_at',1735689600000::bigint,'finished_at',1735689670000::bigint,
    'telemetry_points','[]'::jsonb));
  assert r->>'status' = 'created', 'player 2 created';
  assert (select count(*) from race_players) = 2, 'dois race_players';
  assert (select count(*) from players) = 1, 'um player canonico (mesmo email)';
  assert (select count(*) from telemetry_points) = 1, 'telemetria vazia do p2 nao gera ponto';

  raise notice 'ingest_race_test OK';
end $$;
