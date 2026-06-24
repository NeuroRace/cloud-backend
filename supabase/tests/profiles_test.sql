\set ON_ERROR_STOP on

-- estrutura + unicidade citext + CHECK (seed como superuser, bypassa RLS)
begin;
delete from public.profiles where id in ('aaaaaaaa-1111-1111-1111-111111111111','bbbbbbbb-2222-2222-2222-222222222222');
delete from auth.users where email in ('prof_a@test.com','prof_b@test.com');
insert into auth.users (instance_id, id, aud, role, email, created_at, updated_at) values
  ('00000000-0000-0000-0000-000000000000','aaaaaaaa-1111-1111-1111-111111111111','authenticated','authenticated','prof_a@test.com',now(),now()),
  ('00000000-0000-0000-0000-000000000000','bbbbbbbb-2222-2222-2222-222222222222','authenticated','authenticated','prof_b@test.com',now(),now());

do $$ begin
  -- trigger criou os profiles automaticamente (display_name NULL)
  assert (select count(*) from public.profiles where id='aaaaaaaa-1111-1111-1111-111111111111') = 1, 'trigger deve criar profile no signup';
  assert (select display_name from public.profiles where id='aaaaaaaa-1111-1111-1111-111111111111') is null, 'display_name comeca NULL';
end $$;

-- seta nome do A
update public.profiles set display_name='Alice' where id='aaaaaaaa-1111-1111-1111-111111111111';

-- unicidade case-insensitive: B nao pode usar 'alice'
do $$
declare ok boolean := false;
begin
  begin
    update public.profiles set display_name='alice' where id='bbbbbbbb-2222-2222-2222-222222222222';
  exception when unique_violation then ok := true;
  end;
  assert ok, 'display_name deve ser unico case-insensitive (citext): alice == Alice';
end $$;

-- CHECK: 2 chars falha; 21 chars falha; espaco nas pontas falha
do $$
declare bad int := 0;
begin
  begin update public.profiles set display_name='ab' where id='bbbbbbbb-2222-2222-2222-222222222222'; exception when check_violation then bad:=bad+1; end;
  begin update public.profiles set display_name=repeat('x',21) where id='bbbbbbbb-2222-2222-2222-222222222222'; exception when check_violation then bad:=bad+1; end;
  begin update public.profiles set display_name=' Bob' where id='bbbbbbbb-2222-2222-2222-222222222222'; exception when check_violation then bad:=bad+1; end;
  assert bad = 3, 'CHECK deve rejeitar <3, >20 e espaco nas pontas (esperado 3 rejeicoes, veio '||bad||')';
end $$;
rollback;

-- Re-seed para o bloco de RLS (o rollback acima apagou A e B)
delete from public.profiles where id in ('aaaaaaaa-1111-1111-1111-111111111111','bbbbbbbb-2222-2222-2222-222222222222');
delete from auth.users where email in ('prof_a@test.com','prof_b@test.com');
insert into auth.users (instance_id, id, aud, role, email, created_at, updated_at) values
  ('00000000-0000-0000-0000-000000000000','aaaaaaaa-1111-1111-1111-111111111111','authenticated','authenticated','prof_a@test.com',now(),now()),
  ('00000000-0000-0000-0000-000000000000','bbbbbbbb-2222-2222-2222-222222222222','authenticated','authenticated','prof_b@test.com',now(),now());

-- RLS: cada um so edita o seu
-- (D) garante que B tem nome conhecido antes do bloco RLS
update public.profiles set display_name='Bob' where id='bbbbbbbb-2222-2222-2222-222222222222';

begin;
set local role authenticated;
set local request.jwt.claims to '{"sub":"aaaaaaaa-1111-1111-1111-111111111111","role":"authenticated"}';
do $$ begin
  assert (select count(*) from public.profiles) = 1, 'A so enxerga o proprio profile (RLS select own)';
  assert (select count(*) from public.profiles where id='aaaaaaaa-1111-1111-1111-111111111111') = 1, 'A enxerga o seu';
end $$;
-- (D) A edita o PROPRIO profile (caminho feliz da feature)
update public.profiles set display_name='AliceOk' where id='aaaaaaaa-1111-1111-1111-111111111111';
-- A tenta editar o profile do B -> nao afeta nenhuma linha (RLS update own)
update public.profiles set display_name='Hacker' where id='bbbbbbbb-2222-2222-2222-222222222222';
commit;
do $$ begin
  -- (D) A conseguiu editar o proprio
  assert (select display_name from public.profiles where id='aaaaaaaa-1111-1111-1111-111111111111') = 'AliceOk', 'A deve poder editar o proprio profile';
  -- (E) B mantem o valor exato 'Bob', nao so "diferente de Hacker"
  assert (select display_name from public.profiles where id='bbbbbbbb-2222-2222-2222-222222222222') = 'Bob', 'A nao pode editar o profile do B (B deve manter Bob)';
end $$;

-- (I2) anon nao le profiles direto (so via get_leaderboard)
begin;
set local role anon;
do $$ declare denied boolean := false; begin
  begin
    perform 1 from public.profiles;
  exception when insufficient_privilege then
    denied := true;
  end;
  assert denied, 'anon NAO pode ler profiles direto (so via get_leaderboard)';
end $$;
commit;

-- limpeza
delete from public.profiles where id in ('aaaaaaaa-1111-1111-1111-111111111111','bbbbbbbb-2222-2222-2222-222222222222');
delete from auth.users where email in ('prof_a@test.com','prof_b@test.com');
select 'profiles_test OK' as result;
