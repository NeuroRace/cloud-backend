\set ON_ERROR_STOP on

-- NEU-170: aviso de corrida registrada (com conta) e convite (sem conta), pela caixa de saida
-- da NEU-112. Tudo numa transacao com ROLLBACK no fim. O horario entra sempre por parametro.
--
-- Seed (UTC), aviso ligado as 10:00, espera 10 min, intervalo 30 min:
--   Rodada "C170 Rodada 1" 11:00-14:00. B 39,0 s as 11:30.
--   A (conta, e-mail confirmado): 41,0 s as 12:00 e 40,1 s as 12:08 -> um aviso, com 40,1 s, 2o.
--   S (sem conta, e-mail do estande): 50 s as 12:00 -> convite, sem tempo nem posicao.
--   P (sem conta, so celular): 50 s as 12:00 -> sem contato (WhatsApp e da NEU-113).
--   D (conta so com celular): 50 s as 12:00 -> sem contato.
--   X: so corrida de bot as 12:00 -> nada. E: corrida as 09:00, antes de ligar -> nada.

begin;

update public.avisos_corrida_config set corrida_ligada = true, corrida_ligada_em = '2020-06-01 10:00+00',
  espera_min = 10, intervalo_min = 30, validade_min = 120;

insert into auth.users (instance_id, id, aud, role, email, phone, email_confirmed_at, phone_confirmed_at, created_at, updated_at) values
 ('00000000-0000-0000-0000-000000000000','17000000-0000-0000-0000-00000000000a','authenticated','authenticated','av_a@neu170.test', null,'2020-01-01 00:00+00', null,'2020-01-01 00:00+00','2020-01-01 00:00+00'),
 ('00000000-0000-0000-0000-000000000000','17000000-0000-0000-0000-00000000000b','authenticated','authenticated','av_b@neu170.test', null,'2020-01-01 00:00+00', null,'2020-01-01 00:00+00','2020-01-01 00:00+00'),
 ('00000000-0000-0000-0000-000000000000','17000000-0000-0000-0000-00000000000d','authenticated','authenticated', null,'5511912345671', null,'2020-01-01 00:00+00','2020-01-01 00:00+00','2020-01-01 00:00+00');
update public.profiles set display_name = 'C170A' where id = '17000000-0000-0000-0000-00000000000a';
update public.profiles set display_name = 'C170B' where id = '17000000-0000-0000-0000-00000000000b';

insert into public.players (id, email, phone, user_id) values
 ('17010000-0000-0000-0000-00000000000a','av_a@neu170.test', null,'17000000-0000-0000-0000-00000000000a'),
 ('17010000-0000-0000-0000-00000000000b','av_b@neu170.test', null,'17000000-0000-0000-0000-00000000000b'),
 ('17010000-0000-0000-0000-00000000000d', null,'+5511912345671','17000000-0000-0000-0000-00000000000d'),
 ('17010000-0000-0000-0000-000000000005','av_s@neu170.test', null, null),
 ('17010000-0000-0000-0000-000000000006', null,'+5511912345672', null),
 ('17010000-0000-0000-0000-000000000007','av_x@neu170.test', null, null),
 ('17010000-0000-0000-0000-000000000008','av_e@neu170.test', null, null);

insert into public.ranking_windows (id, name, starts_at, ends_at) values
 ('17020000-0000-0000-0000-000000000001','C170 Rodada 1','2020-06-01 11:00+00','2020-06-01 14:00+00');

