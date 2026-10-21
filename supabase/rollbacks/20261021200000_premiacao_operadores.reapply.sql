-- RELIGAR a NEU-168 depois da volta padrao (20261021200000_premiacao_operadores.down.sql, Parte A).
-- A lista de operadores fica; este arquivo recria as funcoes (secao (2) em diante da migration,
-- copia fiel, com os mesmos revoke/grant). Reaplicar a migration inteira falha
-- ("operadores already exists") e o db push nao age.
-- Rodar numa transacao: psql -v ON_ERROR_STOP=1 -1 -f <este arquivo>
-- Se a NEU-167 tambem foi desligada: o reapply dela primeiro, depois este.
--
-- Gerado da migration, nao editar a mao:
--   sed -n '/^-- (2) Quem chama e operador/,$p' supabase/migrations/20261021200000_premiacao_operadores.sql

-- (2) Quem chama e operador? E-mail CONFIRMADO da conta da sessao (auth.users), presente na
-- lista. Conta so com celular nunca e operadora. Fora disso: 42501, que o site mostra como
-- "sem acesso".
create function public.premiacao_operador_atual()
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_email text;
begin
  select lower(btrim(u.email)) into v_email
  from auth.users u
  where u.id = (select auth.uid())
    and u.email_confirmed_at is not null
    and exists (select 1 from operadores o where o.email = lower(btrim(u.email)));
  if v_email is null then
    raise exception 'sem acesso a premiacao' using errcode = '42501';
  end if;
  return v_email;
end;
$$;

-- (3) Contato para o celular do operador, ja mascarado (o contato completo nunca sai do banco).
-- "lu***@gmail.com | (11) *****-4321"; null quando a conta nao tem contato confirmado.
create function public.premiacao_mascara_contato(p_email text, p_phone text)
returns text
language sql
immutable
set search_path = public
as $$
  select nullif(concat_ws(' | ',
    case when p_email like '_%@_%' then left(split_part(p_email, '@', 1), 2) || '***@' || split_part(p_email, '@', 2) end,
    case
      when regexp_replace(coalesce(p_phone, ''), '\D', '', 'g') ~ '^55[0-9]{10,11}$'
        then '(' || substr(regexp_replace(p_phone, '\D', '', 'g'), 3, 2) || ') *****-' || right(regexp_replace(p_phone, '\D', '', 'g'), 4)
      when coalesce(p_phone, '') <> '' then '***' || right(regexp_replace(p_phone, '\D', '', 'g'), 4)
    end), '');
$$;

-- (4) Da a vez ao proximo elegivel com limite opcional (null = sem limite) e, se pedido, por
-- sorteio entre os elegiveis. Mesma regra de elegiveis da NEU-167 (D2/D4): conta sem premio
-- valendo no evento e que ainda nao teve a vez nesta rodada. premio_dar_vez (NEU-167) passa a
-- ser esta com o limite da configuracao, sem mudar de comportamento.
create function public.premio_dar_vez_ate(p_round uuid, p_agora timestamptz, p_limite int, p_sortear boolean)
returns uuid
language plpgsql
set search_path = public
as $$
declare
  cfg   premiacao_config;
  rod   premiacao_rodadas;
  c     record;
  v_id  uuid;
  v_vez int;
begin
  perform pg_advisory_xact_lock(hashtext('neurorace_premiacao'));
  select * into cfg from premiacao_config;
  select * into rod from premiacao_rodadas where round_id = p_round;

  select count(*) + 1 into v_vez from premios where round_id = p_round;
  if p_limite is not null and v_vez > p_limite then
    return null;
  end if;

  select k.* into c
  from premiacao_candidatos(p_round, rod.corte_em) k
  where not exists (select 1 from premios x where x.round_id = p_round and x.user_id = k.user_id)
    and not exists (select 1 from premios x
                    where x.evento = rod.evento and x.user_id = k.user_id
                      and x.status in ('avisando', 'avisado', 'prazo_estourou', 'aviso_falhou', 'entregue'))
  order by case when p_sortear then random() end, k.posicao
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
          format('%s (%sº no ranking, %sª vez%s) ficou com o premio', c.display_name, c.posicao, v_vez,
                 case when p_sortear then ', sorteio' else '' end));
  return v_id;
