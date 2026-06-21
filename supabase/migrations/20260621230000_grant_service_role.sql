-- service_role bypasses RLS but still needs explicit DML grants on tables.
-- ingest_race() nao tem clausula SECURITY, entao o default e SECURITY INVOKER: executa como o role chamador (service_role), nao como o owner. service_role bypassa RLS mas ainda precisa de GRANT DML.
grant select, insert on public.players          to service_role;
grant select, insert on public.races            to service_role;
grant select, insert on public.race_players     to service_role;
grant select, insert on public.telemetry_points to service_role;
grant execute on function public.ingest_race(jsonb) to service_role;
