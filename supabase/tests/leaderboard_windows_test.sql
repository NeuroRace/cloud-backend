\set ON_ERROR_STOP on

-- NEU-110: get_leaderboard com periodo (p_from/p_to) e desempate por quem fez primeiro.
-- Seed deterministico em 2031-03-15 (UTC). Rodadas: R1 [10:00,12:00), R2 [12:00,14:00).
--   Ana : 30s terminou 11:00 (R1); comecou 12:10 e NAO terminou (R2)
--   Bia : 30s terminou 10:10 (R1); 30s terminou 11:50 (R1)
--   Caio: 20s terminou 12:00:00 exato (R2, fronteira); 50s terminou 13:00 (R2)
--   Duda: 25s terminou 13:30 (R2); 15s terminou 09:00 (antes do evento); 5s BOT terminou 12:30 (R2)
-- Esperado:
--   R1     : Bia 30 (rank 1, fez primeiro), Ana 30 (rank 2)
--            (desempate alfabetico daria Ana primeiro; usar a 2a corrida da Bia, 11:50, tambem)
--   R2     : Caio 20 (rank 1), Duda 25 (rank 2)   [sem Ana nao-terminada, sem bot]
--   Evento (p_from=10:00): Caio 20, Duda 25, Bia 30, Ana 30 (ranks 1..4)
--   Geral  (sem periodo) : Duda 15 na frente de Caio 20

begin;
delete from race_players where id::text like '5d000000-%';
delete from races        where id::text like '5c000000-%';
delete from players      where id::text like '5b000000-%';
delete from auth.users   where email like 'lbw\_%@neu110.test';

insert into auth.users (instance_id, id, aud, role, email, created_at, updated_at) values
 ('00000000-0000-0000-0000-000000000000','5a000000-0000-0000-0000-000000000001','authenticated','authenticated','lbw_ana@neu110.test', '2031-01-01 00:00+00','2031-01-01 00:00+00'),
 ('00000000-0000-0000-0000-000000000000','5a000000-0000-0000-0000-000000000002','authenticated','authenticated','lbw_bia@neu110.test', '2031-01-01 00:00+00','2031-01-01 00:00+00'),
 ('00000000-0000-0000-0000-000000000000','5a000000-0000-0000-0000-000000000003','authenticated','authenticated','lbw_caio@neu110.test','2031-01-01 00:00+00','2031-01-01 00:00+00'),
 ('00000000-0000-0000-0000-000000000000','5a000000-0000-0000-0000-000000000004','authenticated','authenticated','lbw_duda@neu110.test','2031-01-01 00:00+00','2031-01-01 00:00+00');
-- o trigger handle_new_user_profile cria os profiles; damos os apelidos
update public.profiles set display_name = 'W110Ana'  where id = '5a000000-0000-0000-0000-000000000001';
update public.profiles set display_name = 'W110Bia'  where id = '5a000000-0000-0000-0000-000000000002';
update public.profiles set display_name = 'W110Caio' where id = '5a000000-0000-0000-0000-000000000003';
update public.profiles set display_name = 'W110Duda' where id = '5a000000-0000-0000-0000-000000000004';

insert into players (id, email, user_id) values
 ('5b000000-0000-0000-0000-000000000001','lbw_ana@neu110.test', '5a000000-0000-0000-0000-000000000001'),
 ('5b000000-0000-0000-0000-000000000002','lbw_bia@neu110.test', '5a000000-0000-0000-0000-000000000002'),
 ('5b000000-0000-0000-0000-000000000003','lbw_caio@neu110.test','5a000000-0000-0000-0000-000000000003'),
 ('5b000000-0000-0000-0000-000000000004','lbw_duda@neu110.test','5a000000-0000-0000-0000-000000000004');

