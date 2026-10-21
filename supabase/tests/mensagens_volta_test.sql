\set ON_ERROR_STOP on

-- NEU-112: a volta (Parte A) roda limpa, desliga o e-mail e nada mais sai.
-- A Parte B (comentada) e testada no bloco de baixo, com os mesmos comandos, dentro da transacao.

begin;

update public.mensagens_config set email_ligado = true, tipos_ligados = array['corrida_registrada'];
select public.mensagem_enfileirar('corrida_registrada', 'email', 'volta@neu112.test', 'volta1',
  '2020-06-01 13:00+00', 'A', 'T', p_agora => '2020-06-01 11:00+00');

\i supabase/rollbacks/20261022090000_mensagens.down.sql

do $$
declare n int;
begin
  assert not (select email_ligado from public.mensagens_config), 'volta: e-mail desligado';
  assert (select count(*) from public.mensagens_preparar('email', '2020-06-01 12:00+00')) = 0,
    'volta: depois da Parte A nada sai';
  assert (select estado from public.mensagens where chave = 'volta1') = 'pendente',
    'volta: a pendente fica guardada (e expira sozinha)';
  if to_regclass('cron.job') is not null then
    -- EXECUTE nao mexe no FOUND: conta pelo INTO.
    execute $q$select count(*) from cron.job where jobname = 'mensagens-envio'$q$ into n;
    assert n = 0, 'volta: sem agendamento';
  end if;
end $$;

-- Parte B, como esta no arquivo (descomentada aqui): apaga tudo sem erro.
drop function public.mensagem_recusar_premio(uuid, timestamptz);
drop function public.mensagem_bloquear(uuid, text, timestamptz);
drop function public.mensagem_resultado(uuid, boolean, text, text, boolean, timestamptz);
drop function public.mensagens_preparar(text, timestamptz, int);
drop function public.mensagens_destino_email(uuid, uuid);
drop function public.mensagem_enfileirar(text, text, text, text, timestamptz, text, text, text, uuid, uuid, uuid, uuid, timestamptz);
drop function public.mensagens_contato(text, text);
drop table public.mensagens_bloqueio;
drop table public.mensagens;
drop table public.mensagens_config;

do $$
begin
  assert to_regclass('public.mensagens') is null, 'volta B: tabela some';
  assert to_regprocedure('public.mensagens_preparar(text,timestamptz,int)') is null, 'volta B: funcao some';
  assert to_regclass('public.premios') is not null, 'volta B: a premiacao (NEU-167) fica';
end $$;

rollback;
select 'mensagens_volta_test OK' as result;
