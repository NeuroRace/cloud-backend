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

-- O SQL editor do Supabase roda em UTC: horario sem offset fica 3 h adiantado em SP.
comment on column public.ranking_windows.starts_at is
  'Inicio da rodada. Escreva SEMPRE com offset de Sao Paulo, ex.: 2026-09-30 14:00-03';
comment on column public.ranking_windows.ends_at is
  'Fim da rodada (exclusivo). Escreva SEMPRE com offset de Sao Paulo, ex.: 2026-09-30 16:00-03';

alter table public.ranking_windows enable row level security;

create policy ranking_windows_select_public on public.ranking_windows
  for select to anon, authenticated using (true);

-- O default-privileges do Supabase concede ALL (inclusive TRUNCATE, que ignora RLS)
-- a anon/authenticated em tabelas novas do public. Aqui eles so leem.
revoke all on public.ranking_windows from anon, authenticated;
grant select on public.ranking_windows to anon, authenticated;
grant select, insert, update, delete on public.ranking_windows to service_role;

-- (2) get_leaderboard: periodo por finished_at, meio-aberto [p_from, p_to); null = sem
-- limite daquele lado. Desempate: para cada pessoa vale a menor duracao e, empatando,
-- a que terminou primeiro; o rank ordena por (score, achieved_at). Mantem: sem PII,
-- so quem tem apelido, so source='real', so corrida terminada com duracao > 0.
-- A versao (text, int) sai: duas sobrecargas deixariam o PostgREST sem saber qual
-- chamar para {p_metric, p_limit}.
drop function if exists public.get_leaderboard(text, int);

create function public.get_leaderboard(
  p_metric text        default 'best_time',
  p_limit  int         default 50,
  p_from   timestamptz default null,
  p_to     timestamptz default null
)
returns table (rank int, display_name text, score numeric)
language sql
stable
security definer
set search_path = public
as $$
  select (rank() over (order by b.score asc, b.achieved_at asc))::int as rank,
         b.display_name,
         b.score
  from (
    select distinct on (pr.id)
           pr.display_name::text as display_name,
           extract(epoch from (rp.finished_at - rp.started_at))::numeric as score,
           rp.finished_at as achieved_at
    from profiles pr
    join players p       on p.user_id = pr.id
    join race_players rp on rp.player_id = p.id
    where p_metric = 'best_time'          -- unica metrica por enquanto (NEU-67 estende)
      and pr.display_name is not null     -- so quem tem apelido
      and rp.source = 'real'              -- defesa-em-profundidade: ignora bot
      and rp.finished_at is not null      -- ignora corrida nao terminada
      and rp.finished_at > rp.started_at
      and (p_from is null or rp.finished_at >= p_from)
      and (p_to   is null or rp.finished_at <  p_to)
    order by pr.id, (rp.finished_at - rp.started_at) asc, rp.finished_at asc
  ) b
  order by b.score asc, b.achieved_at asc, b.display_name asc
  limit least(greatest(p_limit, 1), 1000);
$$;

revoke all on function public.get_leaderboard(text, int, timestamptz, timestamptz) from public;
grant execute on function public.get_leaderboard(text, int, timestamptz, timestamptz) to anon, authenticated;
