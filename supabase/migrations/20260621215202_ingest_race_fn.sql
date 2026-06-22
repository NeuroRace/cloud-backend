create or replace function public.ingest_race(payload jsonb)
returns jsonb
language plpgsql
as $$
declare
  v_email          text := lower(trim(payload->>'player_email'));
  v_player_id      uuid;
  v_race_player_id uuid;
begin
  -- short-circuit por idempotency_key (replay)
  if exists (select 1 from race_players
              where idempotency_key = (payload->>'idempotency_key')::uuid) then
    return jsonb_build_object('status','duplicate');
  end if;

  -- resolve/cria player (nunca toca user_id)
  insert into players (email) values (v_email)
  on conflict (email) do nothing;
  select id into v_player_id from players where email = v_email;

  -- upsert race (inicio compartilhado)
  insert into races (id, started_at)
  values ((payload->>'race_id')::uuid,
          to_timestamp((payload->>'started_at')::bigint / 1000.0))
  on conflict (id) do nothing;

  -- resultado por jogador; dupla trava via on conflict do nothing
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
  on conflict do nothing
  returning id into v_race_player_id;

  if v_race_player_id is null then
    return jsonb_build_object('status','duplicate');  -- perdeu a corrida em (race_id,slot)
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
