-- service_role bypasses RLS but still needs explicit DML grants on tables.
-- ingest_race() runs with CALLER RIGHTS so it executes as the calling role (service_role).
grant select, insert on public.players          to service_role;
grant select, insert on public.races            to service_role;
grant select, insert on public.race_players     to service_role;
grant select, insert on public.telemetry_points to service_role;
grant execute on function public.ingest_race(jsonb) to service_role;
