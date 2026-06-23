-- Alias do usuario (display_name unico) para o ranking. Aditivo; nao toca ingest/RLS atuais.
create extension if not exists citext with schema extensions;

create table public.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  display_name extensions.citext unique,
  created_at   timestamptz not null default now(),
  constraint display_name_valid check (
    display_name is null
    or (char_length(display_name::text) between 3 and 20
        and display_name::text = btrim(display_name::text))
  )
);

alter table public.profiles enable row level security;

-- Leitura/edicao SO do proprio profile. (A leitura publica do nome no ranking
-- e feita pela funcao get_leaderboard (security definer), nao por esta tabela.)
create policy profiles_select_own on public.profiles
  for select to authenticated using (id = (select auth.uid()));
create policy profiles_update_own on public.profiles
  for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));

grant select, update on public.profiles to authenticated;

-- Cria o profile (display_name NULL) no signup. SECURITY DEFINER pois roda no contexto de auth.users.
create or replace function public.handle_new_user_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id) values (new.id) on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created_profile
  after insert on auth.users
  for each row execute function public.handle_new_user_profile();
