\set ON_ERROR_STOP on

-- NEU-110: tabela ranking_windows (rodadas do ranking).
-- Prova: offset -03 guardado em UTC; rodadas encostadas aceitas; sobreposicao,
-- fim <= inicio e nome vazio rejeitados; anon/authenticated so leem (nem
-- insert/update/delete/truncate). Limpa o proprio seed.

delete from public.ranking_windows where name like 'NEU110-T %';

-- como postgres (dono): R1 e R2 encostadas, cadastradas no horario de Sao Paulo
insert into public.ranking_windows (id, name, starts_at, ends_at) values
 ('5e000000-0000-0000-0000-000000000001','NEU110-T R1','2031-03-15 07:00-03','2031-03-15 09:00-03'),
 ('5e000000-0000-0000-0000-000000000002','NEU110-T R2','2031-03-15 09:00-03','2031-03-15 11:00-03');

do $$
declare ok boolean;
begin
  assert (select starts_at from public.ranking_windows where id = '5e000000-0000-0000-0000-000000000001')
         = '2031-03-15 10:00+00'::timestamptz,
    'R1 cadastrada como 07:00-03 deve comecar 10:00 UTC';

  ok := false;
  begin
    insert into public.ranking_windows (name, starts_at, ends_at)
    values ('NEU110-T sobreposta', '2031-03-15 11:30+00', '2031-03-15 12:30+00');
  exception when exclusion_violation then ok := true;
  end;
  assert ok, 'rodada sobreposta deve ser rejeitada (exclusion_violation)';

  ok := false;
  begin
    insert into public.ranking_windows (name, starts_at, ends_at)
    values ('NEU110-T vazia', '2031-03-16 10:00+00', '2031-03-16 10:00+00');
  exception when check_violation then ok := true;
  end;
  assert ok, 'ends_at <= starts_at deve ser rejeitado (check_violation)';

  ok := false;
  begin
    insert into public.ranking_windows (name, starts_at, ends_at)
    values ('   ', '2031-03-17 10:00+00', '2031-03-17 12:00+00');
  exception when check_violation then ok := true;
  end;
  assert ok, 'nome vazio deve ser rejeitado (check_violation)';
end $$;

-- anon e authenticated: leem, nao escrevem
begin;
set local role anon;
do $$
declare ok boolean;
begin
  assert (select count(*) from public.ranking_windows where name like 'NEU110-T %') = 2,
    'anon deve ler as 2 rodadas';

  ok := false;
  begin
    insert into public.ranking_windows (name, starts_at, ends_at)
    values ('NEU110-T anon', '2031-04-01 10:00+00', '2031-04-01 12:00+00');
  exception when insufficient_privilege then ok := true;
  end;
  assert ok, 'anon NAO pode inserir';

  ok := false;
  begin update public.ranking_windows set name = 'NEU110-T x' where name like 'NEU110-T %';
  exception when insufficient_privilege then ok := true;
  end;
  assert ok, 'anon NAO pode atualizar';

  ok := false;
  begin delete from public.ranking_windows where name like 'NEU110-T %';
  exception when insufficient_privilege then ok := true;
  end;
  assert ok, 'anon NAO pode apagar';

  ok := false;
  begin truncate public.ranking_windows;
  exception when insufficient_privilege then ok := true;
  end;
  assert ok, 'anon NAO pode truncar (TRUNCATE ignora RLS)';
end $$;
commit;

begin;
set local role authenticated;
do $$
declare ok boolean;
begin
  assert (select count(*) from public.ranking_windows where name like 'NEU110-T %') = 2,
    'authenticated deve ler as 2 rodadas';

  ok := false;
  begin
    insert into public.ranking_windows (name, starts_at, ends_at)
    values ('NEU110-T auth', '2031-04-02 10:00+00', '2031-04-02 12:00+00');
  exception when insufficient_privilege then ok := true;
  end;
  assert ok, 'authenticated NAO pode inserir';

  ok := false;
  begin truncate public.ranking_windows;
  exception when insufficient_privilege then ok := true;
  end;
  assert ok, 'authenticated NAO pode truncar';
end $$;
commit;

-- o seed continua intacto depois das tentativas
do $$
begin
  assert (select count(*) from public.ranking_windows where name like 'NEU110-T %') = 2,
    'as tentativas de escrita nao podem ter alterado as rodadas';
end $$;

-- Quem cadastra pelo SQL editor (sessao em UTC) precisa ver que o horario leva offset;
-- sem ele, '14:00' vira 11:00 em Sao Paulo. O comentario da coluna aparece no editor.
do $$
begin
  assert col_description('public.ranking_windows'::regclass, 3) like '%-03%',
    'starts_at deve ter comentario orientando o offset -03';
  assert col_description('public.ranking_windows'::regclass, 4) like '%-03%',
    'ends_at deve ter comentario orientando o offset -03';
end $$;

delete from public.ranking_windows where name like 'NEU110-T %';
select 'ranking_windows_test OK' as result;
