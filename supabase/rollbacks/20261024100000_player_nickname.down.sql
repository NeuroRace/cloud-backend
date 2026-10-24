-- Volta da 20261024100000_player_nickname.sql. NAO fica em migrations/: so roda a mao.
-- Devolve a ingest_race exatamente como na 20261021120000_player_phone.sql
-- (md5(prosrc) = 890af2213317b8b245fa86344ca2a285, conferido em prod em 24/10).
--
-- ORDEM DA VOLTA:
--   1. O operador para de usar apelido no painel (e-mail e celular seguem).
--   2. Republicar a ingest-race anterior (a de 55b8651), com verify_jwt desligado:
--        git worktree add ../cb-volta 55b8651
--        cd ../cb-volta && SUPABASE_ACCESS_TOKEN=$NEURORACE_SUPABASE_ACCESS_TOKEN \
--          npx supabase@2.122.0 functions deploy ingest-race --no-verify-jwt --project-ref wtaulbdkgrnrtbfezaxw
--      A anterior recusa player_nickname com 422 player_email_required: o edge guarda a
--      corrida em "Nao subiram", nada se perde.
--   3. Rodar ESTE arquivo:
--        psql "$DB" -v ON_ERROR_STOP=1 -1 -f supabase/rollbacks/20261024100000_player_nickname.down.sql
--      e apagar a linha 20261024100000 de supabase_migrations.schema_migrations.
--   As corridas que ja entraram por apelido ficam (sao corridas normais no jogador da conta).

create or replace function public.ingest_race(payload jsonb)
returns jsonb
language plpgsql
as $$
declare
  v_email          text := nullif(lower(trim(payload->>'player_email')), '');
  v_phone          text := nullif(trim(payload->>'player_phone'), '');
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
  if v_email is not null then
    insert into players (email) values (v_email)
    on conflict (email) do update set email = excluded.email
    returning id into v_player_id;
  else
    -- formato invalido levanta check_violation (players_phone_format): nada e gravado.
    insert into players (phone) values (v_phone)
    on conflict (phone) do update set phone = excluded.phone
    returning id into v_player_id;
  end if;

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
