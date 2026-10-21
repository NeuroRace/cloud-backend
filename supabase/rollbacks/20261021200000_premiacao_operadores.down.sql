-- Volta da NEU-168 (20261021200000_premiacao_operadores.sql). NAO fica em migrations/: so roda a mao.
-- Rodar inteiro numa transacao: psql -v ON_ERROR_STOP=1 -1 -f <este arquivo>
--
-- Jeito mais leve de tirar o acesso (sem este arquivo): esvaziar a lista.
--   delete from public.operadores;   -- ninguem mais age; a automacao (NEU-167) segue como estiver
--
-- Parte A (padrao): tira as funcoes op_* e as internas da NEU-168 e devolve o premio_dar_vez da
-- NEU-167 (gerado da migration dela). O painel /operador mostra "a premiacao ainda nao esta no
-- ar" (PGRST202); a automacao, get_my_prize e get_official_winners seguem.
-- Parte B (comentada de proposito): apaga a lista de operadores.
--
-- RELIGAR depois da Parte A: psql -v ON_ERROR_STOP=1 -1 -f supabase/rollbacks/20261021200000_premiacao_operadores.reapply.sql
-- (se a NEU-167 tambem foi desligada: reapply da 167 primeiro, depois este).
--
-- O premio_dar_vez abaixo e gerado, nao editar a mao:
--   awk '/^create function public.premio_dar_vez\(/{f=1} f{print} f&&/^\$\$;/{exit}' supabase/migrations/20261021180000_premiacao.sql

-- ===== Parte A =====
drop function if exists public.op_config(jsonb);
drop function if exists public.op_acao(uuid, text, text);
drop function if exists public.op_validar_codigo(text);
drop function if exists public.op_painel();
drop function if exists public.premiacao_op_config(text, jsonb, timestamptz);
drop function if exists public.premiacao_op_acao(text, uuid, text, text, timestamptz);
drop function if exists public.premiacao_op_validar(text, text, timestamptz);
drop function if exists public.premiacao_op_painel(timestamptz);
drop function if exists public.premiacao_mascara_contato(text, text);
drop function if exists public.premiacao_operador_atual();

-- premio_dar_vez volta a ser a da NEU-167 (antes de tirar a premio_dar_vez_ate, de que ela depende agora)
create or replace function public.premio_dar_vez(p_round uuid, p_agora timestamptz)
returns uuid
language plpgsql
set search_path = public
as $$
declare
  cfg  premiacao_config;
  rod  premiacao_rodadas;
  c    record;
  v_id uuid;
  v_vez int;
begin
  -- Mesma trava do tick e das acoes do operador: duas entradas nunca escolhem a mesma conta.
  perform pg_advisory_xact_lock(hashtext('neurorace_premiacao'));
  select * into cfg from premiacao_config;
  select * into rod from premiacao_rodadas where round_id = p_round;

  select count(*) + 1 into v_vez from premios where round_id = p_round;
  if v_vez > cfg.limite_fila then
    return null;
  end if;

  select k.* into c
  from premiacao_candidatos(p_round, rod.corte_em) k
  where not exists (select 1 from premios x where x.round_id = p_round and x.user_id = k.user_id)
    and not exists (select 1 from premios x
                    where x.evento = rod.evento and x.user_id = k.user_id
                      and x.status in ('avisando', 'avisado', 'prazo_estourou', 'aviso_falhou', 'entregue'))
  order by k.posicao
  limit 1;

  if c.user_id is null then
    return null;
  end if;

  insert into premios (round_id, evento, user_id, posicao, display_name, score, race_player_id,
                       status, code, prazo, criado_em, atualizado_em)
  values (p_round, rod.evento, c.user_id, v_vez, c.display_name, c.score, c.race_player_id,
          'avisado', premio_novo_codigo(), p_agora + make_interval(mins => cfg.janela_min), p_agora, p_agora)
  returning id into v_id;

  insert into premiacao_registro (em, operador, acao, round_id, premio_id, detalhe)
  values (p_agora, 'automacao', 'deu_a_vez', p_round, v_id,
          format('%s (%sº no ranking, %sª vez) ficou com o premio', c.display_name, c.posicao, v_vez));
  return v_id;
end;
$$;
drop function if exists public.premio_dar_vez_ate(uuid, timestamptz, int, boolean);

-- ===== Parte B (comentada) =====
-- drop table if exists public.operadores;
