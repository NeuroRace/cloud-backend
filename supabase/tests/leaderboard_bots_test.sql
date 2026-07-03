\set ON_ERROR_STOP on

-- Prova o filtro `source = 'real'` da get_leaderboard (migration leaderboard_exclude_bots).
-- Cenario:
--   RealRacer  -> 1 corrida REAL de 100s.
--   BotRacer   -> 1 corrida BOT de 5s (rapidissima). Nao pode aparecer.
--   MixedRacer -> 1 corrida REAL de 100s + 1 corrida BOT de 5s. Score deve ser 100 (o bot e ignorado, nao 5).
-- Sem o filtro, BotRacer (5s) seria rank 1 e o score de MixedRacer seria 5. Com o filtro, isso nao ocorre.
-- Deterministico (uuids e timestamps fixos; sem now()/random). Limpa o proprio seed.

begin;
-- cleanup defensivo (idempotente)
delete from race_players where id in ('0f000000-0000-0000-0000-0000000000a1','0f000000-0000-0000-0000-0000000000b1','0f000000-0000-0000-0000-0000000000c1','0f000000-0000-0000-0000-0000000000d1');
delete from races        where id in ('0e000000-0000-0000-0000-0000000000a1','0e000000-0000-0000-0000-0000000000b1','0e000000-0000-0000-0000-0000000000c1','0e000000-0000-0000-0000-0000000000d1');
delete from players      where id in ('0f111111-0000-0000-0000-000000000001','0f222222-0000-0000-0000-000000000002','0f333333-0000-0000-0000-000000000003');
delete from public.profiles where id in ('0e111111-0000-0000-0000-000000000001','0e222222-0000-0000-0000-000000000002','0e333333-0000-0000-0000-000000000003');
delete from auth.users   where email in ('lb_real@bots.test','lb_bot@bots.test','lb_mix@bots.test');

insert into auth.users (instance_id, id, aud, role, email, created_at, updated_at) values
 ('00000000-0000-0000-0000-000000000000','0e111111-0000-0000-0000-000000000001','authenticated','authenticated','lb_real@bots.test','2026-01-01 00:00:00+00','2026-01-01 00:00:00+00'),
 ('00000000-0000-0000-0000-000000000000','0e222222-0000-0000-0000-000000000002','authenticated','authenticated','lb_bot@bots.test','2026-01-01 00:00:00+00','2026-01-01 00:00:00+00'),
 ('00000000-0000-0000-0000-000000000000','0e333333-0000-0000-0000-000000000003','authenticated','authenticated','lb_mix@bots.test','2026-01-01 00:00:00+00','2026-01-01 00:00:00+00');
-- o trigger handle_new_user_profile cria o profile (display_name null); damos o nome:
update public.profiles set display_name='RealRacer'  where id='0e111111-0000-0000-0000-000000000001';
update public.profiles set display_name='BotRacer'   where id='0e222222-0000-0000-0000-000000000002';
update public.profiles set display_name='MixedRacer' where id='0e333333-0000-0000-0000-000000000003';

insert into players (id, email, user_id) values
 ('0f111111-0000-0000-0000-000000000001','lb_real@bots.test','0e111111-0000-0000-0000-000000000001'),
 ('0f222222-0000-0000-0000-000000000002','lb_bot@bots.test','0e222222-0000-0000-0000-000000000002'),
 ('0f333333-0000-0000-0000-000000000003','lb_mix@bots.test','0e333333-0000-0000-0000-000000000003');

insert into races (id, started_at) values
 ('0e000000-0000-0000-0000-0000000000a1','2026-01-01 00:00:00+00'),
 ('0e000000-0000-0000-0000-0000000000b1','2026-01-01 00:00:00+00'),
 ('0e000000-0000-0000-0000-0000000000c1','2026-01-01 00:00:00+00'),
 ('0e000000-0000-0000-0000-0000000000d1','2026-01-01 00:00:00+00');

