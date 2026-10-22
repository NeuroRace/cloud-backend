-- Volta da NEU-170 (20261022100000_avisos_corrida.sql). NAO fica em migrations/: so roda a mao.
-- Rodar inteiro numa transacao: psql -v ON_ERROR_STOP=1 -1 -f <este arquivo>
--
-- A corrida continua entrando com ou sem esta peca (ela so le race_players).
--
-- Parte A (sempre segura): tira o agendamento e desliga o aviso. Nada novo e enfileirado;
-- o que ja esta na caixa de saida segue as regras da NEU-112 (expira sozinho).
-- RELIGAR: agendar de novo (cabecalho da migration) e
--   update public.avisos_corrida_config set corrida_ligada = true, corrida_ligada_em = now();
--
-- Parte B (apaga o historico de avisos): COMENTADA de proposito. Depois, em prod:
--   delete from supabase_migrations.schema_migrations where version = '20261022100000';

-- ===== Parte A =====
do $$
begin
  if to_regclass('cron.job') is not null then
    execute $q$select cron.unschedule(jobid) from cron.job where jobname = 'avisos-corrida'$q$;
  end if;
end $$;
update public.avisos_corrida_config set corrida_ligada = false;

-- ===== Parte B (comentada) =====
-- drop function public.avisos_corrida_tick(timestamptz);
-- drop function public.avisos_corrida_pessoa(text, timestamptz);
-- drop function public.mensagem_formata_tempo(numeric);
-- drop table public.avisos_corrida;
-- drop table public.avisos_corrida_config;