end;
$$;

create or replace function public.premio_dar_vez(p_round uuid, p_agora timestamptz)
returns uuid
language sql
set search_path = public
as $$
  select premio_dar_vez_ate(p_round, p_agora, (select limite_fila from premiacao_config), false);
$$;

-- (5) Leitura do painel (op_painel). Contrato da NEU-114: agora, config (9 chaves; piso_tempo_s
-- fica fora de proposito), premios do evento atual (mais recentes primeiro) e as ultimas 20 acoes.
create function public.premiacao_op_painel(p_agora timestamptz)
returns jsonb
language sql
stable
set search_path = public
as $$
  select jsonb_build_object(
    'agora', p_agora,
    'config', (select jsonb_build_object(
                 'premiacao_ligada', c.premiacao_ligada, 'pausa_geral', c.pausa_geral, 'passar_sozinho', c.passar_sozinho,
                 'carencia_min', c.carencia_min, 'janela_min', c.janela_min, 'lembrete_min', c.lembrete_min,
                 'limite_fila', c.limite_fila, 'ligada_em', c.ligada_em, 'evento_atual', c.evento_atual)
               from premiacao_config c),
    'premios', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', p.id, 'round_id', p.round_id, 'round_name', w.name, 'round_ends_at', w.ends_at,
               'posicao', p.posicao, 'display_name', p.display_name,
               'contato', premiacao_mascara_contato(
                            case when u.email_confirmed_at is not null then u.email end,
                            case when u.phone_confirmed_at is not null then u.phone end),
               'score', p.score,
               'atencao_media', (select round(avg(t.attention)::numeric, 1) from telemetry_points t
                                 where t.race_player_id = p.race_player_id and t.attention is not null),
               'status', p.status, 'prazo', p.prazo, 'entregue_em', p.entregue_em,
               -- sem nenhum contato confirmado, nenhum aviso chega (canais: NEU-112/113)
               'sem_canal', (u.email_confirmed_at is null and u.phone_confirmed_at is null))
             order by w.ends_at desc, p.posicao asc)
      from premios p
      join ranking_windows w on w.id = p.round_id
      left join auth.users u on u.id = p.user_id
      where p.evento = (select evento_atual from premiacao_config)), '[]'::jsonb),
    'registro', coalesce((
      select jsonb_agg(jsonb_build_object('em', g.em, 'operador', g.operador, 'acao', g.acao,
                                          'round_name', g.round_name, 'detalhe', g.detalhe) order by g.em desc, g.id desc)
      from (select r.id, r.em, r.operador, r.acao, w.name::text as round_name, r.detalhe
            from premiacao_registro r left join ranking_windows w on w.id = r.round_id
            order by r.em desc, r.id desc limit 20) g), '[]'::jsonb));
$$;

-- (6) Validar o codigo de quem veio buscar. Certo -> entregue; repetido -> ja_entregue;
-- de premio passado ou inexistente -> invalido. 5 erros em 1 min do mesmo operador -> espere
-- (a tentativa que espera nao conta como erro). O codigo nunca vai para o registro.
create function public.premiacao_op_validar(p_operador text, p_codigo text, p_agora timestamptz)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  v_code  text := regexp_replace(coalesce(p_codigo, ''), '\D', '', 'g');
  v_ev    text;
  v_erros int;
  v_ate   timestamptz;
  p       record;
