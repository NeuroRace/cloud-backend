-- Volta do complemento "voce venceu" da NEU-112 (20261022093000_aviso_vencedor.sql). So roda a mao:
-- psql -v ON_ERROR_STOP=1 -1 -f <este arquivo>
-- Tira o agendamento e a funcao. Os avisos ja enfileirados seguem as regras da caixa de saida.
-- Depois, em prod: delete from supabase_migrations.schema_migrations where version = '20261022093000';
do $$
begin
  if to_regclass('cron.job') is not null then
    execute $q$select cron.unschedule(jobid) from cron.job where jobname = 'avisos-premio'$q$;
  end if;
end $$;
drop function public.avisos_premio_tick(timestamptz);
