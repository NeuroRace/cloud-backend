-- RELIGAR a NEU-167 depois da volta padrao (20261021180000_premiacao.down.sql, Parte A).
-- A volta padrao tira o job e as funcoes e guarda as tabelas e os premios. Reaplicar a
-- migration inteira falha ("premiacao_config already exists") e o db push nao age (a migration
-- consta aplicada). Este arquivo recria so as funcoes (secao (5) em diante da migration, copia
-- fiel, com os mesmos revoke/grant) e agenda o tick de novo. Premios e regras ficam como estavam.
--
-- Rodar numa transacao: psql -v ON_ERROR_STOP=1 -1 -f <este arquivo>
-- Se alguma funcao ainda existir (a volta nao foi rodada), falha de proposito e nada muda.
-- Com a NEU-168 aplicada: rodar este e DEPOIS o reapply da NEU-168 (ela recria premio_dar_vez).
--
-- Gerado da migration, nao editar a mao:
--   sed -n '/^-- (5) Candidatos/,$p' supabase/migrations/20261021180000_premiacao.sql

-- (5) Candidatos de uma rodada, na ordem do get_leaderboard: por conta, a menor duracao e,
-- empatando, quem terminou primeiro. So conta com apelido, so source='real', so corrida
-- que chegou ate o corte e que dura pelo menos o piso de tempo.
create function public.premiacao_candidatos(p_round uuid, p_corte timestamptz)
returns table (user_id uuid, display_name text, score numeric, achieved_at timestamptz, race_player_id uuid, posicao int)
language sql
stable
set search_path = public
as $$
  select b.user_id, b.display_name, b.score, b.achieved_at, b.race_player_id,
         (row_number() over (order by b.score asc, b.achieved_at asc, b.display_name asc))::int
  from (
    select distinct on (pr.id)
           pr.id as user_id,
           pr.display_name::text as display_name,
           extract(epoch from (rp.finished_at - rp.started_at))::numeric as score,
           rp.finished_at as achieved_at,
           rp.id as race_player_id
    from ranking_windows w
    join race_players rp on rp.finished_at >= w.starts_at and rp.finished_at < w.ends_at
    join players p       on p.id = rp.player_id
    join profiles pr     on pr.id = p.user_id
    where w.id = p_round
      and pr.display_name is not null
      and rp.source = 'real'
      and rp.finished_at > rp.started_at
      and extract(epoch from (rp.finished_at - rp.started_at)) >= (select c.piso_tempo_s from premiacao_config c)
      and rp.created_at <= p_corte
    order by pr.id, (rp.finished_at - rp.started_at) asc, rp.finished_at asc
  ) b
  order by 6;
$$;

-- (6) Codigo de 6 digitos, aleatorio (pgcrypto), unico entre os que valem.
create function public.premio_novo_codigo()
returns text
language plpgsql
volatile
set search_path = public
as $$
declare
  v_code text;
begin
  loop
    v_code := lpad(((('x' || encode(extensions.gen_random_bytes(4), 'hex'))::bit(32)::bigint % 1000000))::text, 6, '0');
    exit when not exists (
      select 1 from premios
      where code = v_code and status in ('avisando', 'avisado', 'prazo_estourou', 'aviso_falhou'));
  end loop;
  return v_code;
end;
$$;

-- (7) Da a vez ao proximo elegivel da rodada, na ordem do ranking. limite_fila conta as VEZES
-- dadas na rodada (ate o 5o elegivel), nao a colocacao: quem ja ganhou e pulado sem gastar vez.
-- Elegivel: conta sem premio
-- valendo no evento (D2) e que ainda nao teve a vez nesta rodada; recusado/passou em outra
-- rodada volta a valer (D4). Sem canal de aviso (D3), nasce avisado e a janela comeca agora.
-- Devolve o id do premio novo, ou null se a fila acabou.
create function public.premio_dar_vez(p_round uuid, p_agora timestamptz)
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

-- (8) Tira o premio de quem tem e passa ao proximo. p_novo_status: 'passou' (prazo) ou
-- 'recusado' (a pessoa abriu mao). Fila acabou -> o turno vira 'sem_retirada'.
-- Usada pela automacao (passar_sozinho) e pelas acoes do operador (NEU-168).
create function public.premio_passar(p_premio uuid, p_novo_status text, p_agora timestamptz,
                                     p_operador text, p_motivo text default null)
returns uuid
language plpgsql
set search_path = public
as $$
declare
  v_old  premios;
  v_next uuid;