begin
  perform pg_advisory_xact_lock(hashtext('neurorace_premiacao'));
  select evento_atual into v_ev from premiacao_config;

  select count(*) into v_erros from premiacao_registro
   where operador = p_operador and acao = 'codigo_errado' and em > p_agora - interval '1 minute' and em <= p_agora;
  if v_erros >= 5 then
    select em + interval '1 minute' into v_ate from premiacao_registro
     where operador = p_operador and acao = 'codigo_errado' and em > p_agora - interval '1 minute' and em <= p_agora
     order by em desc offset 4 limit 1;
    insert into premiacao_registro (em, operador, acao, detalhe) values (p_agora, p_operador, 'espere', 'muitas tentativas');
    return jsonb_build_object('resultado', 'espere', 'espere_ate', v_ate);
  end if;

  select x.id, x.round_id, x.display_name, x.status, w.name::text as round_name into p
  from premios x join ranking_windows w on w.id = x.round_id
  where v_code ~ '^[0-9]{6}$' and x.code = v_code and x.evento = v_ev
    and x.status in ('avisando', 'avisado', 'prazo_estourou', 'aviso_falhou')
  for update of x;
  if p.id is not null then
    update premios set status = 'entregue', entregue_em = p_agora, atualizado_em = p_agora where id = p.id;
    insert into premiacao_registro (em, operador, acao, round_id, premio_id, detalhe, antes, depois)
    values (p_agora, p_operador, 'entregue', p.round_id, p.id, p.display_name,
            jsonb_build_object('status', p.status), jsonb_build_object('status', 'entregue'));
    return jsonb_build_object('resultado', 'entregue', 'display_name', p.display_name,
                              'round_name', p.round_name, 'entregue_em', p_agora);
  end if;

  select x.id, x.round_id, x.display_name, x.entregue_em, w.name::text as round_name into p
  from premios x join ranking_windows w on w.id = x.round_id
  where v_code ~ '^[0-9]{6}$' and x.code = v_code and x.evento = v_ev and x.status = 'entregue'
  order by x.entregue_em desc limit 1;
  if p.id is not null then
    insert into premiacao_registro (em, operador, acao, round_id, premio_id, detalhe)
    values (p_agora, p_operador, 'codigo_repetido', p.round_id, p.id, p.display_name);
    return jsonb_build_object('resultado', 'ja_entregue', 'display_name', p.display_name,
                              'round_name', p.round_name, 'entregue_em', p.entregue_em);
  end if;

  insert into premiacao_registro (em, operador, acao, detalhe) values (p_agora, p_operador, 'codigo_errado', null);
  return jsonb_build_object('resultado', 'invalido');
end;
$$;

-- (7) Acoes do operador sobre um premio. Erro de negocio nao e excecao: {"ok": false, "erro": "..."}.
create function public.premiacao_op_acao(p_operador text, p_premio uuid, p_acao text, p_motivo text, p_agora timestamptz)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  v       premios;
  v_mot   text := nullif(btrim(coalesce(p_motivo, '')), '');
  v_novo  uuid;
  v_depois text;
  aberto  constant text[] := array['avisando', 'avisado', 'prazo_estourou', 'aviso_falhou'];