insert into races (id, started_at) values
 ('5c000000-0000-0000-0000-000000000001','2031-03-15 10:09:30+00'),
 ('5c000000-0000-0000-0000-000000000002','2031-03-15 11:49:30+00'),
 ('5c000000-0000-0000-0000-000000000003','2031-03-15 10:59:30+00'),
 ('5c000000-0000-0000-0000-000000000004','2031-03-15 11:59:40+00'),
 ('5c000000-0000-0000-0000-000000000005','2031-03-15 12:59:10+00'),
 ('5c000000-0000-0000-0000-000000000006','2031-03-15 13:29:35+00'),
 ('5c000000-0000-0000-0000-000000000007','2031-03-15 08:59:45+00'),
 ('5c000000-0000-0000-0000-000000000008','2031-03-15 12:29:55+00'),
 ('5c000000-0000-0000-0000-000000000009','2031-03-15 12:10:00+00');

-- (id, idempotency_key, race_id, player_id, slot, started_at, finished_at, source)
insert into race_players (id, idempotency_key, race_id, player_id, player_slot, started_at, finished_at, source) values
 ('5d000000-0000-0000-0000-000000000001', gen_random_uuid(), '5c000000-0000-0000-0000-000000000001','5b000000-0000-0000-0000-000000000002',1,'2031-03-15 10:09:30+00','2031-03-15 10:10:00+00','real'),
 ('5d000000-0000-0000-0000-000000000002', gen_random_uuid(), '5c000000-0000-0000-0000-000000000002','5b000000-0000-0000-0000-000000000002',1,'2031-03-15 11:49:30+00','2031-03-15 11:50:00+00','real'),
 ('5d000000-0000-0000-0000-000000000003', gen_random_uuid(), '5c000000-0000-0000-0000-000000000003','5b000000-0000-0000-0000-000000000001',1,'2031-03-15 10:59:30+00','2031-03-15 11:00:00+00','real'),
 ('5d000000-0000-0000-0000-000000000004', gen_random_uuid(), '5c000000-0000-0000-0000-000000000004','5b000000-0000-0000-0000-000000000003',1,'2031-03-15 11:59:40+00','2031-03-15 12:00:00+00','real'),
 ('5d000000-0000-0000-0000-000000000005', gen_random_uuid(), '5c000000-0000-0000-0000-000000000005','5b000000-0000-0000-0000-000000000003',1,'2031-03-15 12:59:10+00','2031-03-15 13:00:00+00','real'),
 ('5d000000-0000-0000-0000-000000000006', gen_random_uuid(), '5c000000-0000-0000-0000-000000000006','5b000000-0000-0000-0000-000000000004',1,'2031-03-15 13:29:35+00','2031-03-15 13:30:00+00','real'),
 ('5d000000-0000-0000-0000-000000000007', gen_random_uuid(), '5c000000-0000-0000-0000-000000000007','5b000000-0000-0000-0000-000000000004',1,'2031-03-15 08:59:45+00','2031-03-15 09:00:00+00','real'),
 ('5d000000-0000-0000-0000-000000000008', gen_random_uuid(), '5c000000-0000-0000-0000-000000000008','5b000000-0000-0000-0000-000000000004',1,'2031-03-15 12:29:55+00','2031-03-15 12:30:00+00','bot'),
 ('5d000000-0000-0000-0000-000000000009', gen_random_uuid(), '5c000000-0000-0000-0000-000000000009','5b000000-0000-0000-0000-000000000001',1,'2031-03-15 12:10:00+00',null,'real');
commit;

-- chamadas como ANON (ranking publico). Rodadas escritas com offset -03, como o operador cadastra.
begin;
set local role anon;
do $$
declare
  r1_from constant timestamptz := '2031-03-15 07:00-03';
  r1_to   constant timestamptz := '2031-03-15 09:00-03';
  r2_from constant timestamptz := '2031-03-15 09:00-03';
  r2_to   constant timestamptz := '2031-03-15 11:00-03';
  names   text;
  ranks   text;
