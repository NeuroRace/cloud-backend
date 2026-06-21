create or replace function public.handle_email_confirmed()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.email_confirmed_at is not null and old.email_confirmed_at is null then
    insert into public.players (email, user_id)
    values (lower(trim(new.email)), new.id)
    on conflict (email) do update
      set user_id = excluded.user_id
      where players.user_id is null;
  end if;
  return new;
end;
$$;

create trigger on_auth_email_confirmed
  after update of email_confirmed_at on auth.users
  for each row
  execute function public.handle_email_confirmed();