begin
  perform pg_advisory_xact_lock(hashtext('neurorace_premiacao'));
  select * into v from premios where id = p_premio for update;
  if v.id is null then
    return jsonb_build_object('ok', false, 'erro', 'Prêmio não encontrado.');
  end if;
  if v.evento is distinct from (select evento_atual from premiacao_config) then
    return jsonb_build_object('ok', false, 'erro', 'Esse prêmio é de outro evento.');
  end if;
  if p_acao in ('entregue_sem_codigo', 'cancelar') and v_mot is null then
    return jsonb_build_object('ok', false, 'erro', 'Escreva o motivo.');
  end if;

  if p_acao in ('mais_10_min', 'passar', 'entregue_sem_codigo', 'cancelar') then
    if not v.status = any (aberto) then
      return jsonb_build_object('ok', false, 'erro', 'Esse prêmio não está em aberto.');
    end if;
    if p_acao = 'mais_10_min' then
      update premios set prazo = greatest(coalesce(prazo, p_agora), p_agora) + interval '10 minutes',
                         status = case when status = 'prazo_estourou' then 'avisado' else status end,
                         atualizado_em = p_agora
       where id = v.id;
    elsif p_acao = 'passar' then
      perform premio_passar(v.id, 'passou', p_agora, p_operador, v_mot);
    elsif p_acao = 'entregue_sem_codigo' then
      update premios set status = 'entregue', entregue_em = p_agora, motivo = v_mot, atualizado_em = p_agora where id = v.id;
    else
      update premios set status = 'cancelado', motivo = v_mot, atualizado_em = p_agora where id = v.id;
    end if;

  elsif p_acao in ('continuar', 'sortear', 'guardar') then
    if v.status <> 'sem_retirada' then
      return jsonb_build_object('ok', false, 'erro', 'Só vale depois que a fila acabou.');
    end if;
    if p_acao = 'guardar' then
      update premios set status = 'cancelado', motivo = coalesce(v_mot, 'prêmio guardado'), atualizado_em = p_agora where id = v.id;
    else
      -- um por vez, alem do limite da fila, com a mesma regra de elegiveis
      v_novo := premio_dar_vez_ate(v.round_id, p_agora, null, p_acao = 'sortear');
      if v_novo is null then
        return jsonb_build_object('ok', false, 'erro', 'Ninguém mais pode receber este prêmio.');
      end if;
      update premios set status = 'passou', atualizado_em = p_agora where id = v.id;
    end if;

  else
    return jsonb_build_object('ok', false, 'erro', 'Ação desconhecida.');
  end if;

  select status into v_depois from premios where id = v.id;
  if p_acao <> 'passar' then   -- premio_passar ja grava o proprio registro
    insert into premiacao_registro (em, operador, acao, round_id, premio_id, detalhe, antes, depois)
    values (p_agora, p_operador, p_acao, v.round_id, v.id, v_mot,
            jsonb_build_object('status', v.status, 'prazo', v.prazo),
            (select jsonb_build_object('status', x.status, 'prazo', x.prazo, 'proximo', v_novo) from premios x where x.id = v.id));
  end if;
  return jsonb_build_object('ok', true);
end;
$$;

-- (8) Mudar regras: merge parcial das 9 chaves do contrato. Ligar sem ligada_em grava agora.
-- Chave desconhecida, tipo errado ou valor fora da faixa -> erro (nada e gravado).
create function public.premiacao_op_config(p_operador text, p_mudancas jsonb, p_agora timestamptz)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  v_antes  jsonb;
  v_depois jsonb;
  k        text;
  permitidas constant text[] := array['premiacao_ligada', 'pausa_geral', 'passar_sozinho', 'carencia_min', 'janela_min',
                                      'lembrete_min', 'limite_fila', 'ligada_em', 'evento_atual'];
begin
  perform pg_advisory_xact_lock(hashtext('neurorace_premiacao'));
  if jsonb_typeof(p_mudancas) is distinct from 'object' then
    raise exception 'op_config: esperado um objeto' using errcode = '22023';
  end if;
  for k in select jsonb_object_keys(p_mudancas) loop
    if not k = any (permitidas) then
      raise exception 'op_config: chave % nao pode ser mudada aqui', k using errcode = '22023';
    end if;
    -- tipo JSON exato: "5" ou "true" (texto) nao valem
    if (k in ('premiacao_ligada', 'pausa_geral', 'passar_sozinho') and jsonb_typeof(p_mudancas -> k) <> 'boolean')
       or (k in ('carencia_min', 'janela_min', 'lembrete_min', 'limite_fila')
           and (jsonb_typeof(p_mudancas -> k) <> 'number' or (p_mudancas ->> k)::numeric <> trunc((p_mudancas ->> k)::numeric)))
       or (k = 'evento_atual' and jsonb_typeof(p_mudancas -> k) <> 'string')
       or (k = 'ligada_em' and jsonb_typeof(p_mudancas -> k) not in ('string', 'null')) then
      raise exception 'op_config: valor de % no tipo errado', k using errcode = '22023';
    end if;
  end loop;

  v_antes := premiacao_op_painel(p_agora) -> 'config';
  update premiacao_config c set
    premiacao_ligada = coalesce((p_mudancas ->> 'premiacao_ligada')::boolean, c.premiacao_ligada),
    pausa_geral      = coalesce((p_mudancas ->> 'pausa_geral')::boolean, c.pausa_geral),
    passar_sozinho   = coalesce((p_mudancas ->> 'passar_sozinho')::boolean, c.passar_sozinho),
    carencia_min     = coalesce((p_mudancas ->> 'carencia_min')::int, c.carencia_min),
    janela_min       = coalesce((p_mudancas ->> 'janela_min')::int, c.janela_min),
    lembrete_min     = coalesce((p_mudancas ->> 'lembrete_min')::int, c.lembrete_min),
    limite_fila      = coalesce((p_mudancas ->> 'limite_fila')::int, c.limite_fila),
    evento_atual     = coalesce(p_mudancas ->> 'evento_atual', c.evento_atual),
    ligada_em        = case
                         when p_mudancas ? 'ligada_em' then (p_mudancas ->> 'ligada_em')::timestamptz
                         when (p_mudancas ->> 'premiacao_ligada')::boolean and c.ligada_em is null then p_agora
                         else c.ligada_em
                       end
   where c.id;   -- linha unica; o WHERE e exigido pelo safeupdate das sessoes do PostgREST
  v_depois := premiacao_op_painel(p_agora) -> 'config';

  insert into premiacao_registro (em, operador, acao, detalhe, antes, depois)
  values (p_agora, p_operador, 'config', p_mudancas::text, v_antes, v_depois);
  return v_depois;
