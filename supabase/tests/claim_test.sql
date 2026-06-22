\set ON_ERROR_STOP on
do $$
declare
  uid  uuid := gen_random_uuid();
  uid2 uuid := gen_random_uuid();
  uid3 uuid := gen_random_uuid();
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

  -- normalizacao: email mixed-case+espacos do signup deve casar o player normalizado
  delete from players   where email='mixed@test.com';
  delete from auth.users where email ilike '%mixed@test.com%';
  insert into players (email) values ('mixed@test.com') on conflict do nothing;
  insert into auth.users (instance_id, id, aud, role, email, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', uid2,
          'authenticated','authenticated','  Mixed@Test.com ', now(), now());
  update auth.users set email_confirmed_at = now() where id = uid2;
  assert (select user_id from players where email='mixed@test.com') = uid2,
    'email mixed-case+espacos deve vincular o player normalizado';
  assert (select count(*) from players where lower(trim(email))='mixed@test.com') = 1,
    'normalizacao nao deve criar player duplicado';

  -- anti-roubo: 2o usuario confirmando o mesmo email NAO rouba vinculo existente
  insert into auth.users (instance_id, id, aud, role, email, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', uid3,
          'authenticated','authenticated','mixed@test.com', now(), now());
  update auth.users set email_confirmed_at = now() where id = uid3;
  assert (select user_id from players where email='mixed@test.com') = uid2,
    'segundo usuario nao pode roubar vinculo ja existente';

  raise notice 'claim_test OK';
end $$;
