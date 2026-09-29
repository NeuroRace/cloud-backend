-- NEU-30: bot do Telegram que avisa o jogador. O Telegram só deixa o bot mandar mensagem para
-- quem deu "Iniciar" nele: no estande, a pessoa escaneia um QR (t.me/<bot>?start=estande), toca
-- Iniciar e informa o e-mail que usou no estande. O bot guarda chat ↔ e-mail aqui.
--
-- LGPD: ninguém prova no Telegram que é dono do e-mail digitado. Por isso o bot NÃO manda dados
-- da corrida (EEG, desempenho) — só avisos com link para o site, onde os dados ficam atrás do
-- login com e-mail confirmado. Os tipos de aviso permitidos estão travados em `kind`.
--
-- Acesso: só o bot (service_role, no servidor). O site (anon/authenticated) não lê nem escreve.

create table public.telegram_subscriptions (
  chat_id    bigint primary key,   -- id do chat privado no Telegram (passa do limite de int4)
  email      text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- Mesmo formato que o ingest grava em players.email (lower/trim): o bot normaliza antes.
  constraint telegram_subscriptions_email_normalized
    check (email = lower(btrim(email)) and email like '_%@_%')
);

comment on table public.telegram_subscriptions is
  'NEU-30: chat do Telegram ↔ e-mail do estande. Só service_role. O bot só manda avisos com link, nunca dados da corrida (LGPD). /parar = apagar a linha.';

-- O bot procura inscritos pelo e-mail das corridas novas.
create index telegram_subscriptions_email_idx on public.telegram_subscriptions (email);

-- Avisos já enviados: o bot grava ANTES de enviar (insert ... on conflict do nothing) e só
-- manda se a linha for nova. Assim o mesmo aviso não sai duas vezes, nem com o bot reiniciando.
create table public.telegram_notifications (
  chat_id bigint not null references public.telegram_subscriptions (chat_id) on delete cascade,
  kind    text   not null check (kind in ('race_registered', 'round_winner')),
  ref     uuid   not null,          -- race_players.id (race_registered) ou ranking_windows.id (round_winner)
  sent_at timestamptz not null default now(),
  primary key (chat_id, kind, ref)
);

comment on table public.telegram_notifications is
  'NEU-30: avisos do bot já enviados (idempotência). Só service_role.';

alter table public.telegram_subscriptions enable row level security;
alter table public.telegram_notifications enable row level security;

-- Sem policy: o site não acessa. O default-privileges do Supabase concede ALL (inclusive
-- TRUNCATE, que ignora RLS) a anon/authenticated em tabelas novas; aqui tiramos tudo.
revoke all on public.telegram_subscriptions from anon, authenticated;
revoke all on public.telegram_notifications from anon, authenticated;
grant select, insert, update, delete on public.telegram_subscriptions to service_role;
grant select, insert, update, delete on public.telegram_notifications to service_role;
