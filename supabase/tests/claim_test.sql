\set ON_ERROR_STOP on
do $$
declare uid uuid := gen_random_uuid();
begin
  delete from players   where email='claim@test.com';
  delete from auth.users where email='claim@test.com';

  -- correu antes de ter conta: ja existe player por email
  insert into players (email) values ('claim@test.com') on conflict do nothing;

  -- signup NAO confirmado -> nao vincula
  insert into auth.users (instance_id, id, aud, role, email, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', uid,
          'authenticated','authenticated','claim@test.com', now(), now());
  assert (select user_id from players where email='claim@test.com') is null,
    'signup nao confirmado nao pode vincular';

  -- confirma email -> trigger vincula
  update auth.users set email_confirmed_at = now() where id = uid;
  assert (select user_id from players where email='claim@test.com') = uid,
    'email confirmado deve vincular player ao user';

  raise notice 'claim_test OK';
end $$;
