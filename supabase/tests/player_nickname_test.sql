-- Apelido do site no estande: ingest_race com player_nickname.
-- Prova: o apelido acha a conta sem ligar para maiuscula/minuscula e grava a corrida no
-- jogador da conta (o do e-mail primeiro; sem ele, o do celular); apelido que nao existe
-- (ou conta sem jogador) devolve unknown_nickname e nao grava nada; replay e duplicate;
-- e-mail e celular seguem iguais.
\set ON_ERROR_STOP on

begin;
delete from telemetry_points; delete from race_players; delete from races; delete from players;
delete from public.profiles where id in ('e0000000-0000-0000-0000-0000000000e1','e0000000-0000-0000-0000-0000000000e2','e0000000-0000-0000-0000-0000000000e3','e0000000-0000-0000-0000-0000000000e4');
delete from auth.users where id in ('e0000000-0000-0000-0000-0000000000e1','e0000000-0000-0000-0000-0000000000e2','e0000000-0000-0000-0000-0000000000e3','e0000000-0000-0000-0000-0000000000e4');
commit;

-- ===== seed: contas pelo caminho real (gatilhos do signup e da confirmacao) =====
do $$
begin
  -- e1: so e-mail confirmado, apelido Breq_Nick
  insert into auth.users (instance_id, id, aud, role, email, created_at, updated_at) values
    ('00000000-0000-0000-0000-000000000000','e0000000-0000-0000-0000-0000000000e1','authenticated','authenticated','nick_a@test.com',now(),now());
  update auth.users set email_confirmed_at = now() where id = 'e0000000-0000-0000-0000-0000000000e1';
  update public.profiles set display_name = 'Breq_Nick' where id = 'e0000000-0000-0000-0000-0000000000e1';

  -- e2: e-mail e celular confirmados (dois jogadores na mesma conta)
  insert into auth.users (instance_id, id, aud, role, email, phone, created_at, updated_at) values
    ('00000000-0000-0000-0000-000000000000','e0000000-0000-0000-0000-0000000000e2','authenticated','authenticated','nick_b@test.com','5511912345678',now(),now());
  update auth.users set phone_confirmed_at = now() where id = 'e0000000-0000-0000-0000-0000000000e2';
  update auth.users set email_confirmed_at = now() where id = 'e0000000-0000-0000-0000-0000000000e2';
  update public.profiles set display_name = 'Dupla' where id = 'e0000000-0000-0000-0000-0000000000e2';

  -- e3: so celular confirmado
  insert into auth.users (instance_id, id, aud, role, phone, created_at, updated_at) values
    ('00000000-0000-0000-0000-000000000000','e0000000-0000-0000-0000-0000000000e3','authenticated','authenticated','5521912345678',now(),now());
  update auth.users set phone_confirmed_at = now() where id = 'e0000000-0000-0000-0000-0000000000e3';
  update public.profiles set display_name = 'SoCel' where id = 'e0000000-0000-0000-0000-0000000000e3';

  -- e4: apelido, mas nunca confirmou nada (sem jogador)
  insert into auth.users (instance_id, id, aud, role, email, created_at, updated_at) values
    ('00000000-0000-0000-0000-000000000000','e0000000-0000-0000-0000-0000000000e4','authenticated','authenticated','nick_d@test.com',now(),now());
  update public.profiles set display_name = 'SemJogador' where id = 'e0000000-0000-0000-0000-0000000000e4';

  assert (select count(*) from players where user_id = 'e0000000-0000-0000-0000-0000000000e1') = 1, 'seed: e1 tem 1 jogador';
  assert (select count(*) from players where user_id = 'e0000000-0000-0000-0000-0000000000e2') = 2, 'seed: e2 tem 2 jogadores';
  assert (select count(*) from players where user_id = 'e0000000-0000-0000-0000-0000000000e3') = 1, 'seed: e3 tem 1 jogador';
  assert (select count(*) from players where user_id = 'e0000000-0000-0000-0000-0000000000e4') = 0, 'seed: e4 sem jogador';
end $$;

-- ===== ingest por apelido =====
do $$
declare
  base jsonb := '{"schema_version":"1.0","player_slot":1,"player_uuid":null,"source":"real",
                  "started_at":1767225600000,"finished_at":1767225660000,
                  "telemetry_points":[{"t":1767225601000,"attention":80,"meditation":55,
                    "poor_signal_level":0,"signal_status":"ok","eeg_power":{"delta":1}}]}';
  r jsonb;
  n_players int := (select count(*) from players);
  p_e1 uuid := (select id from players where user_id = 'e0000000-0000-0000-0000-0000000000e1');
  p_e2_email uuid := (select id from players where user_id = 'e0000000-0000-0000-0000-0000000000e2' and email is not null);
  p_e3 uuid := (select id from players where user_id = 'e0000000-0000-0000-0000-0000000000e3');
