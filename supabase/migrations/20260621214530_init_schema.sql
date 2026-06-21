create table players (
  id         uuid primary key default gen_random_uuid(),
  email      text not null unique,                 -- normalizado lower(trim)
  user_id    uuid unique references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table races (
  id          uuid primary key,                    -- race_id do edge
  started_at  timestamptz not null,                -- inicio compartilhado
  created_at  timestamptz not null default now()
);

create table race_players (
  id              uuid primary key default gen_random_uuid(),
  idempotency_key uuid not null unique,
  race_id         uuid not null references races(id),
  player_id       uuid not null references players(id),
  player_slot     int  not null check (player_slot in (1,2)),
  source          text not null default 'real',
  started_at      timestamptz not null,
  finished_at     timestamptz,
  created_at      timestamptz not null default now(),
  unique (race_id, player_slot)
);

create table telemetry_points (
  id                bigint generated always as identity primary key,
  race_player_id    uuid not null references race_players(id) on delete cascade,
  t                 timestamptz not null,
  attention         int,
  meditation        int,
  poor_signal_level int,
  signal_status     text,
  eeg_power         jsonb
);

create index on telemetry_points (race_player_id);
create index on race_players (player_id);
create index on race_players (race_id);

-- RLS habilitado, sem policy de escrita publica. service_role bypassa RLS. service_role bypassa RLS mas ainda precisa de GRANT explicito (ver 20260621230000_grant_service_role.sql).
alter table players          enable row level security;
alter table races            enable row level security;
alter table race_players     enable row level security;
alter table telemetry_points enable row level security;
