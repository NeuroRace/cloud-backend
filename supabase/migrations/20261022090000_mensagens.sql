-- NEU-112: caixa de saida das mensagens da premiacao e envio por e-mail (Brevo).
-- Peca nova e separada: nao toca em ingest_race, get_leaderboard, RLS nem tabelas existentes.
-- Le premios/premiacao_config da NEU-167 e chama premio_passar ("Nao vou poder").
-- Tudo nasce desligado (email_ligado = false, tipos_ligados vazio): sem ligar, nada sai.
-- Volta: supabase/rollbacks/20261022090000_mensagens.down.sql.

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

