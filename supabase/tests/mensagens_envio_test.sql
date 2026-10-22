\set ON_ERROR_STOP on

-- NEU-112 (parte 2): regras de envio (validade, interruptores, bloqueio, teto, novas tentativas),
-- "parar de receber" e "Nao vou poder". Tudo numa transacao com ROLLBACK no fim.
-- O horario entra sempre por parametro; nada usa now().
--
-- Seed: rodada 2020-06-01 10:00-11:00 com A 40 s, B 41 s, C 42 s. O tick da NEU-167 as 11:05
-- congela o premio de A. Mensagens em 2020-06-01 12:00, teto 10, reserva 3.

begin;

update public.premiacao_config set
  premiacao_ligada = true, ligada_em = '2020-01-01 00:00+00', evento_atual = 'TESTE',
  carencia_min = 5, janela_min = 15, limite_fila = 5, passar_sozinho = false, pausa_geral = false,
  piso_tempo_s = 15;

insert into auth.users (instance_id, id, aud, role, email, email_confirmed_at, created_at, updated_at) values
 ('00000000-0000-0000-0000-000000000000','11220000-0000-0000-0000-00000000000a','authenticated','authenticated','env_a@neu112.test','2020-01-01 00:00+00','2020-01-01 00:00+00','2020-01-01 00:00+00'),
 ('00000000-0000-0000-0000-000000000000','11220000-0000-0000-0000-00000000000b','authenticated','authenticated','env_b@neu112.test','2020-01-01 00:00+00','2020-01-01 00:00+00','2020-01-01 00:00+00'),
 ('00000000-0000-0000-0000-000000000000','11220000-0000-0000-0000-00000000000c','authenticated','authenticated','env_c@neu112.test','2020-01-01 00:00+00','2020-01-01 00:00+00','2020-01-01 00:00+00');
update public.profiles set display_name = 'E112A' where id = '11220000-0000-0000-0000-00000000000a';
update public.profiles set display_name = 'E112B' where id = '11220000-0000-0000-0000-00000000000b';
update public.profiles set display_name = 'E112C' where id = '11220000-0000-0000-0000-00000000000c';
insert into public.players (id, email, user_id) values
 ('11230000-0000-0000-0000-00000000000a','env_a@neu112.test','11220000-0000-0000-0000-00000000000a'),
 ('11230000-0000-0000-0000-00000000000b','env_b@neu112.test','11220000-0000-0000-0000-00000000000b'),
 ('11230000-0000-0000-0000-00000000000c','env_c@neu112.test','11220000-0000-0000-0000-00000000000c');
insert into public.ranking_windows (id, name, starts_at, ends_at) values
 ('11240000-0000-0000-0000-000000000001','E112 Rodada 1','2020-06-01 10:00+00','2020-06-01 11:00+00');

