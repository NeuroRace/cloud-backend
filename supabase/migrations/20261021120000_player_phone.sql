-- NEU-159: corrida de quem deu so o celular no estande, ligada a conta quando a pessoa
-- confirma o celular no site. Tudo aditivo: quem manda so e-mail segue igual.
-- Volta: supabase/rollbacks/20261021120000_player_phone.down.sql

-- (1) players: celular opcional e unico, no formato do edge (+55 + DDD + 9 digitos).
-- E-mail passa a ser opcional, mas cada jogador tem pelo menos um dos dois.
alter table public.players add column phone text unique
  constraint players_phone_format check (phone ~ '^\+55[1-9][0-9]9[0-9]{8}$');
alter table public.players alter column email drop not null;
alter table public.players add constraint players_email_or_phone
  check (email is not null or phone is not null);

-- (2) Sai a trava "uma conta, um jogador": a mesma conta pode ter o jogador do e-mail e o
-- do celular. Ranking (get_leaderboard, distinct on profile) e RLS (user_id = auth.uid())
-- ja agrupam por conta. O indice fica (RLS filtra por user_id), so que nao unico.
alter table public.players drop constraint players_user_id_key;
create index players_user_id_idx on public.players (user_id);

-- (3) ingest_race: aceita player_phone no lugar de player_email. O contrato (contract.ts)
-- garante que vem um dos dois; aqui o celular so entra se o e-mail nao veio.
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

-- (4) Liga a corrida a conta quando o celular e confirmado, igual ao do e-mail
-- (claim_trigger). O Supabase confirma com um UPDATE em phone_confirmed_at (ConfirmPhone)
-- e guarda o telefone SEM o "+" ("5511987654321"): normaliza para o formato do edge.
-- Tambem dispara quando um celular ja confirmado e trocado por outro (troca de numero).
-- Telefone fora do formato do edge (fixo, outro pais) nao vira jogador: nao ha corrida dele.
create or replace function public.handle_phone_confirmed()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text := '+' || regexp_replace(coalesce(new.phone, ''), '\D', '', 'g');
begin
  if new.phone_confirmed_at is not null
     and (old.phone_confirmed_at is null or new.phone is distinct from old.phone)
     and v_phone ~ '^\+55[1-9][0-9]9[0-9]{8}$' then
    insert into public.players (phone, user_id)
    values (v_phone, new.id)
    on conflict (phone) do update
      set user_id = excluded.user_id
      where players.user_id is null;
  end if;
  return new;
end;
$$;

create trigger on_auth_phone_confirmed
  after update of phone_confirmed_at, phone on auth.users
  for each row
  execute function public.handle_phone_confirmed();
