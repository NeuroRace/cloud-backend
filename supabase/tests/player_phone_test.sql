-- NEU-159: corrida por celular, gatilho do celular e conta com dois jogadores.
-- Prova: envio so com player_phone cria/reaproveita o jogador do celular; celular fora do
-- formato nao grava nada; confirmar o celular liga a corrida a conta (Supabase guarda sem
-- o "+"); nao rouba vinculo; conta com e-mail + celular aparece uma vez no ranking, com o
-- melhor tempo dos dois, e le as corridas dos dois (RLS).
\set ON_ERROR_STOP on

begin;
delete from telemetry_points; delete from race_players; delete from races; delete from players;
delete from public.profiles where id in ('f0000000-0000-0000-0000-0000000000f1','f0000000-0000-0000-0000-0000000000f2','f0000000-0000-0000-0000-0000000000f3');
delete from auth.users where id in ('f0000000-0000-0000-0000-0000000000f1','f0000000-0000-0000-0000-0000000000f2','f0000000-0000-0000-0000-0000000000f3');
delete from auth.users where phone in ('5511987654321','5521998765432','5531991234567','551134567890') or email = 'phone_both@test.com';
commit;

-- ===== schema =====
do $$ begin
  assert (select is_nullable from information_schema.columns
          where table_schema='public' and table_name='players' and column_name='email') = 'YES',
    'email passa a ser opcional';
  assert not exists (select 1 from pg_constraint where conname = 'players_user_id_key'),
    'sai a trava uma conta, um jogador';
  begin
    insert into players (id) values (gen_random_uuid());
    assert false, 'jogador sem e-mail e sem celular nao pode existir';
  exception when check_violation then null;
  end;
end $$;

-- ===== ingest por celular =====
do $$
declare
  base jsonb := '{"schema_version":"1.0","player_slot":1,"player_uuid":null,"source":"real",
                  "started_at":1767225600000,"finished_at":1767225660000,
                  "telemetry_points":[{"t":1767225601000,"attention":80,"meditation":55,
                    "poor_signal_level":0,"signal_status":"ok","eeg_power":{"delta":1}}]}';
  r jsonb;
begin
  r := ingest_race(base || '{"idempotency_key":"a1000000-0000-4000-8000-000000000001","race_id":"b1000000-0000-4000-8000-000000000001","player_phone":"+5511987654321"}');
  assert r->>'status' = 'created', 'envio so com celular cria a corrida';
  assert (select count(*) from players where phone = '+5511987654321' and email is null) = 1,
    'cria o jogador do celular';
  assert (select count(*) from telemetry_points tp join race_players rp on rp.id = tp.race_player_id
          join players p on p.id = rp.player_id where p.phone = '+5511987654321') = 1,
    'telemetria gravada no jogador do celular';

  r := ingest_race(base || '{"idempotency_key":"a1000000-0000-4000-8000-000000000002","race_id":"b1000000-0000-4000-8000-000000000002","player_phone":"+5511987654321"}');
  assert r->>'status' = 'created', 'segunda corrida do mesmo celular';
  assert (select count(*) from players where phone = '+5511987654321') = 1, 'mesmo celular reaproveita o jogador';
  assert (select count(*) from race_players rp join players p on p.id = rp.player_id
          where p.phone = '+5511987654321') = 2, 'duas corridas no mesmo jogador';

  r := ingest_race(base || '{"idempotency_key":"a1000000-0000-4000-8000-000000000001","race_id":"b1000000-0000-4000-8000-000000000001","player_phone":"+5511987654321"}');
  assert r->>'status' = 'duplicate', 'replay do mesmo envio continua duplicate';

  -- defesa em profundidade (o contrato ja recusa): formato errado nao grava nada
  begin
    perform ingest_race(base || '{"idempotency_key":"a1000000-0000-4000-8000-000000000003","race_id":"b1000000-0000-4000-8000-000000000003","player_phone":"11987654321"}');
    assert false, 'celular sem +55 tem que falhar';
  exception when check_violation then null;
  end;
  assert not exists (select 1 from races where id = 'b1000000-0000-4000-8000-000000000003'), 'celular invalido nao cria corrida';
  assert not exists (select 1 from players where phone = '11987654321'), 'celular invalido nao cria jogador';
end $$;

-- ===== gatilho do celular =====
do $$
declare
  u1 uuid := 'f0000000-0000-0000-0000-0000000000f1';
  u2 uuid := 'f0000000-0000-0000-0000-0000000000f2';
