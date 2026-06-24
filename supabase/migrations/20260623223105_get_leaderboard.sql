-- Leaderboard publico, calculado na leitura. security definer: roda como owner e
-- agrega entre usuarios (a RLS own-data nao se aplica aqui), devolvendo SO nome+score.
create or replace function public.get_leaderboard(
  p_metric text default 'best_time',
  p_limit  int  default 50
)
returns table (rank int, display_name text, score numeric)
language sql
security definer
set search_path = public
as $$
  select (row_number() over (order by s.score asc))::int as rank,
         s.display_name,
         s.score
  from (
    select pr.display_name::text as display_name,
           extract(epoch from min(rp.finished_at - rp.started_at))::numeric as score
    from profiles pr
    join players p       on p.user_id = pr.id
    join race_players rp on rp.player_id = p.id
    where p_metric = 'best_time'        -- unica metrica por enquanto; outras estendem aqui
      and pr.display_name is not null   -- so registrados com nome
      and rp.finished_at is not null    -- ignora corridas nao-finalizadas
      and rp.finished_at >= rp.started_at  -- defesa: ignora duracao negativa (validado no ingest, defesa em profundidade)
    group by pr.display_name
  ) s
  order by s.score asc
  limit p_limit;
$$;

revoke all on function public.get_leaderboard(text, int) from public;
grant execute on function public.get_leaderboard(text, int) to anon, authenticated;
