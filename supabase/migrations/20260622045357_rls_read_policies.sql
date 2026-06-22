-- Policies de LEITURA (own-data) para o frontend consumir via supabase-js + RLS.
--
-- Contexto: RLS ja esta habilitado nas 4 tabelas, sem nenhuma policy (default deny).
-- Estas policies adicionam SOMENTE leitura (`for select`), escopada ao usuario logado
-- (`authenticated`) via a cadeia players.user_id = auth.uid(). A escrita continua
-- exclusivamente via service_role (que ignora RLS) — o ingest NAO e afetado.
--
-- GRANT: o role precisa de privilegio de tabela (SELECT) para a RLS sequer ser avaliada.
-- Concedemos a `authenticated` (que tem policies) e a `anon` (sem policy -> retorna vazio
-- em vez de "permission denied", padrao Supabase). No projeto hospedado o default-privileges
-- ja concede amplamente -> aqui e idempotente/no-op; no local e necessario.
--
-- Ranking (cross-usuario) NAO entra aqui de proposito (exige decisao de produto + mecanismo
-- proprio, ex.: view security definer). Best practice: `(select auth.uid())` evita reavaliar
-- a funcao por linha; indices exigidos ja existem no schema inicial.

grant select on players, races, race_players, telemetry_points to authenticated, anon;

create policy players_select_own
  on players for select to authenticated
  using (user_id = (select auth.uid()));

create policy race_players_select_own
  on race_players for select to authenticated
  using (
    player_id in (select id from players where user_id = (select auth.uid()))
  );

create policy telemetry_points_select_own
  on telemetry_points for select to authenticated
  using (
    race_player_id in (
      select rp.id
      from race_players rp
      join players p on p.id = rp.player_id
      where p.user_id = (select auth.uid())
    )
  );

create policy races_select_participated
  on races for select to authenticated
  using (
    id in (
      select rp.race_id
      from race_players rp
      join players p on p.id = rp.player_id
      where p.user_id = (select auth.uid())
    )
  );