end;
$$;

-- Internas: so o dono e o service_role (o default-privileges do Supabase daria EXECUTE a anon).
revoke all on function public.premiacao_operador_atual() from public, anon, authenticated;
revoke all on function public.premiacao_mascara_contato(text, text) from public, anon, authenticated;
revoke all on function public.premio_dar_vez_ate(uuid, timestamptz, int, boolean) from public, anon, authenticated;
revoke all on function public.premiacao_op_painel(timestamptz) from public, anon, authenticated;
revoke all on function public.premiacao_op_validar(text, text, timestamptz) from public, anon, authenticated;
revoke all on function public.premiacao_op_acao(text, uuid, text, text, timestamptz) from public, anon, authenticated;
revoke all on function public.premiacao_op_config(text, jsonb, timestamptz) from public, anon, authenticated;
grant execute on function public.premiacao_operador_atual() to service_role;
grant execute on function public.premiacao_mascara_contato(text, text) to service_role;
grant execute on function public.premio_dar_vez_ate(uuid, timestamptz, int, boolean) to service_role;
grant execute on function public.premiacao_op_painel(timestamptz) to service_role;
grant execute on function public.premiacao_op_validar(text, text, timestamptz) to service_role;
grant execute on function public.premiacao_op_acao(text, uuid, text, text, timestamptz) to service_role;
grant execute on function public.premiacao_op_config(text, jsonb, timestamptz) to service_role;
-- premio_dar_vez foi recriada: o create or replace mantem os grants da NEU-167.

-- (9) O que o site chama. Conferem o operador (42501 para quem nao e) e usam a hora do servidor.
create function public.op_painel()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  perform premiacao_operador_atual();
  return premiacao_op_painel(now());
end;
$$;

create function public.op_validar_codigo(p_codigo text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return premiacao_op_validar(premiacao_operador_atual(), p_codigo, now());
end;
$$;

create function public.op_acao(p_premio uuid, p_acao text, p_motivo text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return premiacao_op_acao(premiacao_operador_atual(), p_premio, p_acao, p_motivo, now());
end;
$$;

create function public.op_config(p_mudancas jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return premiacao_op_config(premiacao_operador_atual(), p_mudancas, now());
end;
$$;

revoke all on function public.op_painel() from public, anon;
revoke all on function public.op_validar_codigo(text) from public, anon;
revoke all on function public.op_acao(uuid, text, text) from public, anon;
revoke all on function public.op_config(jsonb) from public, anon;
grant execute on function public.op_painel() to authenticated;
grant execute on function public.op_validar_codigo(text) to authenticated;
grant execute on function public.op_acao(uuid, text, text) to authenticated;
grant execute on function public.op_config(jsonb) to authenticated;
