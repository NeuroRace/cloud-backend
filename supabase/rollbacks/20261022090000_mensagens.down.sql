-- Volta da NEU-112 (20261022090000_mensagens.sql). NAO fica em migrations/: so roda a mao.
-- Rodar inteiro numa transacao: psql -v ON_ERROR_STOP=1 -1 -f <este arquivo>
--
-- O site e o estande nao dependem de nada daqui: com ou sem esta peca, seguem como hoje.
--
-- Parte A (sempre segura): tira o agendamento e desliga o e-mail. Nada mais sai; as mensagens
-- pendentes expiram sozinhas. Funcoes, historico e a lista de "nao enviar" ficam guardados.
-- RELIGAR depois da Parte A: agendar de novo (comando no cabecalho da migration) e
--   update public.mensagens_config set email_ligado = true;
--
-- Parte B (APAGA a caixa de saida E A LISTA DE "NAO ENVIAR"): fica COMENTADA de proposito.
-- Sem a lista, quem pediu para parar de receber volta a receber se a peca for reinstalada.
-- Para apagar tudo, descomente a Parte B e rode de novo. Depois, em prod, apague tambem:
--   delete from supabase_migrations.schema_migrations where version = '20261022090000';
--   supabase functions delete send-messages && supabase functions delete message-actions
-- O pg_net fica: outras pecas podem usar.

-- ===== Parte A =====
do $$
begin
  -- SQL dinamico: sem pg_cron instalado, cron.job nem existe e nao pode ser planejado.
  if to_regclass('cron.job') is not null then
    execute $q$select cron.unschedule(jobid) from cron.job where jobname = 'mensagens-envio'$q$;
  end if;
end $$;
update public.mensagens_config set email_ligado = false;

-- ===== Parte B (comentada) =====
-- drop function public.mensagem_recusar_premio(uuid, timestamptz);
-- drop function public.mensagem_bloquear(uuid, text, timestamptz);
-- drop function public.mensagem_soltar(uuid, uuid, timestamptz);
-- drop function public.mensagem_resultado(uuid, uuid, boolean, text, text, boolean, timestamptz);
-- drop function public.mensagens_preparar(text, timestamptz, int);
-- drop function public.mensagens_destino_email(uuid, uuid);
-- drop function public.mensagem_enfileirar(text, text, text, text, timestamptz, text, text, text, uuid, uuid, uuid, uuid, timestamptz);
-- drop function public.mensagens_contato(text, text);
-- drop table public.mensagens_bloqueio;
-- drop table public.mensagens;
-- drop table public.mensagens_config;
