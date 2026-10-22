-- NEU-170: aviso de corrida registrada (com conta) e convite (sem conta), pela caixa de saida
-- da NEU-112. Peca nova e separada: so LE race_players/players; nao toca em ingest_race,
-- get_leaderboard, RLS nem tabelas existentes. Se quebrar, a corrida continua entrando.
-- Tudo nasce desligado (corrida_ligada = false).
-- Volta: supabase/rollbacks/20261022100000_avisos_corrida.down.sql.
--
-- Em prod, depois da migration (so com o ok do Pedro):
--   agendar: select cron.schedule('avisos-corrida', '* * * * *', $$select public.avisos_corrida_tick()$$);
--   ligar:   update public.avisos_corrida_config set corrida_ligada = true, corrida_ligada_em = now();
--            update public.mensagens_config set tipos_ligados = tipos_ligados || array['corrida_registrada', 'corrida_convite'];
--   Conferir: select decisao, count(*) from public.avisos_corrida group by 1;
--   Voltar atras (leve): update public.avisos_corrida_config set corrida_ligada = false;

-- (1) Regras do aviso, uma linha so.
create table public.avisos_corrida_config (
  id                boolean primary key default true check (id),
  corrida_ligada    boolean     not null default false,
  corrida_ligada_em timestamptz,                         -- corrida que chegou antes disto fica de fora
  -- O aviso sai espera_min depois da 1a corrida da pessoa, com a melhor desse intervalo.
  espera_min        int         not null default 10 check (espera_min between 1 and 120),
  -- No maximo um aviso por pessoa a cada intervalo_min; corrida no meio nao gera outro.
  intervalo_min     int         not null default 30 check (intervalo_min between 1 and 1440),
  validade_min      int         not null default 120 check (validade_min between 5 and 1440),
  site_url          text        not null default 'https://neurorace-v2.vercel.app'
                                check (site_url ~ '^https://[^/\s]+$'),
  constraint avisos_corrida_ligado_tem_hora check (not corrida_ligada or corrida_ligada_em is not null),
  constraint avisos_corrida_espera_no_intervalo check (espera_min <= intervalo_min)
);
insert into public.avisos_corrida_config default values;

-- (2) O que ja foi decidido para cada corrida (o job so le race_players: guarda aqui).
create table public.avisos_corrida (
  race_player_id uuid primary key references public.race_players (id) on delete cascade,
  pessoa         text        not null,          -- 'u:<conta>' ou 'p:<jogador sem conta>'
  janela_inicio  timestamptz not null,
  decisao        text        not null check (decisao in ('avisada', 'agrupada', 'sem_contato')),
  -- Sem FK de proposito: a volta da NEU-112 (caixa de saida) nao depende desta peca.
  mensagem_id    uuid,
  decidido_em    timestamptz not null
);
create index avisos_corrida_pessoa_idx on public.avisos_corrida (pessoa, janela_inicio desc);

alter table public.avisos_corrida_config enable row level security;
alter table public.avisos_corrida        enable row level security;
revoke all on public.avisos_corrida_config, public.avisos_corrida from anon, authenticated;
grant select, insert, update, delete on public.avisos_corrida_config, public.avisos_corrida to service_role;

-- (3) Tempo como o site mostra (formatDuration): "48,3 s" (espaco nao-separavel) abaixo de 1 min,
-- "1:05,3" a partir dele, "—" para invalido. Arredonda para 1 casa antes de escolher o formato.
create function public.mensagem_formata_tempo(p_segundos numeric)
returns text
language sql
immutable
set search_path = public
as $$
  select case
    when p_segundos is null or p_segundos <= 0 then '—'
    when round(p_segundos * 10) < 600 then
      (round(p_segundos * 10)::bigint / 10)::text || ',' || (round(p_segundos * 10)::bigint % 10)::text || chr(160) || 's'
    else
      (round(p_segundos * 10)::bigint / 600)::text || ':'
      || lpad(((round(p_segundos * 10)::bigint % 600) / 10)::text, 2, '0') || ','
      || (round(p_segundos * 10)::bigint % 10)::text
  end;
$$;

