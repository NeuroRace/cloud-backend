# Ranking por rodada (NEU-110) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Adicionar rodadas (`ranking_windows`) e filtro de período + desempate "quem fez primeiro" ao `get_leaderboard`, no contrato que o web PR #11 já consome.

**Architecture:** Uma migration aditiva no Supabase (Postgres 17): tabela `ranking_windows` com leitura pública via RLS e escrita só por SQL/`service_role`; `get_leaderboard(text,int)` é substituída por `get_leaderboard(text,int,timestamptz,timestamptz)` com defaults, na mesma migration. Testes SQL com `assert` rodam contra o Supabase local.

**Tech Stack:** Supabase CLI 2.109.0 (via `npx`), Postgres 17, Docker, psql (dentro do container), SQL/PLpgSQL.

**Spec:** `docs/superpowers/specs/2026-09-28-ranking-por-rodada-design.md`

## Global Constraints

- Contrato fixo (web PR #11): tabela `ranking_windows(id, name, starts_at, ends_at)`; `get_leaderboard(p_metric, p_limit, p_from, p_to)`, `p_from`/`p_to` opcionais.
- Retorno de `get_leaderboard` é **exatamente** `rank, display_name, score` (sem PII).
- Continua valendo: só quem tem apelido, só `source = 'real'`, ignora `finished_at` nulo e duração ≤ 0, `p_limit` entre 1 e 1000, métrica desconhecida → vazio.
- Período por `finished_at`, meio-aberto: `finished_at >= p_from` e `finished_at < p_to`; `null` = sem limite daquele lado.
- Desempate: melhor corrida = menor duração, empate na duração → a que terminou primeiro; `rank() over (order by score, achieved_at)`; ordenação final `score, achieved_at, display_name`.
- Existe **uma** função `public.get_leaderboard` (a de `(text, int)` é removida).
- Escrita em `ranking_windows` só por SQL/`service_role`; `anon`/`authenticated` só leem.
- Migrations são aditivas; esta pode ser editada in-place enquanto o PR não for mergeado/deployado.
- Não tocar produção sem ok explícito do Nikolas (Task 5).
- Commits terminam com `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **PostgREST com a chamada antiga** (`{p_metric, p_limit}` sem período) tem que resolver para a função nova sem "could not choose the best candidate function" → Task 3, Step 3 (curl local).
2. **Rodada cadastrada com offset `-03`** tem que casar com `finished_at` em UTC → Task 1, Step 1 (assert de `starts_at = 10:00 UTC`) e Task 2 (rodadas do seed usam `-03`).
3. **`TRUNCATE` por `anon`/`authenticated`** ignora RLS; o default-privileges do Supabase concede `TRUNCATE` → Task 1 revoga e testa.
4. **`p_from > p_to`** devolve vazio, sem erro → Task 2, Step 1.
5. **Corrida não terminada ou de bot dentro da rodada** não entra → Task 2, Step 1 (Ana sem `finished_at` e Duda bot em R2).

## Arquivos

- Create: `supabase/migrations/20260928120000_ranking_windows.sql` — tabela + RLS + grants (Task 1) e troca da `get_leaderboard` (Task 2).
- Create: `supabase/tests/ranking_windows_test.sql` — tabela: constraints, RLS, grants (Task 1).
- Create: `supabase/tests/leaderboard_windows_test.sql` — função: período, desempate, compatibilidade (Task 2).
  (A spec §6 previa um arquivo só; dividido em dois para cada task ter o seu teste.)
- Modify: `supabase/types/database.types.ts` — regenerado (Task 3).
- Modify: `docs/frontend-integration.md` §8 (Task 3).
- Modify: `CLAUDE.md` — resumo de arquitetura e estado verde (Task 3).

## Como rodar (Windows + Git Bash; sem `psql`/`supabase` instalados)

```bash
# sobe o stack local (Docker precisa estar de pé) e aplica as migrations do zero
npx --yes supabase@2.109.0 start
npx --yes supabase@2.109.0 db reset

# roda UM teste SQL (psql dentro do container do banco)
docker exec -i supabase_db_cloud-backend psql -U postgres -v ON_ERROR_STOP=1 < supabase/tests/<arquivo>.sql

# roda a suíte SQL inteira
for f in supabase/tests/*.sql; do echo "== $f =="; docker exec -i supabase_db_cloud-backend psql -U postgres -v ON_ERROR_STOP=1 < "$f" || break; done

# função Deno
deno test supabase/functions/ingest-race/
```

---

### Task 0: Baseline verde

**Files:** nenhum.

- [ ] **Step 1: Subir o Supabase local e aplicar as migrations**

Run: `npx --yes supabase@2.109.0 start && npx --yes supabase@2.109.0 db reset`
Expected: termina sem erro; `docker ps` mostra `supabase_db_cloud-backend`.

- [ ] **Step 2: Rodar a suíte SQL e o Deno**

Run: o loop da seção "Como rodar" e `deno test supabase/functions/ingest-race/`
Expected: 7 linhas `... OK` (claim, ingest_race, leaderboard_bots, leaderboard, profiles, rls_read, schema) e `31 passed | 0 failed`. Se não bater, **pare** e reporte antes de mexer em qualquer coisa.

- [ ] **Step 3: Marcar a NEU-110 como In Progress no Linear**

---

### Task 1: Tabela `ranking_windows`

**Files:**
- Create: `supabase/tests/ranking_windows_test.sql`
- Create: `supabase/migrations/20260928120000_ranking_windows.sql`

**Interfaces:**
- Produces: tabela `public.ranking_windows(id uuid, name text, starts_at timestamptz, ends_at timestamptz, created_at timestamptz)`; `select` para `anon`/`authenticated`; DML completo para `service_role`.

- [ ] **Step 1: Escrever o teste que falha**

`supabase/tests/ranking_windows_test.sql`:

```sql
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

delete from public.ranking_windows where name like 'NEU110-T %';
select 'ranking_windows_test OK' as result;
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `docker exec -i supabase_db_cloud-backend psql -U postgres -v ON_ERROR_STOP=1 < supabase/tests/ranking_windows_test.sql`
Expected: FAIL com `relation "public.ranking_windows" does not exist`.

- [ ] **Step 3: Implementar (parte 1 da migration)**

`supabase/migrations/20260928120000_ranking_windows.sql`:

```sql
-- NEU-110: ranking por rodada (parte da NEU-89).
-- (1) ranking_windows: rodadas do evento. Leitura publica (o site le para montar as
--     abas Evento / Rodada atual e o telao); escrita so por SQL/service_role ate o
--     painel de operacao (NEU-114). Sem sobreposicao, garantido no banco: hoje as
--     rodadas sao editadas a mao.
-- (2) get_leaderboard ganha filtro de periodo e desempate por quem fez primeiro.
-- Contrato consumido pelo web PR #11 (NEU-111). Spec:
-- docs/superpowers/specs/2026-09-28-ranking-por-rodada-design.md

create table public.ranking_windows (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (char_length(btrim(name)) between 1 and 60),
  starts_at  timestamptz not null,
  ends_at    timestamptz not null,
  created_at timestamptz not null default now(),
  constraint ranking_windows_valid_range check (ends_at > starts_at),
  -- '[)' permite rodadas encostadas (fim de uma = inicio da outra). GiST de range e
  -- nativo; nao precisa de btree_gist.
  constraint ranking_windows_no_overlap
    exclude using gist (tstzrange(starts_at, ends_at, '[)') with &&)
);

alter table public.ranking_windows enable row level security;

create policy ranking_windows_select_public on public.ranking_windows
  for select to anon, authenticated using (true);

-- O default-privileges do Supabase concede ALL (inclusive TRUNCATE, que ignora RLS)
-- a anon/authenticated em tabelas novas do public. Aqui eles so leem.
revoke all on public.ranking_windows from anon, authenticated;
grant select on public.ranking_windows to anon, authenticated;
grant select, insert, update, delete on public.ranking_windows to service_role;
```

- [ ] **Step 4: Aplicar e ver passar**

Run: `npx --yes supabase@2.109.0 db reset` e depois o comando do Step 2.
Expected: última linha `ranking_windows_test OK`.

- [ ] **Step 5: Não-regressão**

Run: o loop da suíte SQL inteira.
Expected: 8 linhas `... OK` (as 7 do baseline + `ranking_windows_test`).

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/20260928120000_ranking_windows.sql supabase/tests/ranking_windows_test.sql
git commit -F - <<'EOF'
feat(db): tabela ranking_windows — rodadas com leitura publica e sem sobreposicao [NEU-110]

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 2: `get_leaderboard` com período e desempate

**Files:**
- Create: `supabase/tests/leaderboard_windows_test.sql`
- Modify: `supabase/migrations/20260928120000_ranking_windows.sql` (acrescentar ao fim)

**Interfaces:**
- Consumes: nada da Task 1 em SQL (o filtro recebe datas, não lê a tabela); só a mesma migration.
- Produces: `public.get_leaderboard(p_metric text default 'best_time', p_limit int default 50, p_from timestamptz default null, p_to timestamptz default null) returns table (rank int, display_name text, score numeric)` — única sobrecarga; `execute` para `anon`/`authenticated`.

- [ ] **Step 1: Escrever o teste que falha**

`supabase/tests/leaderboard_windows_test.sql`:

```sql
\set ON_ERROR_STOP on

-- NEU-110: get_leaderboard com periodo (p_from/p_to) e desempate por quem fez primeiro.
-- Seed deterministico em 2031-03-15 (UTC). Rodadas: R1 [10:00,12:00), R2 [12:00,14:00).
--   Ana : 30s terminou 10:10 (R1); 30s terminou 11:50 (R1); comecou 12:10 e NAO terminou (R2)
--   Bia : 30s terminou 11:00 (R1)
--   Caio: 20s terminou 12:00:00 exato (R2, fronteira); 50s terminou 13:00 (R2)
--   Duda: 25s terminou 13:30 (R2); 15s terminou 09:00 (antes do evento); 5s BOT terminou 12:30 (R2)
-- Esperado:
--   R1     : Ana 30 (rank 1, fez primeiro), Bia 30 (rank 2)
--   R2     : Caio 20 (rank 1), Duda 25 (rank 2)   [sem Ana nao-terminada, sem bot]
--   Evento (p_from=10:00): Caio 20, Duda 25, Ana 30, Bia 30 (ranks 1..4)
--   Geral  (sem periodo) : Duda 15 na frente de Caio 20

begin;
delete from race_players where id::text like '5d000000-%';
delete from races        where id::text like '5c000000-%';
delete from players      where id::text like '5b000000-%';
delete from auth.users   where email like 'lbw\_%@neu110.test';

insert into auth.users (instance_id, id, aud, role, email, created_at, updated_at) values
 ('00000000-0000-0000-0000-000000000000','5a000000-0000-0000-0000-000000000001','authenticated','authenticated','lbw_ana@neu110.test', '2031-01-01 00:00+00','2031-01-01 00:00+00'),
 ('00000000-0000-0000-0000-000000000000','5a000000-0000-0000-0000-000000000002','authenticated','authenticated','lbw_bia@neu110.test', '2031-01-01 00:00+00','2031-01-01 00:00+00'),
 ('00000000-0000-0000-0000-000000000000','5a000000-0000-0000-0000-000000000003','authenticated','authenticated','lbw_caio@neu110.test','2031-01-01 00:00+00','2031-01-01 00:00+00'),
 ('00000000-0000-0000-0000-000000000000','5a000000-0000-0000-0000-000000000004','authenticated','authenticated','lbw_duda@neu110.test','2031-01-01 00:00+00','2031-01-01 00:00+00');
-- o trigger handle_new_user_profile cria os profiles; damos os apelidos
update public.profiles set display_name = 'W110Ana'  where id = '5a000000-0000-0000-0000-000000000001';
update public.profiles set display_name = 'W110Bia'  where id = '5a000000-0000-0000-0000-000000000002';
update public.profiles set display_name = 'W110Caio' where id = '5a000000-0000-0000-0000-000000000003';
update public.profiles set display_name = 'W110Duda' where id = '5a000000-0000-0000-0000-000000000004';

insert into players (id, email, user_id) values
 ('5b000000-0000-0000-0000-000000000001','lbw_ana@neu110.test', '5a000000-0000-0000-0000-000000000001'),
 ('5b000000-0000-0000-0000-000000000002','lbw_bia@neu110.test', '5a000000-0000-0000-0000-000000000002'),
 ('5b000000-0000-0000-0000-000000000003','lbw_caio@neu110.test','5a000000-0000-0000-0000-000000000003'),
 ('5b000000-0000-0000-0000-000000000004','lbw_duda@neu110.test','5a000000-0000-0000-0000-000000000004');

insert into races (id, started_at) values
 ('5c000000-0000-0000-0000-000000000001','2031-03-15 10:09:30+00'),
 ('5c000000-0000-0000-0000-000000000002','2031-03-15 11:49:30+00'),
 ('5c000000-0000-0000-0000-000000000003','2031-03-15 10:59:30+00'),
 ('5c000000-0000-0000-0000-000000000004','2031-03-15 11:59:40+00'),
 ('5c000000-0000-0000-0000-000000000005','2031-03-15 12:59:10+00'),
 ('5c000000-0000-0000-0000-000000000006','2031-03-15 13:29:35+00'),
 ('5c000000-0000-0000-0000-000000000007','2031-03-15 08:59:45+00'),
 ('5c000000-0000-0000-0000-000000000008','2031-03-15 12:29:55+00'),
 ('5c000000-0000-0000-0000-000000000009','2031-03-15 12:10:00+00');

-- (id, idempotency_key, race_id, player_id, slot, started_at, finished_at, source)
insert into race_players (id, idempotency_key, race_id, player_id, player_slot, started_at, finished_at, source) values
 ('5d000000-0000-0000-0000-000000000001', gen_random_uuid(), '5c000000-0000-0000-0000-000000000001','5b000000-0000-0000-0000-000000000001',1,'2031-03-15 10:09:30+00','2031-03-15 10:10:00+00','real'),
 ('5d000000-0000-0000-0000-000000000002', gen_random_uuid(), '5c000000-0000-0000-0000-000000000002','5b000000-0000-0000-0000-000000000001',1,'2031-03-15 11:49:30+00','2031-03-15 11:50:00+00','real'),
 ('5d000000-0000-0000-0000-000000000003', gen_random_uuid(), '5c000000-0000-0000-0000-000000000003','5b000000-0000-0000-0000-000000000002',1,'2031-03-15 10:59:30+00','2031-03-15 11:00:00+00','real'),
 ('5d000000-0000-0000-0000-000000000004', gen_random_uuid(), '5c000000-0000-0000-0000-000000000004','5b000000-0000-0000-0000-000000000003',1,'2031-03-15 11:59:40+00','2031-03-15 12:00:00+00','real'),
 ('5d000000-0000-0000-0000-000000000005', gen_random_uuid(), '5c000000-0000-0000-0000-000000000005','5b000000-0000-0000-0000-000000000003',1,'2031-03-15 12:59:10+00','2031-03-15 13:00:00+00','real'),
 ('5d000000-0000-0000-0000-000000000006', gen_random_uuid(), '5c000000-0000-0000-0000-000000000006','5b000000-0000-0000-0000-000000000004',1,'2031-03-15 13:29:35+00','2031-03-15 13:30:00+00','real'),
 ('5d000000-0000-0000-0000-000000000007', gen_random_uuid(), '5c000000-0000-0000-0000-000000000007','5b000000-0000-0000-0000-000000000004',1,'2031-03-15 08:59:45+00','2031-03-15 09:00:00+00','real'),
 ('5d000000-0000-0000-0000-000000000008', gen_random_uuid(), '5c000000-0000-0000-0000-000000000008','5b000000-0000-0000-0000-000000000004',1,'2031-03-15 12:29:55+00','2031-03-15 12:30:00+00','bot'),
 ('5d000000-0000-0000-0000-000000000009', gen_random_uuid(), '5c000000-0000-0000-0000-000000000009','5b000000-0000-0000-0000-000000000001',1,'2031-03-15 12:10:00+00',null,'real');
commit;

-- chamadas como ANON (ranking publico). Rodadas escritas com offset -03, como o operador cadastra.
begin;
set local role anon;
do $$
declare
  r1_from constant timestamptz := '2031-03-15 07:00-03';
  r1_to   constant timestamptz := '2031-03-15 09:00-03';
  r2_from constant timestamptz := '2031-03-15 09:00-03';
  r2_to   constant timestamptz := '2031-03-15 11:00-03';
  names   text;
  ranks   text;
begin
  -- R1: Ana e Bia empatam em 30s; Ana fez primeiro (10:10 < 11:00) -> rank 1 e 2, distintos
  select string_agg(display_name, ',' order by rank, display_name),
         string_agg(rank::text || ':' || score::int, ',' order by rank, display_name)
    into names, ranks
    from get_leaderboard('best_time', 50, r1_from, r1_to);
  assert names = 'W110Ana,W110Bia', 'R1 deve ser Ana,Bia. veio '||coalesce(names,'NULL');
  assert ranks = '1:30,2:30', 'R1: empate de 30s resolvido por quem fez primeiro (1:30,2:30). veio '||coalesce(ranks,'NULL');

  -- R2: Caio 20 (terminou 12:00:00 exato -> entra em R2), Duda 25.
  -- Sem Ana (nao terminou), sem o bot de 5s da Duda, sem os 50s do Caio (vale o melhor).
  select string_agg(display_name, ',' order by rank, display_name),
         string_agg(rank::text || ':' || score::int, ',' order by rank, display_name)
    into names, ranks
    from get_leaderboard('best_time', 50, r2_from, r2_to);
  assert names = 'W110Caio,W110Duda', 'R2 deve ser Caio,Duda. veio '||coalesce(names,'NULL');
  assert ranks = '1:20,2:25', 'R2 deve ser 1:20,2:25. veio '||coalesce(ranks,'NULL');

  -- Fronteira: Caio (12:00:00) NAO entra em R1
  assert (select count(*) from get_leaderboard('best_time', 50, r1_from, r1_to) where display_name = 'W110Caio') = 0,
    'corrida terminada exatamente em ends_at nao pode entrar na rodada que acaba';

  -- Evento (so p_from, como o site faz): ignora os 15s da Duda (09:00, antes do evento)
  select string_agg(display_name, ',' order by rank, display_name),
         string_agg(rank::text || ':' || score::int, ',' order by rank, display_name)
    into names, ranks
    from get_leaderboard('best_time', 50, r1_from);
  assert names = 'W110Caio,W110Duda,W110Ana,W110Bia', 'Evento deve ser Caio,Duda,Ana,Bia. veio '||coalesce(names,'NULL');
  assert ranks = '1:20,2:25,3:30,4:30', 'Evento deve ser 1:20,2:25,3:30,4:30. veio '||coalesce(ranks,'NULL');

  -- p_from > p_to: vazio, sem erro
  assert (select count(*) from get_leaderboard('best_time', 50, r2_to, r1_from)) = 0,
    'p_from > p_to deve devolver vazio';

  -- Chamada antiga (posicional, 2 args): ranking geral, conta os 15s da Duda
  assert (select score from get_leaderboard('best_time', 1000) where display_name = 'W110Duda') = 15,
    'sem periodo, Duda deve ter 15s (melhor de sempre)';
  assert (select rank from get_leaderboard('best_time', 1000) where display_name = 'W110Duda')
       < (select rank from get_leaderboard('best_time', 1000) where display_name = 'W110Caio'),
    'sem periodo, Duda (15s) fica na frente de Caio (20s)';

  -- Chamada com nomes, como o PostgREST/supabase-js faz
  assert (select count(*) from get_leaderboard(p_metric => 'best_time', p_limit => 1000) where display_name like 'W110%') = 4,
    'chamada nomeada sem periodo deve devolver os 4 jogadores';

  -- metrica desconhecida continua vazia, mesmo com periodo
  assert (select count(*) from get_leaderboard('xxx', 50, r1_from, r2_to)) = 0, 'metrica desconhecida -> vazio';
end $$;
commit;

-- uma unica sobrecarga (senao o PostgREST nao escolhe entre elas)
do $$
begin
  assert (select count(*) from pg_proc
          where proname = 'get_leaderboard' and pronamespace = 'public'::regnamespace) = 1,
    'deve existir exatamente uma public.get_leaderboard';
end $$;

-- limpeza
delete from race_players where id::text like '5d000000-%';
delete from races        where id::text like '5c000000-%';
delete from players      where id::text like '5b000000-%';
delete from auth.users   where email like 'lbw\_%@neu110.test';
select 'leaderboard_windows_test OK' as result;
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `docker exec -i supabase_db_cloud-backend psql -U postgres -v ON_ERROR_STOP=1 < supabase/tests/leaderboard_windows_test.sql`
Expected: FAIL com `function get_leaderboard(..., timestamp with time zone, timestamp with time zone) does not exist` (a versão de 2 argumentos não aceita período).

- [ ] **Step 3: Implementar (acrescentar ao fim da migration)**

```sql
-- (2) get_leaderboard: periodo por finished_at, meio-aberto [p_from, p_to); null = sem
-- limite daquele lado. Desempate: para cada pessoa vale a menor duracao e, empatando,
-- a que terminou primeiro; o rank ordena por (score, achieved_at). Mantem: sem PII,
-- so quem tem apelido, so source='real', so corrida terminada com duracao > 0.
-- A versao (text, int) sai: duas sobrecargas deixariam o PostgREST sem saber qual
-- chamar para {p_metric, p_limit}.
drop function if exists public.get_leaderboard(text, int);

create function public.get_leaderboard(
  p_metric text        default 'best_time',
  p_limit  int         default 50,
  p_from   timestamptz default null,
  p_to     timestamptz default null
)
returns table (rank int, display_name text, score numeric)
language sql
stable
security definer
set search_path = public
as $$
  select (rank() over (order by b.score asc, b.achieved_at asc))::int as rank,
         b.display_name,
         b.score
  from (
    select distinct on (pr.id)
           pr.display_name::text as display_name,
           extract(epoch from (rp.finished_at - rp.started_at))::numeric as score,
           rp.finished_at as achieved_at
    from profiles pr
    join players p       on p.user_id = pr.id
    join race_players rp on rp.player_id = p.id
    where p_metric = 'best_time'          -- unica metrica por enquanto (NEU-67 estende)
      and pr.display_name is not null     -- so quem tem apelido
      and rp.source = 'real'              -- defesa-em-profundidade: ignora bot
      and rp.finished_at is not null      -- ignora corrida nao terminada
      and rp.finished_at > rp.started_at
      and (p_from is null or rp.finished_at >= p_from)
      and (p_to   is null or rp.finished_at <  p_to)
    order by pr.id, (rp.finished_at - rp.started_at) asc, rp.finished_at asc
  ) b
  order by b.score asc, b.achieved_at asc, b.display_name asc
  limit least(greatest(p_limit, 1), 1000);
$$;

revoke all on function public.get_leaderboard(text, int, timestamptz, timestamptz) from public;
grant execute on function public.get_leaderboard(text, int, timestamptz, timestamptz) to anon, authenticated;
```

- [ ] **Step 4: Aplicar e ver passar**

Run: `npx --yes supabase@2.109.0 db reset` e depois o comando do Step 2.
Expected: última linha `leaderboard_windows_test OK`.

- [ ] **Step 5: Não-regressão (sem editar os testes antigos)**

Run: o loop da suíte SQL inteira.
Expected: 9 linhas `... OK`, incluindo `leaderboard_test OK` (Bob/Dave seguem empatados no rank 1: mesmo `finished_at`) e `leaderboard_bots_test OK`.

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/20260928120000_ranking_windows.sql supabase/tests/leaderboard_windows_test.sql
git commit -F - <<'EOF'
feat(db): get_leaderboard com periodo (p_from/p_to) e desempate por quem fez primeiro [NEU-110]

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 3: Contrato publicado — types, docs e prova via PostgREST local

**Files:**
- Modify: `supabase/types/database.types.ts`
- Modify: `docs/frontend-integration.md` (§8)
- Modify: `CLAUDE.md` (seção "Arquitetura" e "Estado verde de referência")

**Interfaces:**
- Consumes: tabela da Task 1 e função da Task 2.
- Produces: `Database["public"]["Tables"]["ranking_windows"]` e `Database["public"]["Functions"]["get_leaderboard"]["Args"] = { p_from?: string; p_limit?: number; p_metric?: string; p_to?: string }` (mesma forma que o web PR #11 escreveu à mão).

- [ ] **Step 1: Regenerar os types**

Run: `npx --yes supabase@2.109.0 gen types typescript --local > supabase/types/database.types.ts && git diff --stat supabase/types/database.types.ts`
Expected: o diff só acrescenta `ranking_windows` e `p_from`/`p_to` em `get_leaderboard.Args`. Se aparecer qualquer outra mudança (ex.: formato do gerador), compare com o web PR #11 e reporte antes de seguir.

- [ ] **Step 2: Provar a chamada antiga pelo PostgREST local (Review Focus 1)**

```bash
eval "$(npx --yes supabase@2.109.0 status -o env | grep -E '^(API_URL|ANON_KEY)=')"
# chamada de hoje do site: tem que dar 200 (nao 300 "could not choose the best candidate function")
curl -s -w "\nHTTP %{http_code}\n" -X POST "$API_URL/rest/v1/rpc/get_leaderboard" \
  -H "apikey: $ANON_KEY" -H "content-type: application/json" -d '{"p_metric":"best_time","p_limit":50}'
# chamada nova do PR #11 (ISO string)
curl -s -w "\nHTTP %{http_code}\n" -X POST "$API_URL/rest/v1/rpc/get_leaderboard" \
  -H "apikey: $ANON_KEY" -H "content-type: application/json" \
  -d '{"p_metric":"best_time","p_limit":50,"p_from":"2031-03-15T10:00:00.000Z","p_to":"2031-03-15T12:00:00.000Z"}'
# leitura publica das rodadas
curl -s -w "\nHTTP %{http_code}\n" "$API_URL/rest/v1/ranking_windows?select=id,name,starts_at,ends_at" -H "apikey: $ANON_KEY"
# escrita anonima bloqueada
curl -s -w "\nHTTP %{http_code}\n" -X POST "$API_URL/rest/v1/ranking_windows" -H "apikey: $ANON_KEY" \
  -H "content-type: application/json" -d '{"name":"x","starts_at":"2031-05-01T10:00:00Z","ends_at":"2031-05-01T12:00:00Z"}'
```
Expected: `HTTP 200` com `[]` nas três primeiras (banco local vazio); `HTTP 401` ou `403` com código `42501` na última.

- [ ] **Step 3: Atualizar `docs/frontend-integration.md` §8**

Substituir o bloco da §8 por:

````markdown
## 8. Ranking / leaderboard (público)
```ts
// metric: 'best_time' (por enquanto). Retorna [{ rank, display_name, score }]
const { data } = await supabase.rpc('get_leaderboard', { p_metric: 'best_time', p_limit: 50 })
// período opcional (NEU-110): conta só corridas com p_from <= finished_at < p_to
const { data: rodada } = await supabase.rpc('get_leaderboard', {
  p_metric: 'best_time', p_limit: 50, p_from: r.starts_at, p_to: r.ends_at,
})
// score de best_time = duração da melhor corrida em SEGUNDOS (menor = melhor)
```
- É **público** (funciona logado ou não). Devolve só `rank`, `display_name`, `score` — sem e-mail.
- **Desempate:** mesmo tempo → vence quem fez primeiro (rank distinto). Só empate exato de tempo e instante divide o rank.
- **Rodadas:** `supabase.from('ranking_windows').select('id, name, starts_at, ends_at')` — leitura pública, sem sobreposição. "Evento" = desde o menor `starts_at`; "rodada atual" = `starts_at <= agora < ends_at`. Escrita só pelo SQL do Supabase (até a NEU-114).
- Para destacar "você", compare `display_name` com o do próprio usuário (lido de `profiles`).
````

- [ ] **Step 4: Atualizar `CLAUDE.md`**

Na seção "Arquitetura", trocar `**Postgres (8 migrations)**:` por `**Postgres (10 migrations)**:`, acrescentar depois do bullet `get_leaderboard`:

```markdown
  - `leaderboard_exclude_bots` — `get_leaderboard` só conta `source = 'real'`.
  - `ranking_windows` — tabela de rodadas (leitura pública, sem sobreposição, escrita só por SQL/`service_role`) + `get_leaderboard(p_metric, p_limit, p_from, p_to)` com período e desempate por quem fez primeiro (NEU-110).
```

e trocar a linha `**Tabelas:**` por:

```markdown
- **Tabelas:** `players, races, race_players, telemetry_points, profiles, ranking_windows`. **Funções:** `ingest_race, handle_email_confirmed, handle_new_user_profile, get_leaderboard`.
```

Na seção "Testar", trocar a linha "Estado verde de referência" pelos números reais da Task 3 Step 5 (ex.: `**9 testes SQL OK + 31 passed | 0 failed no Deno**`, com a data).

- [ ] **Step 5: Suíte completa**

Run: `npx --yes supabase@2.109.0 db reset`, o loop da suíte SQL e `deno test supabase/functions/ingest-race/`
Expected: 9 linhas `... OK` e `31 passed | 0 failed`.

- [ ] **Step 6: Commit**

```bash
git add supabase/types/database.types.ts docs/frontend-integration.md CLAUDE.md
git commit -F - <<'EOF'
docs(ranking): types regenerados e contrato de rodadas/periodo no guia do front [NEU-110]

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 4: PR e CI

**Files:** nenhum.

- [ ] **Step 1: Push e PR (token do `santos-nikolas`, sem trocar a conta global)**

```bash
export GH_TOKEN=$(gh auth token --user santos-nikolas)
git push -u origin feature/neu-110
gh pr create -R NeuroRace/cloud-backend --base main --head feature/neu-110 \
  --title "feat(ranking): rodadas + período e desempate no get_leaderboard (NEU-110)" --body-file <arquivo>
```
Corpo: TL;DR não técnico; o que entra (tabela, função, docs); contrato = web PR #11; como verificar (suíte + curls); "Merge ≠ deploy: `db push` pendente (Task 5)"; `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.

- [ ] **Step 2: CI verde**

Run: `gh pr checks <n> -R NeuroRace/cloud-backend --watch`
Expected: job `db-and-function` pass. Se falhar, `superpowers:systematic-debugging`.

- [ ] **Step 3: Linear** — NEU-110 → In Review, anexar o link do PR, comentar com o contrato final.

---

### Task 5: Deploy em produção (SÓ com ok explícito do Nikolas, depois do merge)

**Files:** nenhum.

Pré-requisitos: PR mergeado; `SUPABASE_ACCESS_TOKEN` e a senha do banco (`SUPABASE_DB_PASSWORD`) fornecidos pelo Nikolas na sessão, nunca ecoados nem gravados.

- [ ] **Step 1: Conferir drift antes (NEU-77)**

Run: `npx --yes supabase@2.109.0 link --project-ref wtaulbdkgrnrtbfezaxw` e `npx --yes supabase@2.109.0 migration list --linked`
Expected: todas as migrations locais até `20260703091403` aparecem como aplicadas no remoto; só `20260928120000` pendente. Qualquer outra divergência: **pare** e reporte.

- [ ] **Step 2: Dry-run e push**

Run: `npx --yes supabase@2.109.0 db push --dry-run` (deve listar só `20260928120000_ranking_windows.sql`) e, com ok, `npx --yes supabase@2.109.0 db push`.

- [ ] **Step 3: Verificar ao vivo (anon, só leitura)**

```bash
U=https://wtaulbdkgrnrtbfezaxw.supabase.co; K=sb_publishable_JpFFIWudbZ3GxR04QINxog_GqGk7dpw
curl -s -X POST "$U/rest/v1/rpc/get_leaderboard" -H "apikey: $K" -H "content-type: application/json" -d '{"p_metric":"best_time","p_limit":50}' -w "\nHTTP %{http_code}\n"
curl -s "$U/rest/v1/ranking_windows?select=id,name,starts_at,ends_at" -H "apikey: $K" -w "\nHTTP %{http_code}\n"
```
Expected: o ranking igual ao de antes do deploy (em 28/09: Pedro 20.81 rank 1, Guilherme 94 rank 2) e `HTTP 200 []` nas rodadas.

- [ ] **Step 4: Cadastrar as rodadas da banca** — horários combinados com o time, via SQL editor do Supabase, sempre com offset: `insert into public.ranking_windows (name, starts_at, ends_at) values ('Banca 1', '2026-09-30 14:00-03', '2026-09-30 16:00-03');`

- [ ] **Step 5: Avisar o Guilherme** (NEU-111) para regenerar os types do web e fechar a NEU-110 no Linear.