begin
  -- signup por celular NAO confirmado -> nao vincula. O Supabase guarda o celular sem o "+".
  insert into auth.users (instance_id, id, aud, role, phone, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', u1, 'authenticated','authenticated','5511987654321', now(), now());
  assert (select user_id from players where phone = '+5511987654321') is null, 'celular nao confirmado nao vincula';

  update auth.users set phone_confirmed_at = now() where id = u1;
  assert (select user_id from players where phone = '+5511987654321') = u1, 'celular confirmado vincula o jogador';
  assert (select count(*) from players where phone = '+5511987654321') = 1, 'vincular nao duplica o jogador';

  -- troca de numero ja confirmado: o novo celular tambem liga (o antigo segue da conta)
  update auth.users set phone = '5521998765432' where id = u1;
  assert (select user_id from players where phone = '+5521998765432') = u1, 'troca de celular confirmado vincula o novo';

  -- anti-roubo: outro usuario confirmando o celular antigo (agora livre no auth) nao rouba o vinculo
  insert into auth.users (instance_id, id, aud, role, phone, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', u2, 'authenticated','authenticated','5511987654321', now(), now());
  update auth.users set phone_confirmed_at = now() where id = u2;
  assert (select user_id from players where phone = '+5511987654321') = u1, 'segundo usuario nao rouba o vinculo';

  -- telefone fora do formato do edge (fixo) nao vira jogador
  update auth.users set phone = '551134567890' where id = u2;
  assert not exists (select 1 from players where user_id = u2), 'fixo confirmado nao cria jogador';
end $$;

-- ===== conta com jogador do e-mail e jogador do celular =====
do $$
declare
  u3 uuid := 'f0000000-0000-0000-0000-0000000000f3';
  base jsonb := '{"schema_version":"1.0","player_slot":1,"player_uuid":null,"source":"real",
                  "started_at":1767225600000,"telemetry_points":[]}';
  lb record;
begin
  -- correu com e-mail (90 s) e com celular (45 s) antes de ter conta
  perform ingest_race(base || '{"idempotency_key":"a3000000-0000-4000-8000-000000000001","race_id":"b3000000-0000-4000-8000-000000000001","player_email":"phone_both@test.com","finished_at":1767225690000}');
  perform ingest_race(base || '{"idempotency_key":"a3000000-0000-4000-8000-000000000002","race_id":"b3000000-0000-4000-8000-000000000002","player_phone":"+5531991234567","finished_at":1767225645000}');

  insert into auth.users (instance_id, id, aud, role, email, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', u3, 'authenticated','authenticated','phone_both@test.com', now(), now());
  update auth.users set email_confirmed_at = now() where id = u3;
  update auth.users set phone = '5531991234567', phone_confirmed_at = now() where id = u3;
  update public.profiles set display_name = 'DoisContatos' where id = u3;

  assert (select count(*) from players where user_id = u3) = 2, 'a conta tem o jogador do e-mail e o do celular';
  assert (select count(*) from get_leaderboard() where display_name = 'DoisContatos') = 1, 'aparece uma vez no ranking';
  select * into lb from get_leaderboard() where display_name = 'DoisContatos';
  assert lb.score = 45, 'vale o melhor tempo dos dois (45 s do celular)';
end $$;

begin;
set local role authenticated;
set local request.jwt.claims to '{"sub":"f0000000-0000-0000-0000-0000000000f3","role":"authenticated"}';
do $$ begin
  assert (select count(*) from players) = 2, 'a pessoa le os dois jogadores dela';
  assert (select count(*) from race_players) = 2, 'o dashboard le as corridas dos dois';
  assert (select count(*) from races) = 2, 'e as duas corridas';
end $$;
commit;

-- ===== limpeza =====
begin;
delete from telemetry_points; delete from race_players; delete from races; delete from players;
delete from public.profiles where id in ('f0000000-0000-0000-0000-0000000000f1','f0000000-0000-0000-0000-0000000000f2','f0000000-0000-0000-0000-0000000000f3');
delete from auth.users where id in ('f0000000-0000-0000-0000-0000000000f1','f0000000-0000-0000-0000-0000000000f2','f0000000-0000-0000-0000-0000000000f3');
delete from auth.users where phone in ('5511987654321','5521998765432','5531991234567','551134567890') or email = 'phone_both@test.com';
commit;
\echo 'player_phone_test OK'
