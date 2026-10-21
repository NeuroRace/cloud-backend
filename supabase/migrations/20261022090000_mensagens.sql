-- NEU-112: caixa de saida das mensagens da premiacao e envio por e-mail (Brevo).
-- Peca nova e separada: nao toca em ingest_race, get_leaderboard, RLS nem tabelas existentes.
-- Le premios/premiacao_config da NEU-167 e chama premio_passar ("Nao vou poder").
-- Tudo nasce desligado (email_ligado = false, tipos_ligados vazio): sem ligar, nada sai.
-- Volta: supabase/rollbacks/20261022090000_mensagens.down.sql.
--
-- Em prod, depois da migration (so com o ok do Pedro; nenhum segredo vai para o repo):
--   1) secrets das funcoes (Dashboard > Edge Functions > Secrets): BREVO_API_KEY,
--      MENSAGENS_REMETENTE (e-mail do dominio validado na Brevo, NEU-164), MENSAGENS_CRON_TOKEN,
--      MENSAGENS_LINK_SECRET (aleatorio, >= 32 bytes) e SITE_URL (https://neurorace-v2.vercel.app);
--      supabase functions deploy send-messages && supabase functions deploy message-actions
--   2) o mesmo MENSAGENS_CRON_TOKEN no Vault, para o cron ler sem gravar o token no job:
--      select vault.create_secret('<MENSAGENS_CRON_TOKEN>', 'mensagens_cron_token');
--   3) agendar (NAO e feito aqui: o CI e quem aplica a migration nao ganham um job rodando):
--      select cron.schedule('mensagens-envio', '* * * * *', $$
--        select net.http_post(
--          url := 'https://wtaulbdkgrnrtbfezaxw.supabase.co/functions/v1/send-messages',
--          headers := jsonb_build_object('content-type', 'application/json', 'x-cron-token',
--            (select decrypted_secret from vault.decrypted_secrets where name = 'mensagens_cron_token')),
--          body := '{}'::jsonb, timeout_milliseconds := 30000) $$);
--   4) ligar: update public.mensagens_config set email_ligado = true,
--        tipos_ligados = array['premio_venceu', 'premio_lembrete', ...];
--   Conferir: select estado, count(*) from public.mensagens group by 1;
--             select * from net._http_response order by created desc limit 5;
--   Voltar atras (leve): update public.mensagens_config set email_ligado = false;
--                        ou select cron.unschedule('mensagens-envio');

create extension if not exists pg_net;

-- (1) Regras do envio, uma linha so.
create table public.mensagens_config (
  id               boolean primary key default true check (id),
  email_ligado     boolean not null default false,
  -- Um tipo so sai se estiver aqui (interruptor por tipo).
  tipos_ligados    text[]  not null default '{}',
  -- Brevo gratis: 300 e-mails por dia. Conta numa janela movel de 24 h.
  teto_diario      int     not null default 300 check (teto_diario between 1 and 100000),
  -- O aviso de corrida para quando faltam estes envios para o teto: sobra para o premio.
  reserva_premio   int     not null default 50 check (reserva_premio >= 0),
  -- Depois da primeira tentativa, quantas novas (espera de 1, 2, 4... min).
  novas_tentativas int     not null default 3 check (novas_tentativas between 0 and 10)
);
insert into public.mensagens_config default values;

-- (2) Caixa de saida. Quem enfileira (NEU-169, NEU-170) ja grava o texto final;
-- o send-messages so acrescenta o rodape com os links assinados.
create table public.mensagens (
  id                   uuid primary key default gen_random_uuid(),
  tipo                 text not null check (tipo in (
                         'premio_faltam_10', 'premio_venceu', 'premio_lembrete', 'premio_prazo_passou',
                         'corrida_registrada', 'corrida_convite')),
  categoria            text generated always as (case when tipo like 'premio\_%' then 'premio' else 'corrida' end) stored,
  canal                text not null check (canal in ('email', 'whatsapp')),
  destino              text not null,
  user_id              uuid references auth.users (id) on delete set null,
  player_id            uuid references public.players (id) on delete set null,
  premio_id            uuid references public.premios (id) on delete set null,
  round_id             uuid,
  -- rodada + pessoa + tipo + canal, montada por quem enfileira: a mesma chave entra uma vez so.
  chave                text not null unique,
  assunto              text not null,
  corpo_texto          text not null,
  corpo_html           text,
  validade             timestamptz not null,
  estado               text not null default 'pendente' check (estado in (
                         'pendente', 'enviada', 'falhou', 'expirada', 'cancelada', 'bloqueada')),
  tentativas           int not null default 0,
  proxima_tentativa_em timestamptz,
  -- Trava de envio: enquanto valer, outro envio nao pega a mensagem.
  travada_ate          timestamptz,
  provedor_id          text,
  erro                 text,
  criada_em            timestamptz not null,
  enviada_em           timestamptz,
  atualizada_em        timestamptz not null
);
create index mensagens_pendentes_idx on public.mensagens (canal, proxima_tentativa_em) where estado = 'pendente';
create index mensagens_enviadas_idx on public.mensagens (canal, enviada_em) where enviada_em is not null;
create index mensagens_destino_idx on public.mensagens (canal, destino);