-- corrida: (n, jogador, segundos, terminou = chegou na nuvem, fonte)
create function pg_temp.corrida(n int, jogador uuid, segundos numeric, terminou timestamptz, fonte text default 'real')
returns void language sql as $$
  insert into public.races (id, started_at)
  values (('17030000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid, terminou - make_interval(secs => segundos));
  insert into public.race_players (id, idempotency_key, race_id, player_id, player_slot, source, started_at, finished_at, created_at)
  values (('17040000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
          ('17050000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
          ('17030000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
          jogador, 1, fonte, terminou - make_interval(secs => segundos), terminou, terminou);
$$;
select pg_temp.corrida(1,'17010000-0000-0000-0000-00000000000b',39.0,'2020-06-01 11:30+00');
select pg_temp.corrida(2,'17010000-0000-0000-0000-00000000000a',41.0,'2020-06-01 12:00+00');
select pg_temp.corrida(3,'17010000-0000-0000-0000-00000000000a',40.1,'2020-06-01 12:08+00');
select pg_temp.corrida(4,'17010000-0000-0000-0000-000000000005',50.0,'2020-06-01 12:00+00');
select pg_temp.corrida(5,'17010000-0000-0000-0000-000000000006',50.0,'2020-06-01 12:00+00');
select pg_temp.corrida(6,'17010000-0000-0000-0000-00000000000d',50.0,'2020-06-01 12:00+00');
select pg_temp.corrida(7,'17010000-0000-0000-0000-000000000007',30.0,'2020-06-01 12:00+00','bot');
select pg_temp.corrida(8,'17010000-0000-0000-0000-000000000008',30.0,'2020-06-01 09:00+00');

create function pg_temp.msgs(destino text) returns setof public.mensagens language sql as $$
  select * from public.mensagens where destino = $1 order by criada_em;
$$;

-- ===== Tempo no formato do site =====
do $$
begin
  assert public.mensagem_formata_tempo(48.3) = '48,3' || chr(160) || 's', 'tempo: 48,3 s, veio ' || public.mensagem_formata_tempo(48.3);
  assert public.mensagem_formata_tempo(65.34) = '1:05,3', 'tempo: 1:05,3, veio ' || public.mensagem_formata_tempo(65.34);
  assert public.mensagem_formata_tempo(40.06) = '40,1' || chr(160) || 's', 'tempo: arredonda 1 casa';
  assert public.mensagem_formata_tempo(59.96) = '1:00,0', 'tempo: 59,96 arredonda para 1:00,0, veio ' || public.mensagem_formata_tempo(59.96);
  assert public.mensagem_formata_tempo(0) = '—' and public.mensagem_formata_tempo(null) = '—', 'tempo: invalido vira —';
end $$;

-- ===== Antes da espera: nada =====
do $$
begin
  perform public.avisos_corrida_tick('2020-06-01 12:05+00');
  assert not exists (select 1 from pg_temp.msgs('av_a@neu170.test')), 'espera: A ainda pode jogar de novo, nada sai';
  assert not exists (select 1 from pg_temp.msgs('av_s@neu170.test')), 'espera: S tambem espera';
  assert (select count(*) from pg_temp.msgs('av_b@neu170.test')) = 1, 'espera: B jogou as 11:30 e ja recebeu';
end $$;

-- ===== Pronto 2: duas corridas em 10 min -> um aviso, com a melhor =====
do $$
declare m public.mensagens; r jsonb;
begin
  r := public.avisos_corrida_tick('2020-06-01 12:10+00');
  assert (r ->> 'erros')::int = 0, 'tick sem erros, veio ' || r::text;
  assert (select count(*) from pg_temp.msgs('av_a@neu170.test')) = 1, 'Pronto 2: um aviso so para A';
  select * into m from pg_temp.msgs('av_a@neu170.test');
  assert m.tipo = 'corrida_registrada' and m.canal = 'email' and m.estado = 'pendente', 'Pronto 2: aviso de corrida por e-mail';
  assert m.corpo_texto = 'Sua corrida no NeuroRace foi registrada: 40,1' || chr(160) || 's, 2º na C170 Rodada 1. '
                        || 'Veja seu card e seu arquétipo em https://neurorace-v2.vercel.app/dashboard.',
    'Pronto 2: texto 5 com a melhor (40,1 s) e a posicao, veio ' || m.corpo_texto;
  assert m.assunto = 'Sua corrida no NeuroRace foi registrada', 'assunto do texto 5';
  assert m.user_id = '17000000-0000-0000-0000-00000000000a', 'aviso ligado a conta';
  assert m.validade = '2020-06-01 14:10+00', 'validade: agora + 120 min';
  assert (select count(*) from public.avisos_corrida where mensagem_id = m.id and decisao = 'avisada') = 2,
    'as duas corridas da janela ficam marcadas';
end $$;

-- ===== Pronto 3: sem conta -> convite, sem tempo nem posicao =====
do $$
declare m public.mensagens;
begin
  select * into m from pg_temp.msgs('av_s@neu170.test');
  assert m.tipo = 'corrida_convite', 'Pronto 3: convite, veio ' || coalesce(m.tipo, 'nada');
  assert m.corpo_texto = 'Você jogou NeuroRace! Entre em https://neurorace-v2.vercel.app/login com este contato '
                        || 'para ver o resultado da sua corrida, seu card e seu arquétipo, e entrar no ranking.',
    'Pronto 3: texto 6, veio ' || m.corpo_texto;
  assert m.corpo_texto not like '%50,0%' and m.corpo_texto not like '%º%', 'Pronto 3: sem tempo nem posicao';
  assert m.assunto = 'Você jogou NeuroRace!', 'assunto do texto 6';
  assert m.player_id = '17010000-0000-0000-0000-000000000005' and m.user_id is null, 'convite ligado ao jogador';
end $$;

-- ===== Sem e-mail (so celular): fica registrado, sem mensagem =====
do $$
begin
  assert (select decisao from public.avisos_corrida where race_player_id = '17040000-0000-0000-0000-000000000005') = 'sem_contato',
    'so celular, sem conta: sem_contato';
  assert (select decisao from public.avisos_corrida where race_player_id = '17040000-0000-0000-0000-000000000006') = 'sem_contato',
    'conta so com celular: sem_contato';
  assert not exists (select 1 from public.mensagens where destino like '%5511912345%'), 'nada para celular (NEU-113)';
end $$;

-- ===== Pronto 1 e 4: bot e corrida de antes de ligar -> nada =====
do $$
begin
  assert not exists (select 1 from public.avisos_corrida where race_player_id = '17040000-0000-0000-0000-000000000007'),
    'Pronto 1: corrida de bot nao entra';
  assert not exists (select 1 from pg_temp.msgs('av_x@neu170.test')), 'Pronto 1: bot nao recebe';
  assert not exists (select 1 from public.avisos_corrida where race_player_id = '17040000-0000-0000-0000-000000000008'),
    'Pronto 4: corrida de antes de ligada_em nao entra';
  assert not exists (select 1 from pg_temp.msgs('av_e@neu170.test')), 'Pronto 4: nada para E';
end $$;

-- ===== Tick repetido nao duplica =====
do $$
begin
  perform public.avisos_corrida_tick('2020-06-01 12:11+00');
  assert (select count(*) from pg_temp.msgs('av_a@neu170.test')) = 1, 'tick repetido: A continua com um aviso';
  assert (select count(*) from public.mensagens where tipo like 'corrida_%') = 3, 'tick repetido: A, B e S, nada a mais';
end $$;

-- ===== Intervalo: jogou de novo dentro de 30 min -> sem novo aviso; depois -> novo aviso =====
do $$
begin
  perform pg_temp.corrida(9,'17010000-0000-0000-0000-00000000000a',38.0,'2020-06-01 12:20+00');
  perform public.avisos_corrida_tick('2020-06-01 12:40+00');
  assert (select count(*) from pg_temp.msgs('av_a@neu170.test')) = 1, 'intervalo: corrida das 12:20 nao gera 2o aviso';
  assert (select decisao from public.avisos_corrida where race_player_id = '17040000-0000-0000-0000-000000000009') = 'agrupada',
    'intervalo: fica agrupada';

  perform pg_temp.corrida(10,'17010000-0000-0000-0000-00000000000a',37.0,'2020-06-01 12:31+00');
  perform public.avisos_corrida_tick('2020-06-01 12:41+00');
  assert (select count(*) from pg_temp.msgs('av_a@neu170.test')) = 2, 'depois do intervalo: novo aviso';
  assert (select corpo_texto from pg_temp.msgs('av_a@neu170.test') offset 1) like '%37,0' || chr(160) || 's, 1º na C170 Rodada 1%',
    'novo aviso com a corrida nova e a posicao nova';

  -- Revisao 12: a corrida avisada nao e a melhor da conta na rodada -> sem posicao (a posicao
  -- seria de outra corrida e leria como se fosse desta).
  perform pg_temp.corrida(12,'17010000-0000-0000-0000-00000000000a',50.0,'2020-06-01 13:05+00');
  perform public.avisos_corrida_tick('2020-06-01 13:15+00');
  assert (select corpo_texto from pg_temp.msgs('av_a@neu170.test') offset 2)
       = 'Sua corrida no NeuroRace foi registrada: 50,0' || chr(160) || 's. '
         || 'Veja seu card e seu arquétipo em https://neurorace-v2.vercel.app/dashboard.',
    'Revisao 12: sem posicao quando a corrida nao e a melhor da rodada, veio '
      || coalesce((select corpo_texto from pg_temp.msgs('av_a@neu170.test') offset 2), 'nada');
end $$;

-- ===== Desligado: nao roda; contato bloqueado: a caixa de saida ja bloqueia =====
do $$
declare r jsonb;
begin
  update public.avisos_corrida_config set corrida_ligada = false;
  r := public.avisos_corrida_tick('2020-06-01 13:30+00');
  assert (r ->> 'rodou')::boolean = false, 'desligado: nao roda, veio ' || r::text;
  update public.avisos_corrida_config set corrida_ligada = true;

  insert into public.mensagens_bloqueio values ('email', 'av_b@neu170.test', 'teste', '2020-06-01 13:00+00');
  perform pg_temp.corrida(11,'17010000-0000-0000-0000-00000000000b',36.0,'2020-06-01 13:10+00');
  perform public.avisos_corrida_tick('2020-06-01 13:30+00');
  assert (select estado from pg_temp.msgs('av_b@neu170.test') offset 1) = 'bloqueada', 'bloqueado: nasce bloqueada';
end $$;

-- ===== Pronto 5 (parte SQL): o ingest nao mudou, a corrida entra mesmo com o aviso quebrado =====
do $$
declare r jsonb;
begin
  r := public.ingest_race(jsonb_build_object(
    'race_id', '17060000-0000-0000-0000-000000000001', 'idempotency_key', '17060000-0000-0000-0000-000000000002',
    'player_email', 'av_novo@neu170.test', 'player_slot', 1, 'source', 'real',
    'started_at', 1591013400000, 'finished_at', 1591013440000));
  assert r ->> 'status' = 'created', 'ingest: corrida entra como sempre, veio ' || r::text;
end $$;

-- ===== O site nao chama nada disto =====
do $$
begin
  assert not has_function_privilege('authenticated', 'public.avisos_corrida_tick(timestamptz)', 'execute'),
    'authenticated nao roda o tick';
  assert not has_function_privilege('anon', 'public.avisos_corrida_tick(timestamptz)', 'execute'), 'anon nao roda o tick';
  assert not has_table_privilege('authenticated', 'public.avisos_corrida', 'select'), 'authenticated nao le avisos';
  assert not has_table_privilege('authenticated', 'public.avisos_corrida_config', 'update'), 'authenticated nao liga';
end $$;

rollback;
select 'avisos_corrida_test OK' as result;