begin
  -- R1: Ana e Bia empatam em 30s; Bia fez primeiro (10:10 < 11:00) -> rank 1 e 2, distintos
  select string_agg(display_name, ',' order by rank, display_name),
         string_agg(rank::text || ':' || score::int, ',' order by rank, display_name)
    into names, ranks
    from get_leaderboard('best_time', 50, r1_from, r1_to);
  assert names = 'W110Bia,W110Ana', 'R1 deve ser Bia,Ana (Bia fez 30s primeiro). veio '||coalesce(names,'NULL');
  assert ranks = '1:30,2:30', 'R1: empate de 30s resolvido por quem fez primeiro (1:30,2:30). veio '||coalesce(ranks,'NULL');

  -- R2: Caio 20 (terminou 12:00:00 exato -> entra em R2), Duda 25.
  -- Sem Ana (nao terminou), sem o bot de 5s da Duda, sem os 50s do Caio (vale o melhor).
  select string_agg(display_name, ',' order by rank, display_name),
         string_agg(rank::text || ':' || score::int, ',' order by rank, display_name)
    into names, ranks
    from get_leaderboard('best_time', 50, r2_from, r2_to);
  assert names = 'W110Caio,W110Duda', 'R2 deve ser Caio,Duda. veio '||coalesce(names,'NULL');
  assert ranks = '1:20,2:25', 'R2 deve ser 1:20,2:25. veio '||coalesce(ranks,'NULL');

  -- Fronteira: Caio (12:00:00) NAO entra em R1
  assert (select count(*) from get_leaderboard('best_time', 50, r1_from, r1_to) where display_name = 'W110Caio') = 0,
    'corrida terminada exatamente em ends_at nao pode entrar na rodada que acaba';

  -- Evento (so p_from, como o site faz): ignora os 15s da Duda (09:00, antes do evento)
  select string_agg(display_name, ',' order by rank, display_name),
         string_agg(rank::text || ':' || score::int, ',' order by rank, display_name)
    into names, ranks
    from get_leaderboard('best_time', 50, r1_from);
  assert names = 'W110Caio,W110Duda,W110Bia,W110Ana', 'Evento deve ser Caio,Duda,Bia,Ana. veio '||coalesce(names,'NULL');
  assert ranks = '1:20,2:25,3:30,4:30', 'Evento deve ser 1:20,2:25,3:30,4:30. veio '||coalesce(ranks,'NULL');

  -- p_from > p_to: vazio, sem erro
  assert (select count(*) from get_leaderboard('best_time', 50, r2_to, r1_from)) = 0,
    'p_from > p_to deve devolver vazio';

  -- Chamada antiga (posicional, 2 args): ranking geral, conta os 15s da Duda
  assert (select score from get_leaderboard('best_time', 1000) where display_name = 'W110Duda') = 15,
    'sem periodo, Duda deve ter 15s (melhor de sempre)';
  assert (select rank from get_leaderboard('best_time', 1000) where display_name = 'W110Duda')
       < (select rank from get_leaderboard('best_time', 1000) where display_name = 'W110Caio'),
    'sem periodo, Duda (15s) fica na frente de Caio (20s)';

  -- Chamada com nomes, como o PostgREST/supabase-js faz
  assert (select count(*) from get_leaderboard(p_metric => 'best_time', p_limit => 1000) where display_name like 'W110%') = 4,
    'chamada nomeada sem periodo deve devolver os 4 jogadores';

  -- metrica desconhecida continua vazia, mesmo com periodo
  assert (select count(*) from get_leaderboard('xxx', 50, r1_from, r2_to)) = 0, 'metrica desconhecida -> vazio';
end $$;
commit;

-- uma unica sobrecarga (senao o PostgREST nao escolhe entre elas)
do $$
begin
  assert (select count(*) from pg_proc
          where proname = 'get_leaderboard' and pronamespace = 'public'::regnamespace) = 1,
    'deve existir exatamente uma public.get_leaderboard';
end $$;

-- limpeza
delete from race_players where id::text like '5d000000-%';
delete from races        where id::text like '5c000000-%';
delete from players      where id::text like '5b000000-%';
delete from auth.users   where email like 'lbw\_%@neu110.test';
select 'leaderboard_windows_test OK' as result;
