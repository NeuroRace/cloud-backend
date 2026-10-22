\set ON_ERROR_STOP on

-- Volta do "voce venceu": tira a funcao sem levar a caixa de saida (NEU-112) nem a premiacao.
begin;
\i supabase/rollbacks/20261022093000_aviso_vencedor.down.sql
do $$
begin
  assert to_regprocedure('public.avisos_premio_tick(timestamptz)') is null, 'volta: a funcao some';
  assert to_regclass('public.mensagens') is not null and to_regclass('public.premios') is not null,
    'volta: caixa de saida e premiacao ficam';
end $$;
rollback;
select 'aviso_vencedor_volta_test OK' as result;
