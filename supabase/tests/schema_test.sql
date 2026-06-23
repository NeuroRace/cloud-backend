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
  assert (select relrowsecurity from pg_class where oid='public.players'::regclass), 'RLS deve estar ON em players';
  assert (select relrowsecurity from pg_class where oid='public.races'::regclass), 'RLS deve estar ON em races';
  assert (select relrowsecurity from pg_class where oid='public.race_players'::regclass), 'RLS deve estar ON em race_players';
  assert (select relrowsecurity from pg_class where oid='public.telemetry_points'::regclass), 'RLS deve estar ON em telemetry_points';
  -- Nas 4 tabelas de DADOS: so leitura own-data; ZERO escrita publica (escrita via service_role).
  assert (select count(*) from pg_policies where schemaname='public'
          and tablename in ('players','races','race_players','telemetry_points') and cmd='SELECT') = 4,
    'esperado 4 policies de leitura nas tabelas de dados';
  assert (select count(*) from pg_policies where schemaname='public'
          and tablename in ('players','races','race_players','telemetry_points') and cmd <> 'SELECT') = 0,
    'nenhuma policy de escrita publica nas tabelas de dados (escrita so via service_role)';
  assert (select count(*) from pg_policies where schemaname='public'
          and tablename in ('players','races','race_players','telemetry_points')
          and policyname in ('players_select_own','race_players_select_own','telemetry_points_select_own','races_select_participated')) = 4,
    'as 4 policies own-data nominais devem existir';
  -- profiles: o usuario gerencia o proprio alias (select-own + update-own).
  assert (select count(*) from pg_policies where schemaname='public' and tablename='profiles'
          and policyname in ('profiles_select_own','profiles_update_own')) = 2,
    'profiles deve ter select-own e update-own';
  raise notice 'schema_test OK';
end $$;