-- (4) Decide as corridas novas de uma pessoa. Devolve 'avisada', 'agrupada', 'sem_contato',
-- 'esperando' ou 'nada'. Chamada pelo tick, uma pessoa por vez, cada uma no seu bloco.
create function public.avisos_corrida_pessoa(p_pessoa text, p_agora timestamptz)
returns text
language plpgsql
set search_path = public
as $$
declare
  cfg       avisos_corrida_config;
  v_user    uuid;
  v_player  uuid;
  v_ultima  timestamptz;
  v_inicio  timestamptz;
  v_agrup   int;
  melhor    record;
  v_round   uuid;
  v_rodada  text;
  v_de      timestamptz;
  v_ate     timestamptz;
  v_pos     int;
  v_destino text;
  v_tipo    text;
  v_assunto text;
  v_texto   text;
  v_chave   text;
  v_msg     uuid;
begin
  select * into cfg from avisos_corrida_config;
  if left(p_pessoa, 2) = 'u:' then
    v_user := substr(p_pessoa, 3)::uuid;
  else
    v_player := substr(p_pessoa, 3)::uuid;
  end if;

  create temp table if not exists pg_temp.avisos_novas (id uuid, player_id uuid, created_at timestamptz,
                                                         started_at timestamptz, finished_at timestamptz)
    on commit drop;
  truncate pg_temp.avisos_novas;
  insert into pg_temp.avisos_novas
  select rp.id, rp.player_id, rp.created_at, rp.started_at, rp.finished_at
  from race_players rp
  join players p on p.id = rp.player_id
  where (case when v_user is not null then p.user_id = v_user else p.id = v_player and p.user_id is null end)
    and rp.source = 'real'
    and rp.finished_at > rp.started_at
    and rp.created_at > cfg.corrida_ligada_em
    and rp.created_at <= p_agora
    and not exists (select 1 from avisos_corrida a where a.race_player_id = rp.id);

  -- Dentro do intervalo do ultimo aviso: nao gera outro.
  select max(janela_inicio) into v_ultima from avisos_corrida where pessoa = p_pessoa and decisao = 'avisada';
  if v_ultima is not null then
    insert into avisos_corrida (race_player_id, pessoa, janela_inicio, decisao, decidido_em)
    select n.id, p_pessoa, v_ultima, 'agrupada', p_agora
    from pg_temp.avisos_novas n
    where n.created_at < v_ultima + make_interval(mins => cfg.intervalo_min);
    get diagnostics v_agrup = row_count;
    delete from pg_temp.avisos_novas where created_at < v_ultima + make_interval(mins => cfg.intervalo_min);
  end if;

  select min(created_at) into v_inicio from pg_temp.avisos_novas;
  if v_inicio is null then
    return case when v_agrup > 0 then 'agrupada' else 'nada' end;
  end if;
  if p_agora < v_inicio + make_interval(mins => cfg.espera_min) then
    return 'esperando';    -- a pessoa ainda pode jogar de novo; sai um aviso so, com a melhor
  end if;
  delete from pg_temp.avisos_novas where created_at >= v_inicio + make_interval(mins => cfg.espera_min);

  select * into melhor from pg_temp.avisos_novas order by finished_at - started_at, finished_at limit 1;

  if v_user is not null then
    -- Com conta: o e-mail confirmado recebe tempo e posicao (texto 5 da NEU-165).
    v_destino := mensagens_destino_email(v_user, null);
    v_tipo := 'corrida_registrada';
    v_assunto := 'Sua corrida no NeuroRace foi registrada';
    select w.id, w.name::text, w.starts_at, w.ends_at into v_round, v_rodada, v_de, v_ate
    from ranking_windows w
    where melhor.finished_at >= w.starts_at and melhor.finished_at < w.ends_at
    order by w.starts_at desc
    limit 1;
    if v_round is not null then
      -- A mesma posicao do ranking publico da rodada (get_leaderboard), pelo apelido unico. So
      -- quando a corrida avisada e a melhor da conta na rodada: senao a posicao seria de outra
      -- corrida e leria como se fosse desta.
      select l.rank into v_pos
      from get_leaderboard('best_time', 1000, v_de, v_ate) l
      join profiles pr on pr.display_name = l.display_name
      where pr.id = v_user
        and l.score = extract(epoch from (melhor.finished_at - melhor.started_at))::numeric;
    end if;
    v_texto := 'Sua corrida no NeuroRace foi registrada: '
      || mensagem_formata_tempo(extract(epoch from (melhor.finished_at - melhor.started_at))::numeric)
      || case when v_pos is not null then ', ' || v_pos || 'º na ' || v_rodada else '' end
      || '. Veja seu card e seu arquétipo em ' || cfg.site_url || '/dashboard.';
  else
    -- Sem conta: o contato digitado no estande nao foi confirmado; vai so o convite,
    -- sem tempo nem posicao (texto 6 da NEU-165).
    v_destino := mensagens_destino_email(null, v_player);
    v_tipo := 'corrida_convite';
    v_assunto := 'Você jogou NeuroRace!';
    v_texto := 'Você jogou NeuroRace! Entre em ' || cfg.site_url || '/login com este contato para ver o '
      || 'resultado da sua corrida, seu card e seu arquétipo, e entrar no ranking.';
  end if;

  if v_destino is null then
    -- So celular: o WhatsApp e da NEU-113.
    insert into avisos_corrida (race_player_id, pessoa, janela_inicio, decisao, decidido_em)
    select n.id, p_pessoa, v_inicio, 'sem_contato', p_agora from pg_temp.avisos_novas n;
    return 'sem_contato';
  end if;

  v_chave := 'corrida:' || p_pessoa || ':' || extract(epoch from v_inicio)::bigint || ':email';
  v_msg := mensagem_enfileirar(v_tipo, 'email', v_destino, v_chave,
             p_agora + make_interval(mins => cfg.validade_min), v_assunto, v_texto, null,
             v_user, melhor.player_id, null, v_round, p_agora);
  if v_msg is null then
    select id into v_msg from mensagens where chave = v_chave;
  end if;
  insert into avisos_corrida (race_player_id, pessoa, janela_inicio, decisao, mensagem_id, decidido_em)
  select n.id, p_pessoa, v_inicio, 'avisada', v_msg, p_agora from pg_temp.avisos_novas n;
  return 'avisada';