begin
  -- maiuscula/minuscula nao importa
  r := ingest_race(base || '{"idempotency_key":"c1000000-0000-4000-8000-000000000001","race_id":"d1000000-0000-4000-8000-000000000001","player_nickname":"BREQ_NICK"}');
  assert r->>'status' = 'created', 'apelido em caixa alta cria a corrida';
  assert (select player_id from race_players where idempotency_key = 'c1000000-0000-4000-8000-000000000001') = p_e1,
    'corrida cai no jogador da conta do apelido';
  assert (select count(*) from telemetry_points tp join race_players rp on rp.id = tp.race_player_id
          where rp.idempotency_key = 'c1000000-0000-4000-8000-000000000001') = 1, 'telemetria gravada';

  r := ingest_race(base || '{"idempotency_key":"c1000000-0000-4000-8000-000000000002","race_id":"d1000000-0000-4000-8000-000000000002","player_nickname":"breq_nick"}');
  assert r->>'status' = 'created', 'apelido em minuscula tambem';
  assert (select player_id from race_players where idempotency_key = 'c1000000-0000-4000-8000-000000000002') = p_e1,
    'minuscula cai no mesmo jogador';

  r := ingest_race(base || '{"idempotency_key":"c1000000-0000-4000-8000-000000000001","race_id":"d1000000-0000-4000-8000-000000000001","player_nickname":"Breq_Nick"}');
  assert r->>'status' = 'duplicate', 'replay do mesmo envio e duplicate';

  -- conta com e-mail e celular: o jogador do e-mail
  r := ingest_race(base || '{"idempotency_key":"c1000000-0000-4000-8000-000000000003","race_id":"d1000000-0000-4000-8000-000000000003","player_nickname":"dupla"}');
  assert r->>'status' = 'created', 'conta com dois jogadores';
  assert (select player_id from race_players where idempotency_key = 'c1000000-0000-4000-8000-000000000003') = p_e2_email,
    'prefere o jogador do e-mail';

  -- conta so com celular: o jogador do celular
  r := ingest_race(base || '{"idempotency_key":"c1000000-0000-4000-8000-000000000004","race_id":"d1000000-0000-4000-8000-000000000004","player_nickname":"SOCEL"}');
  assert r->>'status' = 'created', 'conta so com celular';
  assert (select player_id from race_players where idempotency_key = 'c1000000-0000-4000-8000-000000000004') = p_e3,
    'usa o jogador do celular';

  -- apelido que nao existe e conta sem jogador: unknown_nickname, nada gravado
  r := ingest_race(base || '{"idempotency_key":"c1000000-0000-4000-8000-000000000005","race_id":"d1000000-0000-4000-8000-000000000005","player_nickname":"NaoExiste"}');
  assert r->>'status' = 'unknown_nickname', 'apelido inexistente devolve unknown_nickname';
  r := ingest_race(base || '{"idempotency_key":"c1000000-0000-4000-8000-000000000006","race_id":"d1000000-0000-4000-8000-000000000006","player_nickname":"SemJogador"}');
  assert r->>'status' = 'unknown_nickname', 'conta sem jogador devolve unknown_nickname';
  assert not exists (select 1 from races where id in ('d1000000-0000-4000-8000-000000000005','d1000000-0000-4000-8000-000000000006')),
    'nenhuma race criada para apelido sem conta';
  assert not exists (select 1 from race_players where idempotency_key in ('c1000000-0000-4000-8000-000000000005','c1000000-0000-4000-8000-000000000006')),
    'nenhum race_players para apelido sem conta';
  assert (select count(*) from players) = n_players, 'apelido nunca cria jogador';

  -- o mesmo envio depois de a pessoa criar a conta (reenvio do "Nao subiram") entra
  update public.profiles set display_name = 'NaoExiste' where id = 'e0000000-0000-0000-0000-0000000000e3';
  r := ingest_race(base || '{"idempotency_key":"c1000000-0000-4000-8000-000000000005","race_id":"d1000000-0000-4000-8000-000000000005","player_nickname":"NaoExiste"}');
  assert r->>'status' = 'created', 'reenvio depois do apelido criado entra';
  assert (select player_id from race_players where idempotency_key = 'c1000000-0000-4000-8000-000000000005') = p_e3,
    'reenvio cai na conta';

  -- e-mail e celular seguem como antes
  r := ingest_race(base || '{"idempotency_key":"c1000000-0000-4000-8000-000000000007","race_id":"d1000000-0000-4000-8000-000000000007","player_email":" NICK_A@test.com "}');
  assert r->>'status' = 'created', 'e-mail segue';
  assert (select player_id from race_players where idempotency_key = 'c1000000-0000-4000-8000-000000000007') = p_e1,
    'e-mail cai no mesmo jogador (normalizado)';
  r := ingest_race(base || '{"idempotency_key":"c1000000-0000-4000-8000-000000000008","race_id":"d1000000-0000-4000-8000-000000000008","player_phone":"+5531998887766"}');
  assert r->>'status' = 'created', 'celular segue';
  assert (select count(*) from players where phone = '+5531998887766' and user_id is null) = 1, 'celular novo cria jogador sem conta';
  r := ingest_race(base || '{"idempotency_key":"c1000000-0000-4000-8000-000000000009","race_id":"d1000000-0000-4000-8000-000000000009","player_email":"novo_nick@test.com"}');
  assert (select count(*) from players where email = 'novo_nick@test.com' and user_id is null) = 1, 'e-mail novo cria jogador sem conta';

  -- e-mail ganha do apelido se os dois vierem (o contrato ja recusa; defesa em profundidade)
  r := ingest_race(base || '{"idempotency_key":"c1000000-0000-4000-8000-00000000000a","race_id":"d1000000-0000-4000-8000-00000000000a","player_email":"novo_nick@test.com","player_nickname":"Breq_Nick"}');
  assert (select p.email from race_players rp join players p on p.id = rp.player_id
          where rp.idempotency_key = 'c1000000-0000-4000-8000-00000000000a') = 'novo_nick@test.com', 'e-mail tem prioridade';
end $$;

-- ===== limpeza =====
begin;
delete from telemetry_points; delete from race_players; delete from races; delete from players;
delete from public.profiles where id in ('e0000000-0000-0000-0000-0000000000e1','e0000000-0000-0000-0000-0000000000e2','e0000000-0000-0000-0000-0000000000e3','e0000000-0000-0000-0000-0000000000e4');
delete from auth.users where id in ('e0000000-0000-0000-0000-0000000000e1','e0000000-0000-0000-0000-0000000000e2','e0000000-0000-0000-0000-0000000000e3','e0000000-0000-0000-0000-0000000000e4');
commit;
