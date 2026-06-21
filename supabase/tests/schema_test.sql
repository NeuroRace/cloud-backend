\set ON_ERROR_STOP on
do $$
begin
  assert (select count(*) from information_schema.tables
          where table_schema='public'
            and table_name in ('players','races','race_players','telemetry_points')) = 4,
    'esperado 4 tabelas em public';
  assert (select count(*) from information_schema.table_constraints
          where constraint_schema='public' and table_name='race_players'
            and constraint_type='UNIQUE') >= 2,
    'race_players precisa de 2 uniques (idempotency_key e race_id+player_slot)';
  assert (select relrowsecurity from pg_class where oid='public.players'::regclass), 'RLS off em players';
  assert (select relrowsecurity from pg_class where oid='public.races'::regclass), 'RLS off em races';
  assert (select relrowsecurity from pg_class where oid='public.race_players'::regclass), 'RLS off em race_players';
  assert (select relrowsecurity from pg_class where oid='public.telemetry_points'::regclass), 'RLS off em telemetry_points';
  assert (select count(*) from pg_policies where schemaname='public') = 0, 'nenhuma policy publica esperada';
  raise notice 'schema_test OK';
end $$;
