-- Volta da NEU-159 (20261021120000_player_phone.sql), parte A. NAO fica em migrations/: so roda a mao.
--
-- ORDEM DA VOLTA (a ordem errada quebra o estande):
--   1. O operador passa a pedir so e-mail no painel.
--   2. PRIMEIRO republicar a ingest-race anterior (a de 29f0de3), com verify_jwt desligado:
--        git worktree add ../cb-volta 29f0de3
--        cd ../cb-volta && SUPABASE_ACCESS_TOKEN=$NEURORACE_SUPABASE_ACCESS_TOKEN \
--          supabase functions deploy ingest-race --no-verify-jwt --project-ref wtaulbdkgrnrtbfezaxw
--      (o token vem da env, como no CLAUDE.md: sem ele o deploy para no login.)
--      (ou pelo MCP do Supabase, deploy_edge_function com os 3 arquivos de
--      supabase/functions/ingest-race/ de 29f0de3 e verify_jwt: false).
--      A anterior recusa player_phone com 422 player_email_required: o edge guarda a
--      corrida em "Nao subiram", nada se perde. Se o passo 3 viesse antes, a funcao nova
--      mandaria player_phone para a ingest_race antiga, que grava jogador sem e-mail e para
--      no check players_email_or_phone: 500 em cada corrida de celular (testado em 21/10).
--   3. So depois rodar ESTE arquivo (sempre seguro, mesmo com jogador de celular):
--        psql "$DB" -v ON_ERROR_STOP=1 -1 -f supabase/rollbacks/20261021120000_player_phone.down.sql
--      ingest_race volta a versao anterior (fix_ingest_race) e o gatilho do celular sai.
--   4. Desfazer o schema (20261021120000_player_phone.down-schema.sql) so com 0 jogadores de
--      celular e 0 contas com 2 jogadores. Nao precisa antes de sabado: a coluna phone e o
--      email opcional nao atrapalham ninguem.

-- ===== Parte A =====
drop trigger if exists on_auth_phone_confirmed on auth.users;
drop function if exists public.handle_phone_confirmed();

create or replace function public.ingest_race(payload jsonb)
returns jsonb
language plpgsql
as $$
declare
  v_email          text := lower(trim(payload->>'player_email'));
  v_player_id      uuid;
  v_race_player_id uuid;
begin
  if exists (select 1 from race_players
              where idempotency_key = (payload->>'idempotency_key')::uuid) then
    return jsonb_build_object('status','duplicate');
  end if;

  insert into players (email) values (v_email)
  on conflict (email) do update set email = excluded.email
  returning id into v_player_id;

  insert into races (id, started_at)
  values ((payload->>'race_id')::uuid,
          to_timestamp((payload->>'started_at')::bigint / 1000.0))
  on conflict (id) do nothing;

  begin
    insert into race_players
      (idempotency_key, race_id, player_id, player_slot, source, started_at, finished_at)
    values
      ((payload->>'idempotency_key')::uuid,
       (payload->>'race_id')::uuid,
       v_player_id,
       (payload->>'player_slot')::int,
       coalesce(payload->>'source','real'),
       to_timestamp((payload->>'started_at')::bigint / 1000.0),
       to_timestamp((payload->>'finished_at')::bigint / 1000.0))
    on conflict (idempotency_key) do nothing
    returning id into v_race_player_id;
  exception
    when unique_violation then
      if exists (select 1 from race_players
                 where race_id = (payload->>'race_id')::uuid
                   and player_slot = (payload->>'player_slot')::int
                   and player_id = v_player_id) then
        return jsonb_build_object('status','duplicate');
      end if;
      raise exception 'race_players slot conflict: race % slot % ocupado por outro jogador',
        payload->>'race_id', payload->>'player_slot'
        using errcode = 'unique_violation';
  end;

  if v_race_player_id is null then
    return jsonb_build_object('status','duplicate');
  end if;

  insert into telemetry_points
    (race_player_id, t, attention, meditation, poor_signal_level, signal_status, eeg_power)
  select v_race_player_id,
         to_timestamp((p->>'t')::bigint / 1000.0),
         (p->>'attention')::int,
         (p->>'meditation')::int,
         (p->>'poor_signal_level')::int,
         p->>'signal_status',
         p->'eeg_power'
  from jsonb_array_elements(coalesce(payload->'telemetry_points','[]'::jsonb)) as p;

  return jsonb_build_object('status','created');
end;
$$;
