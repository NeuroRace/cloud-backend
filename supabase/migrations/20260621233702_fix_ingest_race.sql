-- ingest_race usa ON CONFLICT DO UPDATE em players (para fechar janela de concorrencia),
-- o que exige UPDATE alem de INSERT. Adiciona o grant que faltava.
grant update on public.players to service_role;

create or replace function public.ingest_race(payload jsonb)
returns jsonb
language plpgsql
as $$
declare
  v_email          text := lower(trim(payload->>'player_email'));
  v_player_id      uuid;
  v_race_player_id uuid;
begin
  -- replay exato ja processado
  if exists (select 1 from race_players
              where idempotency_key = (payload->>'idempotency_key')::uuid) then
    return jsonb_build_object('status','duplicate');
  end if;

  -- resolve/cria player; do update ... returning fecha a janela de concorrencia
  -- (sempre devolve a linha conflitante). NUNCA toca user_id.
  insert into players (email) values (v_email)
  on conflict (email) do update set email = excluded.email
  returning id into v_player_id;

  -- upsert race (inicio compartilhado)
  insert into races (id, started_at)
  values ((payload->>'race_id')::uuid,
          to_timestamp((payload->>'started_at')::bigint / 1000.0))
  on conflict (id) do nothing;

  -- resultado por jogador. on conflict (idempotency_key) trata replay concorrente.
  -- conflito em (race_id, player_slot) NAO e alvo aqui -> levanta unique_violation,
  -- tratado abaixo para distinguir re-consolidacao (mesmo jogador) de colisao real.
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
      -- so a trava (race_id, player_slot) chega aqui. Mesmo jogador no slot =
      -- re-consolidacao com jobId novo (intencao do spec) -> duplicate.
      -- Jogador DIFERENTE no mesmo slot = anomalia -> propaga (nao engole).
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
    -- on conflict (idempotency_key) do nothing suprimiu -> replay concorrente
    return jsonb_build_object('status','duplicate');
  end if;

  -- telemetria (so no caminho de criacao real)
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
