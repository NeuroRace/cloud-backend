-- NEU-110: ranking por rodada (parte da NEU-89).
-- (1) ranking_windows: rodadas do evento. Leitura publica (o site le para montar as
--     abas Evento / Rodada atual e o telao); escrita so por SQL/service_role ate o
--     painel de operacao (NEU-114). Sem sobreposicao, garantido no banco: hoje as
--     rodadas sao editadas a mao.
-- (2) get_leaderboard ganha filtro de periodo e desempate por quem fez primeiro.
-- Contrato consumido pelo web PR #11 (NEU-111). Spec:
-- docs/superpowers/specs/2026-09-28-ranking-por-rodada-design.md

create table public.ranking_windows (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (char_length(btrim(name)) between 1 and 60),
  starts_at  timestamptz not null,
  ends_at    timestamptz not null,
  created_at timestamptz not null default now(),
  constraint ranking_windows_valid_range check (ends_at > starts_at),
  -- '[)' permite rodadas encostadas (fim de uma = inicio da outra). GiST de range e
  -- nativo; nao precisa de btree_gist.
  constraint ranking_windows_no_overlap
    exclude using gist (tstzrange(starts_at, ends_at, '[)') with &&)
);

alter table public.ranking_windows enable row level security;

create policy ranking_windows_select_public on public.ranking_windows
  for select to anon, authenticated using (true);

-- O default-privileges do Supabase concede ALL (inclusive TRUNCATE, que ignora RLS)
-- a anon/authenticated em tabelas novas do public. Aqui eles so leem.
revoke all on public.ranking_windows from anon, authenticated;
grant select on public.ranking_windows to anon, authenticated;
grant select, insert, update, delete on public.ranking_windows to service_role;