-- (3) Lista de "nao enviar", por canal + contato: vale para todos os tipos.
create table public.mensagens_bloqueio (
  canal     text not null check (canal in ('email', 'whatsapp')),
  contato   text not null,
  origem    text not null,
  criado_em timestamptz not null,
  primary key (canal, contato)
);

-- Acesso: so service_role e as funcoes abaixo. O default-privileges do Supabase concede ALL
-- (inclusive TRUNCATE, que ignora RLS) a anon/authenticated em tabela nova; aqui tiramos tudo.
alter table public.mensagens_config   enable row level security;
alter table public.mensagens          enable row level security;
alter table public.mensagens_bloqueio enable row level security;
revoke all on public.mensagens_config, public.mensagens, public.mensagens_bloqueio from anon, authenticated;
grant select, insert, update, delete on public.mensagens_config, public.mensagens, public.mensagens_bloqueio
  to service_role;

-- (4) Contato normalizado: e-mail em lower/trim (como players.email), WhatsApp so digitos.
create function public.mensagens_contato(p_canal text, p_contato text)
returns text
language sql
immutable
set search_path = public
as $$
  select case when p_canal = 'whatsapp' then regexp_replace(p_contato, '[^0-9]', '', 'g')
              else lower(btrim(p_contato)) end;
$$;

-- (5) Enfileirar. Chave repetida -> null (nada muda). Contato bloqueado -> ja nasce bloqueada.
create function public.mensagem_enfileirar(
  p_tipo text, p_canal text, p_destino text, p_chave text, p_validade timestamptz,
  p_assunto text, p_corpo_texto text, p_corpo_html text default null,
  p_user uuid default null, p_player uuid default null, p_premio uuid default null, p_round uuid default null,
  p_agora timestamptz default now())
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_destino text := mensagens_contato(p_canal, p_destino);
  v_id      uuid;
begin
  insert into mensagens (tipo, canal, destino, user_id, player_id, premio_id, round_id, chave,
                         assunto, corpo_texto, corpo_html, validade, estado, criada_em, atualizada_em)
  values (p_tipo, p_canal, v_destino, p_user, p_player, p_premio, p_round, p_chave,
          p_assunto, p_corpo_texto, p_corpo_html, p_validade,
          case when exists (select 1 from mensagens_bloqueio b where b.canal = p_canal and b.contato = v_destino)
               then 'bloqueada' else 'pendente' end,
          p_agora, p_agora)
  on conflict (chave) do nothing
  returning id into v_id;
  return v_id;
end;
$$;