begin
  if p_novo_status not in ('passou', 'recusado') then
    raise exception 'premio_passar: estado % nao vale aqui', p_novo_status;
  end if;

  perform pg_advisory_xact_lock(hashtext('neurorace_premiacao'));
  select * into v_old from premios where id = p_premio for update;
  if v_old.id is null or v_old.status not in ('avisando', 'avisado', 'prazo_estourou', 'aviso_falhou') then
    return null;
  end if;

  update premios set status = p_novo_status, motivo = coalesce(p_motivo, motivo), atualizado_em = p_agora
   where id = p_premio;
  v_next := premio_dar_vez(v_old.round_id, p_agora);
  if v_next is null then
    update premios set status = 'sem_retirada', atualizado_em = p_agora where id = p_premio;
  end if;

  insert into premiacao_registro (em, operador, acao, round_id, premio_id, detalhe, antes, depois)
  values (p_agora, p_operador, case when v_next is null then 'sem_retirada' else p_novo_status end,
          v_old.round_id, p_premio, p_motivo,
          jsonb_build_object('status', v_old.status),
          jsonb_build_object('status', case when v_next is null then 'sem_retirada' else p_novo_status end,
                             'proximo', v_next));
  return v_next;
end;
$$;

-- Erro da automacao no registro, uma vez so por (rodada, premio, mensagem): o tick tenta de
-- novo a cada minuto, mas o mesmo erro nao enche o registro (o painel mostra as ultimas acoes).
create function public.premiacao_registra_erro(p_agora timestamptz, p_round uuid, p_premio uuid, p_detalhe text)
returns void
language sql
set search_path = public
as $$
  insert into premiacao_registro (em, operador, acao, round_id, premio_id, detalhe)
  select p_agora, 'automacao', 'erro', p_round, p_premio, p_detalhe
  where not exists (
    select 1 from premiacao_registro
    where acao = 'erro' and round_id is not distinct from p_round
      and premio_id is not distinct from p_premio and detalhe = p_detalhe);
$$;

