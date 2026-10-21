\set ON_ERROR_STOP on

-- NEU-112 (parte 1): caixa de saida, enfileirar, destino e lista de "nao enviar".
-- Tudo numa transacao com ROLLBACK no fim. O horario entra sempre por parametro.

begin;

insert into auth.users (instance_id, id, aud, role, email, email_confirmed_at, created_at, updated_at) values
 ('00000000-0000-0000-0000-000000000000','11200000-0000-0000-0000-00000000000a','authenticated','authenticated','msg_a@neu112.test','2020-01-01 00:00+00','2020-01-01 00:00+00','2020-01-01 00:00+00'),
 ('00000000-0000-0000-0000-000000000000','11200000-0000-0000-0000-00000000000b','authenticated','authenticated','msg_b@neu112.test', null,'2020-01-01 00:00+00','2020-01-01 00:00+00');
insert into public.players (id, email, user_id) values
 ('11210000-0000-0000-0000-000000000099','msg_semconta@neu112.test', null);

-- Pronto 2: a mesma chave entra duas vezes -> um registro so.
do $$
declare v1 uuid; v2 uuid;
begin
  v1 := public.mensagem_enfileirar('corrida_registrada','email','msg_a@neu112.test','k1',
          '2020-06-01 13:00+00','Assunto','Texto', p_agora => '2020-06-01 12:00+00');
  v2 := public.mensagem_enfileirar('corrida_registrada','email','msg_a@neu112.test','k1',
          '2020-06-01 13:00+00','Assunto','Texto', p_agora => '2020-06-01 12:00+00');
  assert v1 is not null, 'enfileirar: a primeira vez devolve o id';
  assert v2 is null, 'enfileirar: a mesma chave de novo devolve null';
  assert (select count(*) from public.mensagens where chave = 'k1') = 1, 'Pronto 2: um registro so por chave';
  assert (select estado from public.mensagens where id = v1) = 'pendente', 'enfileirar: nasce pendente';
  assert (select categoria from public.mensagens where id = v1) = 'corrida', 'categoria: corrida_* e corrida';
end $$;

-- O destino e normalizado (lower/trim), como players.email.
do $$
declare v uuid;
begin
  v := public.mensagem_enfileirar('premio_venceu','email','  Msg_A@NEU112.test ','k2',
         '2020-06-01 13:00+00','Assunto','Texto', p_agora => '2020-06-01 12:00+00');
  assert (select destino from public.mensagens where id = v) = 'msg_a@neu112.test', 'destino normalizado';
  assert (select categoria from public.mensagens where id = v) = 'premio', 'categoria: premio_* e premio';
end $$;

-- Review Focus 5 + Pronto 4: contato bloqueado (com maiuscula e espaco) -> ja nasce bloqueada.
do $$
declare v uuid;
begin
  insert into public.mensagens_bloqueio (canal, contato, origem, criado_em)
  values ('email', public.mensagens_contato('email', ' Msg_SemConta@NEU112.test '), 'teste', '2020-06-01 11:00+00');
  v := public.mensagem_enfileirar('corrida_convite','email','msg_semconta@neu112.test','k3',
         '2020-06-01 13:00+00','Assunto','Texto', p_agora => '2020-06-01 12:00+00');
  assert (select estado from public.mensagens where id = v) = 'bloqueada', 'bloqueado: nasce bloqueada';
  assert public.mensagens_contato('whatsapp', '+55 (11) 91234-5670') = '5511912345670', 'whatsapp: so digitos';
end $$;

-- Para quem mandar: conta -> e-mail confirmado; sem conta -> e-mail do estande.
do $$
begin
  assert public.mensagens_destino_email('11200000-0000-0000-0000-00000000000a', null) = 'msg_a@neu112.test',
    'destino: conta com e-mail confirmado';
  assert public.mensagens_destino_email('11200000-0000-0000-0000-00000000000b', null) is null,
    'destino: conta sem e-mail confirmado nao recebe';
  assert public.mensagens_destino_email(null, '11210000-0000-0000-0000-000000000099') = 'msg_semconta@neu112.test',
    'destino: sem conta, o e-mail digitado no estande';
  assert public.mensagens_destino_email(null, null) is null, 'destino: nada -> null';
end $$;

-- Validacoes: tipo e canal fora da lista nao entram.
do $$
begin
  begin
    perform public.mensagem_enfileirar('outro','email','x@neu112.test','k4','2020-06-01 13:00+00','A','T',
      p_agora => '2020-06-01 12:00+00');
    assert false, 'tipo desconhecido deveria falhar';
  exception when check_violation then null;
  end;
end $$;

-- Tudo nasce desligado.
do $$
begin
  assert (select not email_ligado and tipos_ligados = '{}' from public.mensagens_config), 'config: nasce desligada';
  assert (select teto_diario = 300 and reserva_premio = 50 and novas_tentativas = 3 from public.mensagens_config),
    'config: padroes 300 / 50 / 3';
end $$;

-- O site nao le nem chama nada disto.
do $$
begin
  assert not has_table_privilege('anon', 'public.mensagens', 'select'), 'anon nao le mensagens';
  assert not has_table_privilege('authenticated', 'public.mensagens', 'select'), 'authenticated nao le mensagens';
  assert not has_table_privilege('authenticated', 'public.mensagens_bloqueio', 'select'), 'authenticated nao le bloqueio';
  assert not has_table_privilege('authenticated', 'public.mensagens_config', 'update'), 'authenticated nao muda config';
  assert not has_function_privilege('authenticated',
    'public.mensagem_enfileirar(text,text,text,text,timestamptz,text,text,text,uuid,uuid,uuid,uuid,timestamptz)', 'execute'),
    'authenticated nao enfileira';
  assert not has_function_privilege('anon', 'public.mensagens_destino_email(uuid,uuid)', 'execute'),
    'anon nao descobre e-mail';
  assert has_function_privilege('service_role',
    'public.mensagem_enfileirar(text,text,text,text,timestamptz,text,text,text,uuid,uuid,uuid,uuid,timestamptz)', 'execute'),
    'service_role enfileira';
end $$;

rollback;
select 'mensagens_base_test OK' as result;