create function pg_temp.corrida(n int, jogador uuid, segundos numeric, terminou timestamptz)
returns void language sql as $$
  insert into public.races (id, started_at)
  values (('11250000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid, terminou - make_interval(secs => segundos));
  insert into public.race_players (id, idempotency_key, race_id, player_id, player_slot, source, started_at, finished_at, created_at)
  values (('11260000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
          ('11270000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
          ('11250000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
          jogador, 1, 'real', terminou - make_interval(secs => segundos), terminou, terminou);
$$;
select pg_temp.corrida(1,'11230000-0000-0000-0000-00000000000a',40,'2020-06-01 10:30+00');
select pg_temp.corrida(2,'11230000-0000-0000-0000-00000000000b',41,'2020-06-01 10:40+00');
select pg_temp.corrida(3,'11230000-0000-0000-0000-00000000000c',42,'2020-06-01 10:50+00');
select public.premiacao_tick('2020-06-01 11:05+00');

-- Premio valendo agora (da conta que tem a vez).
create function pg_temp.premio_valendo() returns uuid language sql as $$
  select id from public.premios
  where round_id = '11240000-0000-0000-0000-000000000001'
    and status in ('avisando','avisado','prazo_estourou','aviso_falhou');
$$;

-- msg: enfileira as 11:00 para o destino dado.
create function pg_temp.msg(chave text, tipo text, destino text, validade timestamptz, premio uuid default null)
returns uuid language sql as $$
  select public.mensagem_enfileirar(tipo, 'email', destino, chave, validade, 'Assunto', 'Texto',
    p_premio => premio, p_agora => '2020-06-01 11:00+00');
$$;

create function pg_temp.limpa() returns void language sql as $$
  delete from public.mensagens;
  delete from public.mensagens_bloqueio;
  update public.mensagens_config set email_ligado = true, teto_diario = 10, reserva_premio = 3, novas_tentativas = 3,
    tipos_ligados = array['premio_faltam_10','premio_venceu','premio_lembrete','premio_prazo_passou',
                          'corrida_registrada','corrida_convite'];
  update public.premiacao_config set pausa_geral = false;
$$;

create function pg_temp.estado(m uuid) returns text language sql as $$
  select estado from public.mensagens where id = m;
$$;

-- res: grava o resultado do envio atual (o envio_id que o preparar deu).
create function pg_temp.res(m uuid, ok boolean, provedor text, erro text, definitivo boolean, agora timestamptz)
returns text language sql as $$
  select public.mensagem_resultado(m, (select envio_id from public.mensagens where id = m), ok, provedor, erro, definitivo, agora);
$$;

-- ===== Pronto 1: mensagem vencida nunca sai =====
do $$
declare m uuid;
begin
  perform pg_temp.limpa();
  assert pg_temp.premio_valendo() is not null, 'seed: o tick congelou o premio de A';
  m := pg_temp.msg('venc', 'corrida_registrada', 'x1@neu112.test', '2020-06-01 11:59+00');
  assert (select count(*) from public.mensagens_preparar('email', '2020-06-01 12:00+00')) = 0,
    'Pronto 1: vencida nao e devolvida';
  assert pg_temp.estado(m) = 'expirada', 'Pronto 1: vencida vira expirada, veio ' || pg_temp.estado(m);
end $$;

-- ===== Pronto 3: canal desligado -> fica pendente e expira; pausa geral e tipo desligado tambem seguram =====
do $$
declare m uuid; t uuid;
begin
  perform pg_temp.limpa();
  update public.mensagens_config set email_ligado = false;
  m := pg_temp.msg('desl', 'corrida_registrada', 'x1@neu112.test', '2020-06-01 13:00+00');
  assert (select count(*) from public.mensagens_preparar('email', '2020-06-01 12:00+00')) = 0,
    'Pronto 3: canal desligado nao devolve';
  assert pg_temp.estado(m) = 'pendente', 'Pronto 3: canal desligado fica pendente';
  perform public.mensagens_preparar('email', '2020-06-01 13:00+00');
  assert pg_temp.estado(m) = 'expirada', 'Pronto 3: e expira quando passa da validade (canal religado nao manda pilha velha)';

  perform pg_temp.limpa();
  update public.premiacao_config set pausa_geral = true;
  m := pg_temp.msg('pausa', 'premio_faltam_10', 'x1@neu112.test', '2020-06-01 13:00+00');
  assert (select count(*) from public.mensagens_preparar('email', '2020-06-01 12:00+00')) = 0, 'pausa geral nao manda';
  assert pg_temp.estado(m) = 'pendente', 'pausa geral: fica pendente';

  perform pg_temp.limpa();
  update public.mensagens_config set tipos_ligados = array['premio_faltam_10'];
  m := pg_temp.msg('tipo1', 'corrida_registrada', 'x1@neu112.test', '2020-06-01 13:00+00');
  t := pg_temp.msg('tipo2', 'premio_faltam_10', 'x2@neu112.test', '2020-06-01 13:00+00');
  assert (select array_agg(id) from public.mensagens_preparar('email', '2020-06-01 12:00+00')) = array[t],
    'interruptor por tipo: so o tipo ligado sai';
  assert pg_temp.estado(m) = 'pendente', 'interruptor por tipo: o desligado fica pendente';
end $$;

-- ===== Pronto 4: contato na lista de "nao enviar" -> bloqueada =====
do $$
declare m uuid;
begin
  perform pg_temp.limpa();
  m := pg_temp.msg('bloq', 'corrida_registrada', 'x1@neu112.test', '2020-06-01 13:00+00');
  insert into public.mensagens_bloqueio values ('email', 'x1@neu112.test', 'teste', '2020-06-01 11:30+00');
  assert (select count(*) from public.mensagens_preparar('email', '2020-06-01 12:00+00')) = 0, 'Pronto 4: bloqueado nao sai';
  assert pg_temp.estado(m) = 'bloqueada', 'Pronto 4: vira bloqueada, veio ' || pg_temp.estado(m);
end $$;

-- ===== Pronto 5: teto quase cheio -> aviso de corrida bloqueado, aviso de premio enviado =====
do $$
declare c uuid; p uuid; i int;
begin
  perform pg_temp.limpa();
  for i in 1..7 loop
    perform pg_temp.msg('env' || i, 'corrida_registrada', 'y' || i || '@neu112.test', '2020-06-01 13:00+00');
  end loop;
  update public.mensagens set estado = 'enviada', enviada_em = '2020-06-01 11:30+00' where chave like 'env%';
  c := pg_temp.msg('teto_c', 'corrida_registrada', 'x1@neu112.test', '2020-06-01 13:00+00');
  p := pg_temp.msg('teto_p', 'premio_faltam_10', 'x2@neu112.test', '2020-06-01 13:00+00');
  assert (select array_agg(id) from public.mensagens_preparar('email', '2020-06-01 12:00+00')) = array[p],
    'Pronto 5: so o aviso de premio sai';
  assert pg_temp.estado(c) = 'bloqueada', 'Pronto 5: aviso de corrida bloqueado, veio ' || pg_temp.estado(c);
  assert (select erro from public.mensagens where id = c) = 'teto diario', 'Pronto 5: motivo e o teto';

  -- Teto cheio: nem o premio sai, mas ele fica pendente (a janela de 24 h anda e ele sai depois).
  perform pg_temp.limpa();
  for i in 1..10 loop
    perform pg_temp.msg('cheio' || i, 'corrida_registrada', 'y' || i || '@neu112.test', '2020-06-01 13:00+00');
  end loop;
  update public.mensagens set estado = 'enviada', enviada_em = '2020-06-01 11:30+00' where chave like 'cheio%';
  p := pg_temp.msg('cheio_p', 'premio_faltam_10', 'x2@neu112.test', '2020-06-01 13:00+00');
  assert (select count(*) from public.mensagens_preparar('email', '2020-06-01 12:00+00')) = 0, 'teto cheio: nada sai';
  assert pg_temp.estado(p) = 'pendente', 'teto cheio: o premio fica pendente';

  -- Enviada ha mais de 24 h nao conta no teto.
  perform pg_temp.limpa();
  for i in 1..7 loop
    perform pg_temp.msg('velha' || i, 'corrida_registrada', 'y' || i || '@neu112.test', '2020-06-01 13:00+00');
  end loop;
  update public.mensagens set estado = 'enviada', enviada_em = '2020-05-31 11:00+00' where chave like 'velha%';
  c := pg_temp.msg('velha_c', 'corrida_registrada', 'x1@neu112.test', '2020-06-01 13:00+00');
  assert (select array_agg(id) from public.mensagens_preparar('email', '2020-06-01 12:00+00')) = array[c],
    'teto: envio de 25 h atras nao conta';
end $$;

-- ===== Ordem: premio antes de corrida, e o limite do lote =====
do $$
declare c uuid; p uuid;
begin
  perform pg_temp.limpa();
  c := pg_temp.msg('ord_c', 'corrida_registrada', 'x1@neu112.test', '2020-06-01 13:00+00');
  p := pg_temp.msg('ord_p', 'premio_faltam_10', 'x2@neu112.test', '2020-06-01 13:00+00');
  assert (select array_agg(id) from public.mensagens_preparar('email', '2020-06-01 12:00+00', 1)) = array[p],
    'ordem: premio primeiro, e o lote respeita o limite';
  assert pg_temp.estado(c) = 'pendente', 'ordem: a corrida espera o proximo lote';
end $$;

-- ===== Review Focus 2: dois envios ao mesmo tempo nao pegam a mesma mensagem =====
do $$
declare m uuid;
begin
  perform pg_temp.limpa();
  m := pg_temp.msg('conc', 'corrida_registrada', 'x1@neu112.test', '2020-06-01 13:00+00');
  assert (select count(*) from public.mensagens_preparar('email', '2020-06-01 12:00+00')) = 1, 'concorrencia: o 1o pega';
  assert (select count(*) from public.mensagens_preparar('email', '2020-06-01 12:00+00')) = 0, 'concorrencia: o 2o nao pega';
  assert (select tentativas from public.mensagens where id = m) = 1, 'concorrencia: uma tentativa so';
  -- A trava vale 5 min (um lote lento de 20 x 10 s cabe nela); depois, a mensagem volta.
  assert (select count(*) from public.mensagens_preparar('email', '2020-06-01 12:04+00')) = 0, 'trava: 4 min ainda travada';
  assert (select count(*) from public.mensagens_preparar('email', '2020-06-01 12:05+00')) = 1, 'trava vencida: volta';
end $$;

-- ===== Pronto 6 (lado SQL): 3 novas tentativas com espera crescente, depois falhou =====
do $$
declare m uuid; e text;
begin
  perform pg_temp.limpa();
  m := pg_temp.msg('retry', 'corrida_registrada', 'x1@neu112.test', '2020-06-01 13:00+00');

  assert (select count(*) from public.mensagens_preparar('email', '2020-06-01 12:00+00')) = 1, 'tentativa 1';
  e := pg_temp.res(m, false, null, 'brevo 500', false, '2020-06-01 12:00+00');
  assert e = 'pendente', 'falha 1 -> pendente, veio ' || e;
  assert (select proxima_tentativa_em from public.mensagens where id = m) = '2020-06-01 12:01+00', 'espera 1 min';
  assert (select count(*) from public.mensagens_preparar('email', '2020-06-01 12:00:30+00')) = 0, 'antes da espera, nada';

  assert (select count(*) from public.mensagens_preparar('email', '2020-06-01 12:01+00')) = 1, 'tentativa 2';
  e := pg_temp.res(m, false, null, 'brevo 500', false, '2020-06-01 12:01+00');
  assert e = 'pendente' and (select proxima_tentativa_em from public.mensagens where id = m) = '2020-06-01 12:03+00',
    'falha 2 -> espera 2 min';

  assert (select count(*) from public.mensagens_preparar('email', '2020-06-01 12:03+00')) = 1, 'tentativa 3';
  e := pg_temp.res(m, false, null, 'brevo 500', false, '2020-06-01 12:03+00');
  assert e = 'pendente' and (select proxima_tentativa_em from public.mensagens where id = m) = '2020-06-01 12:07+00',
    'falha 3 -> espera 4 min';

  assert (select count(*) from public.mensagens_preparar('email', '2020-06-01 12:07+00')) = 1, 'tentativa 4';
  e := pg_temp.res(m, false, null, 'brevo 500', false, '2020-06-01 12:07+00');
  assert e = 'falhou', 'Pronto 6: depois de 3 novas tentativas, falhou; veio ' || e;
  assert (select erro from public.mensagens where id = m) = 'brevo 500', 'falhou: guarda o erro';
  assert (select count(*) from public.mensagens_preparar('email', '2020-06-01 12:30+00')) = 0, 'falhou nao volta';
end $$;

-- ===== Sucesso e falha definitiva =====
do $$
declare m uuid; d uuid; e text;
begin
  perform pg_temp.limpa();
  m := pg_temp.msg('ok', 'corrida_registrada', 'x1@neu112.test', '2020-06-01 13:00+00');
  d := pg_temp.msg('def', 'corrida_registrada', 'x2@neu112.test', '2020-06-01 13:00+00');
  perform public.mensagens_preparar('email', '2020-06-01 12:00+00');
  e := pg_temp.res(m, true, '<abc@brevo>', null, false, '2020-06-01 12:00:05+00');
  assert e = 'enviada', 'sucesso -> enviada';
  assert (select enviada_em = '2020-06-01 12:00:05+00' and provedor_id = '<abc@brevo>' and travada_ate is null
          from public.mensagens where id = m), 'sucesso: hora, id da Brevo e sem trava';
  e := pg_temp.res(d, false, null, 'brevo 400: email invalido', true, '2020-06-01 12:00:05+00');
  assert e = 'falhou', 'falha definitiva nao tenta de novo, veio ' || e;
end $$;

-- ===== Falha do aviso de premio vai para o registro da premiacao (o operador ve) =====
do $$
declare m uuid;
begin
  perform pg_temp.limpa();
  m := pg_temp.msg('pfalha', 'premio_venceu', 'env_a@neu112.test', '2020-06-01 13:00+00', pg_temp.premio_valendo());
  perform public.mensagens_preparar('email', '2020-06-01 12:00+00');
  perform pg_temp.res(m, false, null, 'brevo 400', true, '2020-06-01 12:00+00');
  assert exists (select 1 from public.premiacao_registro
                 where acao = 'erro' and premio_id = pg_temp.premio_valendo()
                   and detalhe like 'aviso por e-mail falhou%'),
    'falha do aviso de premio fica no registro';
end $$;

-- ===== Revisao final 2: o resultado so vale para o dono da trava; OK atrasado conta =====
do $$
declare m uuid; v uuid; e1 uuid; e2 uuid; e text;
begin
  perform pg_temp.limpa();
  m := pg_temp.msg('dono', 'corrida_registrada', 'x1@neu112.test', '2020-06-01 13:00+00');
  perform public.mensagens_preparar('email', '2020-06-01 12:00+00');
  e1 := (select envio_id from public.mensagens where id = m);
  assert e1 is not null, 'dono: o envio ganha um id';
  perform public.mensagens_preparar('email', '2020-06-01 12:05+00');
  e2 := (select envio_id from public.mensagens where id = m);
  assert e2 is not null and e2 <> e1, 'dono: novo envio, novo id';
  e := public.mensagem_resultado(m, e1, false, null, 'brevo 500', false, '2020-06-01 12:05:30+00');
  assert e = 'pendente', 'dono: falha do envio antigo, veio ' || e;
  assert (select travada_ate from public.mensagens where id = m) = '2020-06-01 12:10+00',
    'dono: falha do envio antigo nao solta a trava do envio atual';
  e := public.mensagem_resultado(m, e1, true, '<velho@brevo>', null, false, '2020-06-01 12:06+00');
  assert e = 'enviada', 'dono: OK atrasado do envio antigo conta (o e-mail saiu), veio ' || e;
  e := public.mensagem_resultado(m, e2, true, '<novo@brevo>', null, false, '2020-06-01 12:06:10+00');
  assert e = 'enviada' and (select provedor_id from public.mensagens where id = m) = '<velho@brevo>',
    'dono: o segundo OK nao muda nada';

  -- OK que chega depois de a mensagem expirar (trava vencida + validade): conta como enviada.
  perform pg_temp.limpa();
  v := pg_temp.msg('tarde', 'corrida_registrada', 'x2@neu112.test', '2020-06-01 12:03+00');
  perform public.mensagens_preparar('email', '2020-06-01 12:00+00');
  e1 := (select envio_id from public.mensagens where id = v);
  perform public.mensagens_preparar('email', '2020-06-01 12:06+00');
  assert pg_temp.estado(v) = 'expirada', 'tarde: expirou depois da trava vencer';
  e := public.mensagem_resultado(v, e1, true, '<tarde@brevo>', null, false, '2020-06-01 12:06:30+00');
  assert e = 'enviada', 'tarde: o OK atrasado vira enviada, veio ' || e;
end $$;

-- ===== Revisao final 1: soltar o que nao coube no prazo do lote =====
do $$
declare m uuid; e1 uuid;
begin
  perform pg_temp.limpa();
  m := pg_temp.msg('soltar', 'corrida_registrada', 'x1@neu112.test', '2020-06-01 13:00+00');
  perform public.mensagens_preparar('email', '2020-06-01 12:00+00');
  e1 := (select envio_id from public.mensagens where id = m);
  assert public.mensagem_soltar(m, e1, '2020-06-01 12:00:50+00'), 'soltar: true para o dono';
  assert (select tentativas = 0 and travada_ate is null and envio_id is null from public.mensagens where id = m),
    'soltar: nao conta tentativa e tira a trava';
  assert (select count(*) from public.mensagens_preparar('email', '2020-06-01 12:01+00')) = 1, 'soltar: volta no proximo lote';
  assert not public.mensagem_soltar(m, e1, '2020-06-01 12:01:10+00'), 'soltar: envio antigo nao solta o novo';
end $$;

-- ===== Revisao final 3: aviso de premio com prazo estourado ou sem premio nao sai =====
do $$
declare m uuid; n uuid; a uuid := pg_temp.premio_valendo();
begin
  perform pg_temp.limpa();
  m := pg_temp.msg('estourou', 'premio_lembrete', 'env_a@neu112.test', '2020-06-01 13:00+00', a);
  n := pg_temp.msg('semprem', 'premio_venceu', 'z@neu112.test', '2020-06-01 13:00+00', null);
  update public.premios set status = 'prazo_estourou' where id = a;
  assert (select count(*) from public.mensagens_preparar('email', '2020-06-01 12:00+00')) = 0,
    'prazo estourado e premio apagado: nada sai';
  assert pg_temp.estado(m) = 'cancelada', 'prazo estourado: lembrete cancelado, veio ' || pg_temp.estado(m);
  assert pg_temp.estado(n) = 'cancelada', 'sem premio (conta apagada): venceu cancelado, veio ' || pg_temp.estado(n);
  update public.premios set status = 'avisado' where id = a;
end $$;

-- ===== "Parar de receber": bloqueia o contato e as pendentes dele =====
do $$
declare m1 uuid; m2 uuid; m3 uuid;
begin
  perform pg_temp.limpa();
  m1 := pg_temp.msg('b1', 'corrida_registrada', 'x1@neu112.test', '2020-06-01 13:00+00');
  m2 := pg_temp.msg('b2', 'premio_faltam_10', 'x1@neu112.test', '2020-06-01 13:00+00');
  m3 := pg_temp.msg('b3', 'corrida_registrada', 'x2@neu112.test', '2020-06-01 13:00+00');
  assert public.mensagem_bloquear(m1, 'link do e-mail', '2020-06-01 12:00+00'), 'bloquear: true';
  assert exists (select 1 from public.mensagens_bloqueio where canal = 'email' and contato = 'x1@neu112.test'),
    'bloquear: contato na lista';
  assert pg_temp.estado(m1) = 'bloqueada' and pg_temp.estado(m2) = 'bloqueada', 'bloquear: pendentes do contato, todos os tipos';
  assert pg_temp.estado(m3) = 'pendente', 'bloquear: outro contato segue';
  assert public.mensagem_bloquear(m1, 'link do e-mail', '2020-06-01 12:01+00'), 'bloquear de novo: ok, sem erro';
  assert not public.mensagem_bloquear('00000000-0000-0000-0000-000000000000', 'x', '2020-06-01 12:00+00'),
    'bloquear: mensagem inexistente -> false';
end $$;

-- ===== Review Focus 3: aviso de premio que nao vale mais e cancelado =====
do $$
declare m uuid; a uuid := pg_temp.premio_valendo();
begin
  perform pg_temp.limpa();
  m := pg_temp.msg('velho', 'premio_venceu', 'env_a@neu112.test', '2020-06-01 13:00+00', a);
  perform public.premio_passar(a, 'passou', '2020-06-01 11:30+00', 'teste', 'prazo');
  assert (select count(*) from public.mensagens_preparar('email', '2020-06-01 12:00+00')) = 0,
    'aviso de premio que passou nao sai';
  assert pg_temp.estado(m) = 'cancelada', 'Review Focus 3: vira cancelada, veio ' || pg_temp.estado(m);
end $$;

-- ===== "Nao vou poder" (Review Focus 4: o segundo clique nao passa de novo) =====
do $$
declare m uuid; c uuid; b uuid := pg_temp.premio_valendo(); r text;
begin
  perform pg_temp.limpa();
  assert (select user_id from public.premios where id = b) = '11220000-0000-0000-0000-00000000000b',
    'seed: depois de A passar, B tem a vez';
  m := pg_temp.msg('nvp', 'premio_venceu', 'env_b@neu112.test', '2020-06-01 13:00+00', b);
  r := public.mensagem_recusar_premio(m, '2020-06-01 12:00+00');
  assert r = 'recusado', 'Nao vou poder: recusado, veio ' || r;
  assert (select status from public.premios where id = b) = 'recusado', 'o premio de B fica recusado';
  assert (select user_id from public.premios where id = pg_temp.premio_valendo()) = '11220000-0000-0000-0000-00000000000c',
    'o premio passa para C';
  r := public.mensagem_recusar_premio(m, '2020-06-01 12:01+00');
  assert r = 'ja_resolvido', 'segundo clique: ja_resolvido, veio ' || r;
  assert (select count(*) from public.premios where round_id = '11240000-0000-0000-0000-000000000001') = 3,
    'segundo clique nao passa de novo';

  c := pg_temp.msg('nvp_c', 'corrida_registrada', 'env_b@neu112.test', '2020-06-01 13:00+00');
  assert public.mensagem_recusar_premio(c, '2020-06-01 12:00+00') = 'invalido', 'aviso de corrida: invalido';
  assert public.mensagem_recusar_premio('00000000-0000-0000-0000-000000000000', '2020-06-01 12:00+00') = 'invalido',
    'mensagem inexistente: invalido';
end $$;

-- ===== O site nao chama nada disto =====
do $$
begin
  assert not has_function_privilege('authenticated', 'public.mensagens_preparar(text,timestamptz,int)', 'execute'),
    'authenticated nao prepara envio';
  assert not has_function_privilege('anon', 'public.mensagem_bloquear(uuid,text,timestamptz)', 'execute'),
    'anon nao bloqueia direto';
  assert not has_function_privilege('anon', 'public.mensagem_recusar_premio(uuid,timestamptz)', 'execute'),
    'anon nao recusa direto';
  assert has_function_privilege('service_role',
    'pg_temp.res(uuid,boolean,text,text,boolean,timestamptz)', 'execute'), 'service_role grava resultado';
end $$;

rollback;
select 'mensagens_envio_test OK' as result;
