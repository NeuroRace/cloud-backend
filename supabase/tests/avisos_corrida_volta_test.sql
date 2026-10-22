\set ON_ERROR_STOP on

-- NEU-170: a volta (Parte A) desliga o aviso; a Parte B (comentada no arquivo) apaga sem erro
-- e sem levar a caixa de saida da NEU-112 junto.

begin;

update public.avisos_corrida_config set corrida_ligada = true, corrida_ligada_em = '2020-06-01 10:00+00';

\i supabase/rollbacks/20261022100000_avisos_corrida.down.sql

do $$
declare r jsonb; n int;
begin
  assert not (select corrida_ligada from public.avisos_corrida_config), 'volta: aviso desligado';
  r := public.avisos_corrida_tick('2020-06-01 12:00+00');
  assert (r ->> 'rodou')::boolean = false, 'volta: o tick nao roda mais';
  if to_regclass('cron.job') is not null then
    execute $q$select count(*) from cron.job where jobname = 'avisos-corrida'$q$ into n;
    assert n = 0, 'volta: sem agendamento';
  end if;
end $$;

drop function public.avisos_corrida_tick(timestamptz);
drop function public.avisos_corrida_pessoa(text, timestamptz);
drop function public.mensagem_formata_tempo(numeric);
drop table public.avisos_corrida;
drop table public.avisos_corrida_config;

do $$
begin
  assert to_regclass('public.avisos_corrida') is null, 'volta B: tabela some';
  assert to_regclass('public.mensagens') is not null, 'volta B: a caixa de saida (NEU-112) fica';
end $$;

rollback;
select 'avisos_corrida_volta_test OK' as result;