-- (9) O passo da automacao, chamado pelo pg_cron a cada minuto. O horario entra por parametro
-- (os testes nunca usam now()). Desligada ou em pausa geral: nao muda nada.
-- security definer: roda como o dono (igual ao cron), seja quem for que chame. Quem pode chamar
-- e so o service_role (revoke abaixo); assim o tick nao depende dos grants de cada ambiente
-- (no CI o service_role nao le profiles).
create function public.premiacao_tick(p_agora timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  cfg       premiacao_config;
  w         record;
  p         record;
  v_fechou  int := 0;
  v_estouro int := 0;
  v_passou  int := 0;
  v_erros   int := 0;
begin
  -- Uma execucao por vez (cron e acoes do operador nao se atropelam).
  perform pg_advisory_xact_lock(hashtext('neurorace_premiacao'));

  select * into cfg from premiacao_config;
  if not cfg.premiacao_ligada then
    return jsonb_build_object('rodou', false, 'motivo', 'desligada');
  end if;
  if cfg.pausa_geral then
    return jsonb_build_object('rodou', false, 'motivo', 'pausa_geral');
  end if;

  -- Cada rodada e cada premio num bloco proprio: um erro desfaz so aquele passo, fica no
  -- registro (o painel mostra) e o resto segue. Sem isso, um erro travaria todo minuto.
  -- Fecha as rodadas que acabaram depois de ligada_em e ja passaram da carencia.
  for w in
    select r.id, r.ends_at + make_interval(mins => cfg.carencia_min) as corte
    from ranking_windows r
    where r.ends_at > cfg.ligada_em
      and r.ends_at + make_interval(mins => cfg.carencia_min) <= p_agora
      and not exists (select 1 from premiacao_rodadas x where x.round_id = r.id)
    order by r.ends_at
  loop
    begin
      insert into premiacao_rodadas (round_id, evento, fechada_em, corte_em)
      values (w.id, cfg.evento_atual, p_agora, w.corte);
      insert into premiacao_registro (em, operador, acao, round_id) values (p_agora, 'automacao', 'fechou_rodada', w.id);
      if premio_dar_vez(w.id, p_agora) is null then
        insert into premiacao_registro (em, operador, acao, round_id, detalhe)
        values (p_agora, 'automacao', 'sem_candidato', w.id, 'ninguem elegivel ate o limite da fila');
      end if;
      v_fechou := v_fechou + 1;
    exception when others then
      perform premiacao_registra_erro(p_agora, w.id, null, 'fechar rodada: ' || sqlerrm);
      v_erros := v_erros + 1;
    end;
  end loop;

  -- Prazo vencido: fica prazo_estourou e o codigo continua valendo ate o operador passar.
  for p in
    select id, round_id from premios where status = 'avisado' and prazo <= p_agora
  loop
    update premios set status = 'prazo_estourou', atualizado_em = p_agora where id = p.id;
    insert into premiacao_registro (em, operador, acao, round_id, premio_id, antes, depois)
    values (p_agora, 'automacao', 'prazo_estourou', p.round_id, p.id,
            jsonb_build_object('status', 'avisado'), jsonb_build_object('status', 'prazo_estourou'));
    v_estouro := v_estouro + 1;
  end loop;

  -- Com passar_sozinho ligado (desligado por padrao), o premio passa ao proximo.
  if cfg.passar_sozinho then
    for p in select id, round_id from premios where status = 'prazo_estourou' order by prazo loop
      begin
        perform premio_passar(p.id, 'passou', p_agora, 'automacao', 'prazo estourou');
        v_passou := v_passou + 1;
      exception when others then
        perform premiacao_registra_erro(p_agora, p.round_id, p.id, 'passar: ' || sqlerrm);
        v_erros := v_erros + 1;
      end;
    end loop;
  end if;

  return jsonb_build_object('rodou', true, 'fechou', v_fechou, 'prazo_estourou', v_estouro,
                            'passou', v_passou, 'erros', v_erros);
end;
$$;

-- Funcoes internas: so o dono (cron) e o service_role. O default-privileges do Supabase da
-- EXECUTE a anon/authenticated em funcao nova; sem este revoke, qualquer visitante chamaria
-- premiacao_tick com uma data futura e fecharia as rodadas antes da hora.
revoke all on function public.premiacao_candidatos(uuid, timestamptz) from public, anon, authenticated;
revoke all on function public.premio_novo_codigo() from public, anon, authenticated;
revoke all on function public.premio_dar_vez(uuid, timestamptz) from public, anon, authenticated;
revoke all on function public.premio_passar(uuid, text, timestamptz, text, text) from public, anon, authenticated;
revoke all on function public.premiacao_tick(timestamptz) from public, anon, authenticated;
revoke all on function public.premiacao_registra_erro(timestamptz, uuid, uuid, text) from public, anon, authenticated;
-- Explicito (nao depender do default-privileges): o tick e as acoes chamam umas as outras.
grant execute on function public.premiacao_candidatos(uuid, timestamptz) to service_role;
grant execute on function public.premio_novo_codigo() to service_role;
grant execute on function public.premio_dar_vez(uuid, timestamptz) to service_role;
grant execute on function public.premio_passar(uuid, text, timestamptz, text, text) to service_role;
grant execute on function public.premiacao_registra_erro(timestamptz, uuid, uuid, text) to service_role;
grant execute on function public.premiacao_tick(timestamptz) to service_role;

-- (10) O proprio premio, para o painel do vencedor (NEU-171). Sem parametro: so a conta da
-- sessao, so o evento atual, o mais recente primeiro. Codigo so nos estados em que vale.
-- Para a pessoa, sem_retirada e "passou": o premio nao e mais dela.
create function public.get_my_prize()
returns table (round_name text, status text, code text, claim_deadline timestamptz, delivered_at timestamptz)
language sql
stable
security definer
set search_path = public
as $$
  select w.name::text,
         case when p.status = 'sem_retirada' then 'passou' else p.status end,
         case when p.status in ('avisando', 'avisado', 'prazo_estourou', 'aviso_falhou') then p.code end,
         p.prazo,
         p.entregue_em
  from premios p
  join ranking_windows w on w.id = p.round_id
  join premiacao_config c on p.evento = c.evento_atual
  where p.user_id = (select auth.uid())
  order by w.ends_at desc, p.criado_em desc;
$$;
revoke all on function public.get_my_prize() from public, anon, authenticated;
grant execute on function public.get_my_prize() to authenticated;

-- (11) Vencedor oficial por rodada, para o letreiro do telao (NEU-173). Publico, sem contato.
-- Uma linha por rodada que a premiacao cuida (acabou depois de ligada_em); apelido e tempo de
-- quem tem o premio agora, ou os dois nulos (carencia, sem retirada, cancelado: o letreiro some).
-- Premiacao desligada: nenhuma linha (o telao volta ao 1o ao vivo).
create function public.get_official_winners()
returns table (round_id uuid, round_name text, display_name text, score numeric)
language sql
stable
security definer
set search_path = public
as $$
  select w.id, w.name::text, h.display_name, h.score
  from premiacao_config c
  join ranking_windows w on w.ends_at > c.ligada_em and w.ends_at <= now()
  left join premiacao_rodadas r on r.round_id = w.id
  left join premios h on h.round_id = w.id
                     and h.status in ('avisando', 'avisado', 'prazo_estourou', 'aviso_falhou', 'entregue')
  where c.premiacao_ligada
    and (r.round_id is null or r.evento = c.evento_atual)
  order by w.ends_at;
$$;
revoke all on function public.get_official_winners() from public;
grant execute on function public.get_official_winners() to anon, authenticated;

-- Agenda o tick de novo (a volta padrao tirou o job).
select cron.schedule('premiacao-tick', '* * * * *', $$select public.premiacao_tick()$$);