-- (6) Para quem mandar por e-mail. Com conta: so o e-mail confirmado (auth.users). Sem conta:
-- o e-mail digitado no estande (players.email), que a pessoa nao confirmou: quem enfileira
-- manda para ele so o convite, sem tempo nem posicao (NEU-170).
create function public.mensagens_destino_email(p_user uuid, p_player uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case
    when p_user is not null then
      (select u.email::text from auth.users u where u.id = p_user and u.email_confirmed_at is not null)
    when p_player is not null then
      (select p.email from players p where p.id = p_player)
  end;
$$;

-- Funcoes: so service_role. O default-privileges do Supabase da EXECUTE a anon/authenticated.
revoke all on function public.mensagens_contato(text, text) from public, anon, authenticated;
revoke all on function public.mensagem_enfileirar(text, text, text, text, timestamptz, text, text, text,
  uuid, uuid, uuid, uuid, timestamptz) from public, anon, authenticated;
revoke all on function public.mensagens_destino_email(uuid, uuid) from public, anon, authenticated;
grant execute on function public.mensagens_contato(text, text) to service_role;
grant execute on function public.mensagem_enfileirar(text, text, text, text, timestamptz, text, text, text,
  uuid, uuid, uuid, uuid, timestamptz) to service_role;
grant execute on function public.mensagens_destino_email(uuid, uuid) to service_role;

-- (7) Prepara um lote para envio. Ordem: expira o que venceu, bloqueia contato da lista, cancela
-- aviso de premio que nao vale mais; com o canal ligado e sem pausa geral, trava e devolve as
-- prontas (premio antes de corrida), respeitando o teto. Mensagem travada (em envio) nao e tocada.
-- O horario entra por parametro (os testes nunca usam now()).
create function public.mensagens_preparar(p_canal text, p_agora timestamptz, p_limite int default 20)
returns setof public.mensagens
language plpgsql
security definer
set search_path = public
as $$
declare
  cfg          mensagens_config;
  m            mensagens;
  v_usados     int;
  v_devolvidas int := 0;
begin
  select * into cfg from mensagens_config;

  -- Mensagem vencida nunca sai, nem quando o canal religar.
  update mensagens set estado = 'expirada', atualizada_em = p_agora
   where canal = p_canal and estado = 'pendente' and validade <= p_agora
     and (travada_ate is null or travada_ate <= p_agora);

  update mensagens x set estado = 'bloqueada', atualizada_em = p_agora
   where x.canal = p_canal and x.estado = 'pendente'
     and (x.travada_ate is null or x.travada_ate <= p_agora)
     and exists (select 1 from mensagens_bloqueio b where b.canal = x.canal and b.contato = x.destino);

  -- "Voce venceu" e lembrete de um premio que passou, foi recusado ou entregue: nao sai.
  -- (O "prazo passou" e justamente sobre premio que nao vale mais, entao fica.)
  update mensagens x set estado = 'cancelada', erro = 'o premio nao vale mais', atualizada_em = p_agora
   where x.canal = p_canal and x.estado = 'pendente' and x.tipo in ('premio_venceu', 'premio_lembrete')
     and (x.travada_ate is null or x.travada_ate <= p_agora)
     and x.premio_id is not null
     and not exists (select 1 from premios p where p.id = x.premio_id
                       and p.status in ('avisando', 'avisado', 'prazo_estourou', 'aviso_falhou'));

  -- So o e-mail tem envio por enquanto (WhatsApp: NEU-113).
  if p_canal <> 'email' or not cfg.email_ligado then
    return;
  end if;
  if coalesce((select c.pausa_geral from premiacao_config c), false) then
    return;
  end if;

  -- Teto numa janela movel de 24 h: enviadas + as que estao em envio agora.
  select count(*) into v_usados from mensagens
   where canal = p_canal
     and ((enviada_em > p_agora - interval '24 hours' and enviada_em <= p_agora)
          or (estado = 'pendente' and travada_ate > p_agora));

  for m in
    select * from mensagens
    where canal = p_canal and estado = 'pendente' and tipo = any (cfg.tipos_ligados)
      and (proxima_tentativa_em is null or proxima_tentativa_em <= p_agora)
      and (travada_ate is null or travada_ate <= p_agora)
    order by (categoria = 'premio') desc, criada_em, id
    for update skip locked
  loop
    exit when v_devolvidas >= p_limite;
    -- Reserva para o premio: o aviso de corrida para antes do teto.
    if m.categoria = 'corrida' and v_usados >= cfg.teto_diario - cfg.reserva_premio then
      update mensagens set estado = 'bloqueada', erro = 'teto diario', atualizada_em = p_agora where id = m.id;
      continue;
    end if;
    -- Teto cheio: o premio espera (pendente) a janela de 24 h andar ou a validade vencer.
    if v_usados >= cfg.teto_diario then
      update mensagens set erro = 'teto diario', atualizada_em = p_agora where id = m.id;
      continue;
    end if;
    update mensagens set travada_ate = p_agora + interval '2 minutes', tentativas = tentativas + 1,
                         atualizada_em = p_agora
     where id = m.id
    returning * into m;
    v_usados := v_usados + 1;
    v_devolvidas := v_devolvidas + 1;
    return next m;
  end loop;
end;
$$;

-- (8) Resultado de um envio. Falha temporaria -> nova tentativa em 1, 2, 4... min, ate
-- novas_tentativas; depois (ou falha definitiva) -> falhou. Falha de aviso de premio vai para o
-- registro da premiacao, que o operador ve no painel. Devolve o estado da mensagem.
create function public.mensagem_resultado(p_id uuid, p_ok boolean, p_provedor_id text, p_erro text,
                                          p_definitivo boolean, p_agora timestamptz)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  cfg mensagens_config;
  m   mensagens;
begin
  select * into cfg from mensagens_config;
  select * into m from mensagens where id = p_id for update;
  if m.id is null then
    return null;
  end if;
  if m.estado <> 'pendente' then
    return m.estado;
  end if;

  if p_ok then
    update mensagens set estado = 'enviada', enviada_em = p_agora, provedor_id = p_provedor_id, erro = null,
                         travada_ate = null, proxima_tentativa_em = null, atualizada_em = p_agora
     where id = p_id;
    return 'enviada';
  end if;

  if p_definitivo or m.tentativas >= 1 + cfg.novas_tentativas then
    update mensagens set estado = 'falhou', erro = p_erro, travada_ate = null, atualizada_em = p_agora
     where id = p_id;
    if m.premio_id is not null then
      perform premiacao_registra_erro(p_agora,
        coalesce(m.round_id, (select p.round_id from premios p where p.id = m.premio_id)),
        m.premio_id, 'aviso por e-mail falhou: ' || coalesce(p_erro, 'sem detalhe'));
    end if;
    return 'falhou';
  end if;

  update mensagens set erro = p_erro, travada_ate = null, atualizada_em = p_agora,
                       proxima_tentativa_em = p_agora + make_interval(mins => (2 ^ (greatest(m.tentativas, 1) - 1))::int)
   where id = p_id;
  return 'pendente';
end;
$$;

-- (9) "Parar de receber" (link do e-mail): o contato da mensagem entra na lista e as pendentes
-- dele, de qualquer tipo, ficam bloqueadas. Mensagem inexistente -> false.
create function public.mensagem_bloquear(p_mensagem uuid, p_origem text, p_agora timestamptz)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  m mensagens;
begin
  select * into m from mensagens where id = p_mensagem;
  if m.id is null then
    return false;
  end if;
  insert into mensagens_bloqueio (canal, contato, origem, criado_em)
  values (m.canal, m.destino, p_origem, p_agora)
  on conflict (canal, contato) do nothing;
  update mensagens set estado = 'bloqueada', atualizada_em = p_agora
   where canal = m.canal and destino = m.destino and estado = 'pendente'
     and (travada_ate is null or travada_ate <= p_agora);
  return true;
end;
$$;

-- (10) "Nao vou poder" (link do aviso de premio): a pessoa abre mao e o premio passa ao proximo
-- (premio_passar da NEU-167). Devolve 'recusado', 'ja_resolvido' (o premio nao vale mais:
-- clique repetido, prazo, entregue) ou 'invalido' (mensagem que nao e aviso de premio).
create function public.mensagem_recusar_premio(p_mensagem uuid, p_agora timestamptz)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  m        mensagens;
  v_status text;
begin
  select * into m from mensagens where id = p_mensagem;
  if m.id is null or m.premio_id is null or m.tipo not in ('premio_venceu', 'premio_lembrete') then
    return 'invalido';
  end if;
  select status into v_status from premios where id = m.premio_id;
  if v_status is null or v_status not in ('avisando', 'avisado', 'prazo_estourou', 'aviso_falhou') then
    return 'ja_resolvido';
  end if;
  perform premio_passar(m.premio_id, 'recusado', p_agora, 'vencedor (link do e-mail)', 'Nao vou poder');
  -- premio_passar confere o estado de novo com a trava: se outro passo chegou antes, nada mudou.
  select status into v_status from premios where id = m.premio_id;
  return case when v_status in ('recusado', 'sem_retirada') then 'recusado' else 'ja_resolvido' end;
end;
$$;

revoke all on function public.mensagens_preparar(text, timestamptz, int) from public, anon, authenticated;
revoke all on function public.mensagem_resultado(uuid, boolean, text, text, boolean, timestamptz)
  from public, anon, authenticated;
revoke all on function public.mensagem_bloquear(uuid, text, timestamptz) from public, anon, authenticated;
revoke all on function public.mensagem_recusar_premio(uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.mensagens_preparar(text, timestamptz, int) to service_role;
grant execute on function public.mensagem_resultado(uuid, boolean, text, text, boolean, timestamptz) to service_role;
grant execute on function public.mensagem_bloquear(uuid, text, timestamptz) to service_role;
grant execute on function public.mensagem_recusar_premio(uuid, timestamptz) to service_role;
