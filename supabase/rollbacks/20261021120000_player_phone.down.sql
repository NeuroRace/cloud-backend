-- Volta da NEU-159 (20261021120000_player_phone.sql). NAO fica em migrations/: so roda a mao.
-- Rodar inteiro numa transacao: psql -v ON_ERROR_STOP=1 -1 -f <este arquivo>
--
-- Parte A (sempre segura): o estande volta a ser so e-mail. ingest_race volta a versao
-- anterior (fix_ingest_race) e o gatilho do celular sai. Envio com player_phone passa a
-- falhar (o contract.ts anterior recusa com 422 player_email_required; o edge guarda a
-- corrida em "Nao subiram"). Lembre de publicar tambem a versao anterior da ingest-race.
--
-- Parte B (so se NENHUM jogador tiver celular): desfaz o schema. Com jogador de celular,
-- ela para com erro de proposito e nada e desfeito (transacao). Nesse caso a volta segura e
-- so a Parte A: comente a Parte B e rode de novo. A coluna fica, nao atrapalha ninguem.

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

-- ===== Parte B =====
do $$ begin
  if exists (select 1 from public.players where phone is not null) then
    raise exception 'ha jogador com celular: rode so a Parte A (veja o topo do arquivo)';
  end if;
end $$;
drop index if exists public.players_user_id_idx;
alter table public.players add constraint players_user_id_key unique (user_id);
alter table public.players drop constraint players_email_or_phone;
alter table public.players alter column email set not null;
alter table public.players drop column phone;