-- (id, idempotency_key, race_id, player_id, player_slot, started_at, finished_at, source)
insert into race_players (id, idempotency_key, race_id, player_id, player_slot, started_at, finished_at, source) values
 -- RealRacer: 100s real
 ('0f000000-0000-0000-0000-0000000000a1','1a000000-0000-0000-0000-0000000000a1','0e000000-0000-0000-0000-0000000000a1','0f111111-0000-0000-0000-000000000001',1,'2026-01-01 00:00:00+00','2026-01-01 00:01:40+00','real'),
 -- BotRacer: 5s BOT (rapidissima; NAO pode aparecer)
 ('0f000000-0000-0000-0000-0000000000b1','1a000000-0000-0000-0000-0000000000b1','0e000000-0000-0000-0000-0000000000b1','0f222222-0000-0000-0000-000000000002',1,'2026-01-01 00:00:00+00','2026-01-01 00:00:05+00','bot'),
 -- MixedRacer: 100s real
 ('0f000000-0000-0000-0000-0000000000c1','1a000000-0000-0000-0000-0000000000c1','0e000000-0000-0000-0000-0000000000c1','0f333333-0000-0000-0000-000000000003',1,'2026-01-01 00:00:00+00','2026-01-01 00:01:40+00','real'),
 -- MixedRacer: 5s BOT (deve ser ignorada no score)
 ('0f000000-0000-0000-0000-0000000000d1','1a000000-0000-0000-0000-0000000000d1','0e000000-0000-0000-0000-0000000000d1','0f333333-0000-0000-0000-000000000003',2,'2026-01-01 00:00:00+00','2026-01-01 00:00:05+00','bot');
commit;

begin;
set local role anon;
do $$
declare r record;
begin
  -- BotRacer (so tem corrida bot) NAO aparece
  assert (select count(*) from get_leaderboard('best_time',1000) where display_name='BotRacer') = 0,
    'BotRacer (source=bot) NAO deve aparecer no leaderboard';

  -- Nenhuma linha com score < 100 deveria existir no nosso seed (o unico <100 seria o bot de 5s)
  assert (select count(*) from get_leaderboard('best_time',1000) where display_name in ('RealRacer','BotRacer','MixedRacer') and score < 100) = 0,
    'nenhuma corrida de bot (5s) pode entrar: nao deve haver score < 100 no nosso seed';

  -- RealRacer aparece com 100s
  select * into r from get_leaderboard('best_time',1000) where display_name='RealRacer';
  assert r.score = 100, 'RealRacer deve pontuar 100s (corrida real). veio '||coalesce(r.score::text,'NULL');

  -- MixedRacer aparece com 100s (o bot de 5s e ignorado, senao seria 5)
  select * into r from get_leaderboard('best_time',1000) where display_name='MixedRacer';
  assert r.score = 100, 'MixedRacer deve pontuar 100s (o bot de 5s e ignorado, nao 5). veio '||coalesce(r.score::text,'NULL');
end $$;
commit;

-- limpeza
delete from race_players where id in ('0f000000-0000-0000-0000-0000000000a1','0f000000-0000-0000-0000-0000000000b1','0f000000-0000-0000-0000-0000000000c1','0f000000-0000-0000-0000-0000000000d1');
delete from races        where id in ('0e000000-0000-0000-0000-0000000000a1','0e000000-0000-0000-0000-0000000000b1','0e000000-0000-0000-0000-0000000000c1','0e000000-0000-0000-0000-0000000000d1');
delete from players      where id in ('0f111111-0000-0000-0000-000000000001','0f222222-0000-0000-0000-000000000002','0f333333-0000-0000-0000-000000000003');
delete from public.profiles where id in ('0e111111-0000-0000-0000-000000000001','0e222222-0000-0000-0000-000000000002','0e333333-0000-0000-0000-000000000003');
delete from auth.users   where email in ('lb_real@bots.test','lb_bot@bots.test','lb_mix@bots.test');
select 'leaderboard_bots_test OK' as result;
