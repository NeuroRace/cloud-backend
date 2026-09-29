\set ON_ERROR_STOP on

-- NEU-30: inscrições do bot do Telegram (chat ↔ e-mail do estande) e avisos já enviados.
-- Prova: chat_id cabe em bigint; e-mail tem de vir normalizado (lower/trim, como o ingest);
-- o mesmo chat troca de e-mail por upsert; aviso não duplica (chave chat+tipo+referência);
-- apagar a inscrição (/parar) apaga os avisos; anon/authenticated não leem nem escrevem nada.
-- Limpa o próprio seed.

delete from public.telegram_subscriptions where chat_id in (7000000001, 7000000002);

-- chat_id do Telegram passa do limite de int4 (2^31): precisa ser bigint
insert into public.telegram_subscriptions (chat_id, email) values (7000000001, 'ana@neu30.test');

do $$
declare ok boolean;
begin
  -- mesmo chat manda outro e-mail: upsert troca, não duplica
  insert into public.telegram_subscriptions (chat_id, email) values (7000000001, 'ana.nova@neu30.test')
  on conflict (chat_id) do update set email = excluded.email, updated_at = now();
  assert (select count(*) from public.telegram_subscriptions where chat_id = 7000000001) = 1,
    'um chat tem uma inscrição só';
  assert (select email from public.telegram_subscriptions where chat_id = 7000000001) = 'ana.nova@neu30.test',
    'upsert troca o e-mail do chat';

  -- e-mail fora do padrão do ingest (maiúscula / espaço / sem @) é recusado
  ok := false;
  begin insert into public.telegram_subscriptions (chat_id, email) values (7000000002, 'Bia@NEU30.test');
  exception when check_violation then ok := true; end;
  assert ok, 'e-mail com maiúscula deve ser recusado (o bot normaliza com lower/trim antes)';

  ok := false;
  begin insert into public.telegram_subscriptions (chat_id, email) values (7000000002, ' bia@neu30.test');
  exception when check_violation then ok := true; end;
  assert ok, 'e-mail com espaço deve ser recusado';

  ok := false;
  begin insert into public.telegram_subscriptions (chat_id, email) values (7000000002, 'sem-arroba');
  exception when check_violation then ok := true; end;
  assert ok, 'texto sem @ deve ser recusado';

  -- avisos: o mesmo aviso não é gravado duas vezes (o bot grava ANTES de enviar)
  insert into public.telegram_notifications (chat_id, kind, ref)
  values (7000000001, 'race_registered', 'aa000000-0000-0000-0000-00000000030a');
  insert into public.telegram_notifications (chat_id, kind, ref)
  values (7000000001, 'race_registered', 'aa000000-0000-0000-0000-00000000030a')
  on conflict do nothing;
  assert (select count(*) from public.telegram_notifications where chat_id = 7000000001) = 1,
    'aviso repetido não duplica';

  -- tipo de aviso fora da lista é recusado
  ok := false;
  begin insert into public.telegram_notifications (chat_id, kind, ref)
        values (7000000001, 'resultado_completo', 'aa000000-0000-0000-0000-00000000030b');
  exception when check_violation then ok := true; end;
  assert ok, 'só os avisos previstos (sem dados da corrida) podem ser registrados';

  -- /parar: apagar a inscrição apaga os avisos daquele chat
  delete from public.telegram_subscriptions where chat_id = 7000000001;
  assert (select count(*) from public.telegram_notifications where chat_id = 7000000001) = 0,
    'apagar a inscrição apaga os avisos (cascade)';
end $$;

-- o site (anon/authenticated) não enxerga nem escreve nada: só o bot, com service_role
insert into public.telegram_subscriptions (chat_id, email) values (7000000002, 'bia@neu30.test');

begin;
set local role anon;
do $$
declare ok boolean;
begin
  ok := false;
  begin perform 1 from public.telegram_subscriptions;
  exception when insufficient_privilege then ok := true; end;
  assert ok, 'anon NÃO pode ler inscrições (e-mail + chat do Telegram)';

  ok := false;
  begin insert into public.telegram_subscriptions (chat_id, email) values (7000000003, 'x@neu30.test');
  exception when insufficient_privilege then ok := true; end;
  assert ok, 'anon NÃO pode se inscrever pelo site';

  ok := false;
  begin perform 1 from public.telegram_notifications;
  exception when insufficient_privilege then ok := true; end;
  assert ok, 'anon NÃO pode ler avisos';
end $$;
commit;

begin;
set local role authenticated;
do $$
declare ok boolean;
begin
  ok := false;
  begin perform 1 from public.telegram_subscriptions;
  exception when insufficient_privilege then ok := true; end;
  assert ok, 'authenticated NÃO pode ler inscrições';

  ok := false;
  begin truncate public.telegram_subscriptions;
  exception when insufficient_privilege then ok := true; end;
  assert ok, 'authenticated NÃO pode truncar (TRUNCATE ignora RLS)';
end $$;
commit;

-- service_role (o bot) lê e escreve
begin;
set local role service_role;
do $$
begin
  assert (select count(*) from public.telegram_subscriptions where chat_id = 7000000002) = 1,
    'service_role lê as inscrições';
  insert into public.telegram_notifications (chat_id, kind, ref)
  values (7000000002, 'round_winner', 'bb000000-0000-0000-0000-00000000030a');
  assert (select count(*) from public.telegram_notifications where chat_id = 7000000002) = 1,
    'service_role grava avisos';
end $$;
commit;

delete from public.telegram_subscriptions where chat_id in (7000000001, 7000000002);
select 'telegram_subscriptions_test OK' as result;
