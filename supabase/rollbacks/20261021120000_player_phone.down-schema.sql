-- Volta da NEU-159, parte B: desfaz o schema. Passo 4 da ordem que esta no topo de
-- 20261021120000_player_phone.down.sql: so depois da parte A, e so com 0 jogadores de
-- celular e 0 contas com 2 jogadores. Se houver, para com erro de proposito e nada muda.
--   psql "$DB" -v ON_ERROR_STOP=1 -1 -f supabase/rollbacks/20261021120000_player_phone.down-schema.sql

do $$ begin
  if exists (select 1 from public.players where phone is not null) then
    raise exception 'ha jogador com celular: o schema fica (a parte A ja basta)';
  end if;
  if exists (select 1 from public.players where user_id is not null group by user_id having count(*) > 1) then
    raise exception 'ha conta com 2 jogadores: a trava uma conta, um jogador nao volta';
  end if;
end $$;
drop index if exists public.players_user_id_idx;
alter table public.players add constraint players_user_id_key unique (user_id);
alter table public.players drop constraint players_email_or_phone;
alter table public.players alter column email set not null;
alter table public.players drop column phone;
