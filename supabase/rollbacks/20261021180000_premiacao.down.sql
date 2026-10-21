-- Volta da NEU-167 (20261021180000_premiacao.sql). NAO fica em migrations/: so roda a mao.
-- Rodar inteiro numa transacao: psql -v ON_ERROR_STOP=1 -1 -f <este arquivo>
--
-- Antes de tudo, o jeito mais leve de parar (sem este arquivo):
--   update public.premiacao_config set premiacao_ligada = false;   -- para de fechar rodadas
--   select cron.unschedule('premiacao-tick');                       -- tira o agendamento
--
-- Parte A (sempre segura): tira o agendamento e as funcoes. O site volta a ser o de hoje:
-- get_my_prize e get_official_winners somem (PGRST202), o cartao do premio nao aparece e o
-- letreiro do telao volta ao 1o ao vivo. As tabelas e os premios ficam guardados.
--
-- Parte B (apaga os premios): so se ninguem precisar mais deles. Comente se for so a Parte A.
-- Depois de rodar a Parte B em prod, apague tambem a linha da migration:
--   delete from supabase_migrations.schema_migrations where version = '20261021180000';

-- ===== Parte A =====
do $$
begin
  -- SQL dinamico: sem pg_cron instalado, cron.job nem existe e nao pode ser planejado.
  if to_regclass('cron.job') is not null then
    execute $q$select cron.unschedule(jobid) from cron.job where jobname = 'premiacao-tick'$q$;
  end if;
end $$;

drop function if exists public.get_official_winners();
drop function if exists public.get_my_prize();
drop function if exists public.premiacao_tick(timestamptz);
drop function if exists public.premiacao_registra_erro(timestamptz, uuid, uuid, text);
drop function if exists public.premio_passar(uuid, text, timestamptz, text, text);
drop function if exists public.premio_dar_vez(uuid, timestamptz);
drop function if exists public.premio_novo_codigo();
drop function if exists public.premiacao_candidatos(uuid, timestamptz);

-- ===== Parte B =====
drop table if exists public.premiacao_registro;
drop table if exists public.premios;
drop table if exists public.premiacao_rodadas;
drop table if exists public.premiacao_config;