end;
$$;

-- (5) O passo do job, chamado pelo pg_cron a cada minuto. O horario entra por parametro (os
-- testes nunca usam now()). Cada pessoa num bloco proprio: um erro desfaz so aquela pessoa.
-- security definer: roda como o dono, seja quem for que chame; so o service_role pode chamar.
create function public.avisos_corrida_tick(p_agora timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  cfg      avisos_corrida_config;
  pes      record;
  v_r      text;
  v_avisos int := 0;
  v_sem    int := 0;
  v_erros  int := 0;
begin
  select * into cfg from avisos_corrida_config;
  if not cfg.corrida_ligada then
    return jsonb_build_object('rodou', false, 'motivo', 'desligado');
  end if;
  -- Uma execucao por vez.
  perform pg_advisory_xact_lock(hashtext('neurorace_avisos_corrida'));

  for pes in
    select distinct case when p.user_id is not null then 'u:' || p.user_id else 'p:' || p.id end as pessoa
    from race_players rp
    join players p on p.id = rp.player_id
    where rp.source = 'real'
      and rp.finished_at > rp.started_at
      and rp.created_at > cfg.corrida_ligada_em
      and rp.created_at <= p_agora
      and not exists (select 1 from avisos_corrida a where a.race_player_id = rp.id)
  loop
    begin
      v_r := avisos_corrida_pessoa(pes.pessoa, p_agora);
      if v_r = 'avisada' then v_avisos := v_avisos + 1; end if;
      if v_r = 'sem_contato' then v_sem := v_sem + 1; end if;
    exception when others then
      v_erros := v_erros + 1;
      raise warning 'avisos_corrida_tick: % (%)', pes.pessoa, sqlerrm;
    end;
  end loop;

  return jsonb_build_object('rodou', true, 'avisos', v_avisos, 'sem_contato', v_sem, 'erros', v_erros);
end;
$$;

revoke all on function public.mensagem_formata_tempo(numeric) from public, anon, authenticated;
revoke all on function public.avisos_corrida_pessoa(text, timestamptz) from public, anon, authenticated;
revoke all on function public.avisos_corrida_tick(timestamptz) from public, anon, authenticated;
grant execute on function public.mensagem_formata_tempo(numeric) to service_role;
grant execute on function public.avisos_corrida_pessoa(text, timestamptz) to service_role;
grant execute on function public.avisos_corrida_tick(timestamptz) to service_role;
