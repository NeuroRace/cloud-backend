# Ingest de Corridas (cloud-backend) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Receber e armazenar de forma durável e idempotente o resultado de corrida vindo do edge-service, com identidade de jogador por email e vínculo tardio a contas, numa Supabase Edge Function.

**Architecture:** Migrations SQL versionadas neste repo criam 4 tabelas (`players`, `races`, `race_players`, `telemetry_points`) com RLS e um trigger de claim por email verificado. Uma função Postgres `ingest_race(payload jsonb)` faz o upsert transacional e idempotente. A Edge Function `ingest-race` (Deno) valida o token (shared-secret, `verify_jwt=false`), valida o body contra o contrato canônico e chama a função via `rpc` com a service_role.

**Tech Stack:** Supabase CLI 2.107.0 `[ev]`, Postgres 17, Deno (Edge Functions), `@supabase/supabase-js` v2, psql para asserts de banco, bash+curl para a prova de integração.

## Global Constraints

Valores **verbatim** do spec (`docs/superpowers/specs/2026-06-21-cloud-backend-ingest-design.md`, SHA `8e4f66d`). Todo task herda isto:

- Contrato canônico **snake_case**, `schema_version` = `"1.0"`.
- Timestamps: **epoch ms UTC (int)** → `timestamptz` via `to_timestamp(ms / 1000.0)`.
- Auth: header **`x-edge-ingest-token`**; `verify_jwt=false`; comparação em **tempo constante**. A anon key **não** é fator de segurança. service_role escreve server-side e **nunca** sai da Cloud.
- Idempotência **dupla**: `unique (idempotency_key)` **e** `unique (race_id, player_slot)`.
- Email **normalizado**: `lower(trim(email))`.
- `signal_status` ∈ {`ok`,`poor`,`no-signal`,`unknown`}.
- `telemetry_points` pode ser **vazio** (corrida persiste mesmo assim).
- `player_uuid` é sempre `null` hoje (mantido no contrato de propósito).
- **Invariante:** `mailer_autoconfirm` permanece `false` (segurança do claim depende disso) `[ev]`.
- Segredos **nunca** em repo/chat/disco. `EDGE_INGEST_TOKEN` é secret da função. Chaves no formato novo `sb_*`.
- RLS habilitado em todas as tabelas, **sem policy de escrita pública**.
- **Pré-requisito de ambiente:** Docker rodando (necessário para `supabase start`). `[hip — não verifiquei Docker neste host; checar no Task 1]`

---

## File Structure

```
cloud-backend/
  .gitignore                                  # Task 1
  .env.example                                # Task 1 (documenta EDGE_INGEST_TOKEN; sem valores reais)
  README.md                                   # Task 8
  supabase/
    config.toml                               # Task 1 (init) + Task 7 (verify_jwt=false)
    migrations/
      <ts>_init_schema.sql                    # Task 2 (4 tabelas + índices + RLS)
      <ts>_ingest_race_fn.sql                 # Task 3 (função ingest_race)
      <ts>_claim_trigger.sql                  # Task 4 (trigger de claim)
    functions/
      ingest-race/
        index.ts                              # Task 7 (handler)
        auth.ts                               # Task 5 (compare tempo constante)
        contract.ts                           # Task 6 (validação estrita)
        auth_test.ts                          # Task 5
        contract_test.ts                      # Task 6
    tests/
      schema_test.sql                         # Task 2 (asserts via psql)
      ingest_race_test.sql                    # Task 3
      claim_test.sql                          # Task 4
  scripts/
    proof-ingest.sh                           # Task 7 (prova de integração curl + psql)
```

**Convenção de URL/DB local (Supabase default):** função em `http://127.0.0.1:54321/functions/v1/ingest-race`; DB em `postgresql://postgres:postgres@127.0.0.1:54322/postgres`. Confirme com `supabase status`.

---

### Task 1: Scaffold do repo + Supabase local no ar

**Files:**
- Create: `.gitignore`, `.env.example`
- Create (via CLI): `supabase/config.toml` e estrutura `supabase/`

**Interfaces:**
- Consumes: nada.
- Produces: stack local do Supabase rodando; estrutura `supabase/` versionável.

- [ ] **Step 1: Verificar Docker (pré-requisito)**

Run: `docker info >/dev/null 2>&1 && echo DOCKER_OK || echo DOCKER_MISSING`
Expected: `DOCKER_OK`. Se `DOCKER_MISSING`, **pare** e peça o ambiente Docker ao Pedro (não inferir).

- [ ] **Step 2: `supabase init`**

Run: `supabase init`
Expected: cria `supabase/config.toml` e `supabase/` (functions, migrations). Se perguntar sobre VS Code/Deno settings, responder `N`.

- [ ] **Step 3: Criar `.gitignore`**

```gitignore
# secrets — nunca commitar
.env
supabase/functions/.env

# supabase local
supabase/.temp/
supabase/.branches/

# os
.DS_Store
```

- [ ] **Step 4: Criar `.env.example`**

```bash
# Copie para supabase/functions/.env (gitignored) para rodar `supabase functions serve`.
# NUNCA commite valores reais. Em produção, use `supabase secrets set`.
EDGE_INGEST_TOKEN=dev-only-change-me
```

- [ ] **Step 5: Subir o stack local**

Run: `supabase start`
Expected: imprime API URL (`http://127.0.0.1:54321`), DB URL (`...54322`), e as chaves locais.

- [ ] **Step 6: Verificar status**

Run: `supabase status`
Expected: serviços `RUNNING` (API, DB, Auth). Anote o `DB URL`.

- [ ] **Step 7: Commit**

```bash
git add .gitignore .env.example supabase/config.toml
git commit -m "chore(supabase): init local stack + gitignore/env.example"
```

---

### Task 2: Migration do schema (4 tabelas + índices + RLS)

**Files:**
- Create: `supabase/migrations/<ts>_init_schema.sql`
- Test: `supabase/tests/schema_test.sql`

**Interfaces:**
- Consumes: stack local (Task 1).
- Produces: tabelas `players(id, email unique, user_id, created_at)`, `races(id, started_at, created_at)`, `race_players(id, idempotency_key unique, race_id fk, player_id fk, player_slot, source, started_at, finished_at, created_at, unique(race_id,player_slot))`, `telemetry_points(id, race_player_id fk, t, attention, meditation, poor_signal_level, signal_status, eeg_power)`. RLS ON, sem policies.

- [ ] **Step 1: Escrever o teste que falha** — `supabase/tests/schema_test.sql`

```sql
\set ON_ERROR_STOP on
do $$
begin
  assert (select count(*) from information_schema.tables
          where table_schema='public'
            and table_name in ('players','races','race_players','telemetry_points')) = 4,
    'esperado 4 tabelas em public';
  assert (select count(*) from information_schema.table_constraints
          where constraint_schema='public' and table_name='race_players'
            and constraint_type='UNIQUE') >= 2,
    'race_players precisa de 2 uniques (idempotency_key e race_id+player_slot)';
  assert (select relrowsecurity from pg_class where oid='public.players'::regclass), 'RLS off em players';
  assert (select relrowsecurity from pg_class where oid='public.races'::regclass), 'RLS off em races';
  assert (select relrowsecurity from pg_class where oid='public.race_players'::regclass), 'RLS off em race_players';
  assert (select relrowsecurity from pg_class where oid='public.telemetry_points'::regclass), 'RLS off em telemetry_points';
  assert (select count(*) from pg_policies where schemaname='public') = 0, 'nenhuma policy publica esperada';
  raise notice 'schema_test OK';
end $$;
```

- [ ] **Step 2: Rodar o teste e ver falhar**

Run: `psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -v ON_ERROR_STOP=1 -f supabase/tests/schema_test.sql`
Expected: FALHA (`esperado 4 tabelas em public`) — as tabelas ainda não existem.

- [ ] **Step 3: Criar a migration**

Run: `supabase migration new init_schema` (cria `supabase/migrations/<ts>_init_schema.sql`). Preencher com:

```sql
create table players (
  id         uuid primary key default gen_random_uuid(),
  email      text not null unique,                 -- normalizado lower(trim)
  user_id    uuid unique references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table races (
  id          uuid primary key,                    -- race_id do edge
  started_at  timestamptz not null,                -- inicio compartilhado
  created_at  timestamptz not null default now()
);

create table race_players (
  id              uuid primary key default gen_random_uuid(),
  idempotency_key uuid not null unique,
  race_id         uuid not null references races(id),
  player_id       uuid not null references players(id),
  player_slot     int  not null check (player_slot in (1,2)),
  source          text not null default 'real',
  started_at      timestamptz not null,
  finished_at     timestamptz,
  created_at      timestamptz not null default now(),
  unique (race_id, player_slot)
);

create table telemetry_points (
  id                bigint generated always as identity primary key,
  race_player_id    uuid not null references race_players(id) on delete cascade,
  t                 timestamptz not null,
  attention         int,
  meditation        int,
  poor_signal_level int,
  signal_status     text,
  eeg_power         jsonb
);

create index on telemetry_points (race_player_id);
create index on race_players (player_id);
create index on race_players (race_id);

-- RLS habilitado, sem policy de escrita publica. service_role bypassa RLS.
alter table players          enable row level security;
alter table races            enable row level security;
alter table race_players     enable row level security;
alter table telemetry_points enable row level security;
```

- [ ] **Step 4: Aplicar a migration**

Run: `supabase db reset`
Expected: aplica `init_schema` sem erro (`Applying migration <ts>_init_schema.sql...`).

- [ ] **Step 5: Rodar o teste e ver passar**

Run: `psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -v ON_ERROR_STOP=1 -f supabase/tests/schema_test.sql`
Expected: `NOTICE: schema_test OK`, exit 0.

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations supabase/tests/schema_test.sql
git commit -m "feat(db): schema do ingest (players/races/race_players/telemetry) + RLS"
```

---

### Task 3: Função `ingest_race(payload jsonb)` (upsert transacional idempotente)

**Files:**
- Create: `supabase/migrations/<ts>_ingest_race_fn.sql`
- Test: `supabase/tests/ingest_race_test.sql`

**Interfaces:**
- Consumes: tabelas do Task 2.
- Produces: `public.ingest_race(payload jsonb) returns jsonb` — retorna `{"status":"created"}` ou `{"status":"duplicate"}`. Chamada pelo handler via `rpc('ingest_race', { payload })`.

- [ ] **Step 1: Escrever o teste que falha** — `supabase/tests/ingest_race_test.sql`

```sql
\set ON_ERROR_STOP on
do $$
declare
  r jsonb;
  base jsonb := jsonb_build_object(
    'schema_version','1.0',
    'idempotency_key','11111111-1111-1111-1111-111111111111',
    'race_id','22222222-2222-2222-2222-222222222222',
    'player_slot',1,'player_email','A@Test.com ','player_uuid',null,'source','real',
    'started_at',1735689600000::bigint,'finished_at',1735689660000::bigint,
    'telemetry_points', jsonb_build_array(
      jsonb_build_object('t',1735689601000::bigint,'attention',80,'meditation',55,
        'poor_signal_level',0,'signal_status','ok',
        'eeg_power',jsonb_build_object('delta',1,'theta',2))));
begin
  delete from telemetry_points; delete from race_players; delete from races; delete from players;

  r := ingest_race(base);
  assert r->>'status' = 'created', '1o ingest = created';
  assert (select count(*) from races) = 1, 'uma race';
  assert (select count(*) from race_players) = 1, 'um race_player';
  assert (select count(*) from telemetry_points) = 1, 'um ponto';
  assert (select email from players limit 1) = 'a@test.com', 'email normalizado lower+trim';

  r := ingest_race(base);  -- replay mesma idempotency_key
  assert r->>'status' = 'duplicate', 'replay = duplicate';
  assert (select count(*) from race_players) = 1, 'sem dup no replay';
  assert (select count(*) from telemetry_points) = 1, 'sem dup de telemetria';

  -- mesma (race_id, player_slot), idempotency_key diferente -> ainda duplicate
  r := ingest_race(jsonb_set(base,'{idempotency_key}','"33333333-3333-3333-3333-333333333333"'));
  assert r->>'status' = 'duplicate', '2a trava (race_id,slot) bloqueia';
  assert (select count(*) from race_players) = 1, 'sem dup pela 2a trava';

  -- player 2, mesmo email -> 2 race_players, 1 player
  r := ingest_race(jsonb_build_object(
    'schema_version','1.0','idempotency_key','44444444-4444-4444-4444-444444444444',
    'race_id','22222222-2222-2222-2222-222222222222','player_slot',2,
    'player_email','a@test.com','player_uuid',null,'source','real',
    'started_at',1735689600000::bigint,'finished_at',1735689670000::bigint,
    'telemetry_points','[]'::jsonb));
  assert r->>'status' = 'created', 'player 2 created';
  assert (select count(*) from race_players) = 2, 'dois race_players';
  assert (select count(*) from players) = 1, 'um player canonico (mesmo email)';
  assert (select count(*) from telemetry_points) = 1, 'telemetria vazia do p2 nao gera ponto';

  raise notice 'ingest_race_test OK';
end $$;
```

- [ ] **Step 2: Rodar o teste e ver falhar**

Run: `psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -v ON_ERROR_STOP=1 -f supabase/tests/ingest_race_test.sql`
Expected: FALHA (`function ingest_race(jsonb) does not exist`).

- [ ] **Step 3: Criar a função**

Run: `supabase migration new ingest_race_fn`. Preencher:

```sql
create or replace function public.ingest_race(payload jsonb)
returns jsonb
language plpgsql
as $$
declare
  v_email          text := lower(trim(payload->>'player_email'));
  v_player_id      uuid;
  v_race_player_id uuid;
begin
  -- short-circuit por idempotency_key (replay)
  if exists (select 1 from race_players
              where idempotency_key = (payload->>'idempotency_key')::uuid) then
    return jsonb_build_object('status','duplicate');
  end if;

  -- resolve/cria player (nunca toca user_id)
  insert into players (email) values (v_email)
  on conflict (email) do nothing;
  select id into v_player_id from players where email = v_email;

  -- upsert race (inicio compartilhado)
  insert into races (id, started_at)
  values ((payload->>'race_id')::uuid,
          to_timestamp((payload->>'started_at')::bigint / 1000.0))
  on conflict (id) do nothing;

  -- resultado por jogador; dupla trava via on conflict do nothing
  insert into race_players
    (idempotency_key, race_id, player_id, player_slot, source, started_at, finished_at)
  values
    ((payload->>'idempotency_key')::uuid,
     (payload->>'race_id')::uuid,
     v_player_id,
     (payload->>'player_slot')::int,
     coalesce(payload->>'source','real'),
     to_timestamp((payload->>'started_at')::bigint / 1000.0),
     to_timestamp((payload->>'finished_at')::bigint / 1000.0))
  on conflict do nothing
  returning id into v_race_player_id;

  if v_race_player_id is null then
    return jsonb_build_object('status','duplicate');  -- perdeu a corrida em (race_id,slot)
  end if;

  insert into telemetry_points
    (race_player_id, t, attention, meditation, poor_signal_level, signal_status, eeg_power)
  select v_race_player_id,
         to_timestamp((p->>'t')::bigint / 1000.0),
         (p->>'attention')::int,
         (p->>'meditation')::int,
         (p->>'poor_signal_level')::int,
         p->>'signal_status',
         p->'eeg_power'
  from jsonb_array_elements(coalesce(payload->'telemetry_points','[]'::jsonb)) as p;

  return jsonb_build_object('status','created');
end;
$$;
```

- [ ] **Step 4: Aplicar e rodar o teste**

Run: `supabase db reset && psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -v ON_ERROR_STOP=1 -f supabase/tests/ingest_race_test.sql`
Expected: `NOTICE: ingest_race_test OK`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations supabase/tests/ingest_race_test.sql
git commit -m "feat(db): funcao ingest_race transacional e idempotente"
```

---

### Task 4: Trigger de claim (vínculo por email verificado)

**Files:**
- Create: `supabase/migrations/<ts>_claim_trigger.sql`
- Test: `supabase/tests/claim_test.sql`

**Interfaces:**
- Consumes: tabela `players` (Task 2).
- Produces: trigger `on_auth_email_confirmed` em `auth.users` que, na confirmação de email, faz `players.user_id = auth.users.id` para o email normalizado.

- [ ] **Step 1: Escrever o teste que falha** — `supabase/tests/claim_test.sql`

> `[hip]` `auth.users` pode exigir colunas NOT NULL além das abaixo nesta versão. Se o INSERT falhar por NOT NULL, adicionar as colunas faltantes (valores dummy) — o objetivo do teste é provar o trigger, não o schema do GoTrue.

```sql
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
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -v ON_ERROR_STOP=1 -f supabase/tests/claim_test.sql`
Expected: FALHA na 2ª assert (`email confirmado deve vincular...`) — sem trigger, `user_id` continua null.

- [ ] **Step 3: Criar o trigger**

Run: `supabase migration new claim_trigger`. Preencher:

```sql
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
```

- [ ] **Step 4: Aplicar e rodar o teste**

Run: `supabase db reset && psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -v ON_ERROR_STOP=1 -f supabase/tests/claim_test.sql`
Expected: `NOTICE: claim_test OK`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations supabase/tests/claim_test.sql
git commit -m "feat(db): trigger de claim por email verificado"
```

---

### Task 5: `auth.ts` — comparação de token em tempo constante

**Files:**
- Create: `supabase/functions/ingest-race/auth.ts`
- Test: `supabase/functions/ingest-race/auth_test.ts`

**Interfaces:**
- Consumes: nada.
- Produces: `tokenMatches(provided: string | null, expected: string): Promise<boolean>` — true só se iguais; compara digests SHA-256 (tempo constante, sem vazar tamanho).

- [ ] **Step 1: Escrever o teste que falha** — `auth_test.ts`

```ts
import { assertEquals } from "jsr:@std/assert@1";
import { tokenMatches } from "./auth.ts";

Deno.test("token valido casa", async () => {
  assertEquals(await tokenMatches("s3cret-token", "s3cret-token"), true);
});
Deno.test("token invalido rejeitado", async () => {
  assertEquals(await tokenMatches("wrong", "s3cret-token"), false);
});
Deno.test("token nulo rejeitado", async () => {
  assertEquals(await tokenMatches(null, "s3cret-token"), false);
});
Deno.test("tamanho diferente rejeitado", async () => {
  assertEquals(await tokenMatches("s3cret-token-longo", "s3cret-token"), false);
});
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `deno test supabase/functions/ingest-race/auth_test.ts`
Expected: FALHA (`Module not found "./auth.ts"`).

- [ ] **Step 3: Implementar `auth.ts`**

```ts
async function sha256(s: string): Promise<Uint8Array> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return new Uint8Array(digest);
}

/** Compara tokens em tempo constante via digests SHA-256 (tamanho fixo, sem leak de length). */
export async function tokenMatches(provided: string | null, expected: string): Promise<boolean> {
  if (provided === null || expected === "") return false;
  const a = await sha256(provided);
  const b = await sha256(expected);
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}
```

- [ ] **Step 4: Rodar e ver passar**

Run: `deno test supabase/functions/ingest-race/auth_test.ts`
Expected: `ok | 4 passed | 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/ingest-race/auth.ts supabase/functions/ingest-race/auth_test.ts
git commit -m "feat(fn): compare de token em tempo constante"
```

---

### Task 6: `contract.ts` — validação estrita do body canônico

**Files:**
- Create: `supabase/functions/ingest-race/contract.ts`
- Test: `supabase/functions/ingest-race/contract_test.ts`

**Interfaces:**
- Consumes: nada.
- Produces: `validateIngestBody(body: unknown): { ok: true } | { ok: false; error: string }`.

- [ ] **Step 1: Escrever o teste que falha** — `contract_test.ts`

```ts
import { assert, assertEquals } from "jsr:@std/assert@1";
import { validateIngestBody } from "./contract.ts";

const valid = {
  schema_version: "1.0",
  idempotency_key: "11111111-1111-1111-1111-111111111111",
  race_id: "22222222-2222-2222-2222-222222222222",
  player_slot: 1, player_email: "a@test.com", player_uuid: null, source: "real",
  started_at: 1735689600000, finished_at: 1735689660000,
  telemetry_points: [{ t: 1735689601000, attention: 80, meditation: 55,
    poor_signal_level: 0, signal_status: "ok", eeg_power: { delta: 1 } }],
};

Deno.test("body valido passa", () => assert(validateIngestBody(valid).ok));
Deno.test("telemetria vazia passa", () =>
  assert(validateIngestBody({ ...valid, telemetry_points: [] }).ok));
Deno.test("schema_version errado falha", () => {
  const r = validateIngestBody({ ...valid, schema_version: "2.0" });
  assertEquals(r.ok ? "" : r.error, "unsupported_schema_version");
});
Deno.test("idempotency_key nao-uuid falha", () => {
  const r = validateIngestBody({ ...valid, idempotency_key: "x" });
  assertEquals(r.ok ? "" : r.error, "idempotency_key_must_be_uuid");
});
Deno.test("player_slot invalido falha", () => {
  const r = validateIngestBody({ ...valid, player_slot: 3 });
  assertEquals(r.ok ? "" : r.error, "player_slot_must_be_1_or_2");
});
Deno.test("email vazio falha", () => {
  const r = validateIngestBody({ ...valid, player_email: "  " });
  assertEquals(r.ok ? "" : r.error, "player_email_required");
});
Deno.test("signal_status invalido falha", () => {
  const r = validateIngestBody({ ...valid,
    telemetry_points: [{ ...valid.telemetry_points[0], signal_status: "bad" }] });
  assertEquals(r.ok ? "" : r.error, "telemetry_signal_status_invalid");
});
Deno.test("started_at nao-int falha", () => {
  const r = validateIngestBody({ ...valid, started_at: "ontem" });
  assertEquals(r.ok ? "" : r.error, "started_at_must_be_int");
});
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `deno test supabase/functions/ingest-race/contract_test.ts`
Expected: FALHA (`Module not found "./contract.ts"`).

- [ ] **Step 3: Implementar `contract.ts`**

```ts
export type ValidationResult = { ok: true } | { ok: false; error: string };

const SIGNAL_STATUS = new Set(["ok", "poor", "no-signal", "unknown"]);
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const isInt = (n: unknown): n is number => typeof n === "number" && Number.isInteger(n);
const fail = (error: string): ValidationResult => ({ ok: false, error });

export function validateIngestBody(body: unknown): ValidationResult {
  if (typeof body !== "object" || body === null) return fail("body_must_be_object");
  const b = body as Record<string, unknown>;

  if (b.schema_version !== "1.0") return fail("unsupported_schema_version");
  if (typeof b.idempotency_key !== "string" || !UUID_RE.test(b.idempotency_key))
    return fail("idempotency_key_must_be_uuid");
  if (typeof b.race_id !== "string" || !UUID_RE.test(b.race_id))
    return fail("race_id_must_be_uuid");
  if (b.player_slot !== 1 && b.player_slot !== 2) return fail("player_slot_must_be_1_or_2");
  if (typeof b.player_email !== "string" || b.player_email.trim() === "")
    return fail("player_email_required");
  if (b.player_uuid !== null && typeof b.player_uuid !== "string")
    return fail("player_uuid_must_be_string_or_null");
  if (b.source !== "real" && b.source !== "bot") return fail("source_invalid");
  if (!isInt(b.started_at)) return fail("started_at_must_be_int");
  if (!isInt(b.finished_at)) return fail("finished_at_must_be_int");
  if (!Array.isArray(b.telemetry_points)) return fail("telemetry_points_must_be_array");

  for (const p of b.telemetry_points as unknown[]) {
    if (typeof p !== "object" || p === null) return fail("telemetry_point_must_be_object");
    const tp = p as Record<string, unknown>;
    if (!isInt(tp.t)) return fail("telemetry_t_must_be_int");
    if (!isInt(tp.attention)) return fail("telemetry_attention_must_be_int");
    if (!isInt(tp.meditation)) return fail("telemetry_meditation_must_be_int");
    if (tp.poor_signal_level !== null && !isInt(tp.poor_signal_level))
      return fail("telemetry_poor_signal_level_invalid");
    if (typeof tp.signal_status !== "string" || !SIGNAL_STATUS.has(tp.signal_status))
      return fail("telemetry_signal_status_invalid");
    if (typeof tp.eeg_power !== "object" || tp.eeg_power === null || Array.isArray(tp.eeg_power))
      return fail("telemetry_eeg_power_must_be_object");
  }
  return { ok: true };
}
```

- [ ] **Step 4: Rodar e ver passar**

Run: `deno test supabase/functions/ingest-race/contract_test.ts`
Expected: `ok | 9 passed | 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/ingest-race/contract.ts supabase/functions/ingest-race/contract_test.ts
git commit -m "feat(fn): validacao estrita do contrato canonico"
```

---

### Task 7: Handler `index.ts` + `verify_jwt=false` + prova de integração (valida §10)

**Files:**
- Create: `supabase/functions/ingest-race/index.ts`
- Modify: `supabase/config.toml` (adicionar bloco da função)
- Create: `scripts/proof-ingest.sh`
- Create: `supabase/functions/.env` (gitignored, local) com `EDGE_INGEST_TOKEN`

**Interfaces:**
- Consumes: `tokenMatches` (Task 5), `validateIngestBody` (Task 6), `ingest_race` rpc (Task 3).
- Produces: endpoint HTTP `POST /functions/v1/ingest-race` com a semântica de status do spec §7.

- [ ] **Step 1: Configurar `verify_jwt=false`** — adicionar ao fim de `supabase/config.toml`:

```toml
[functions.ingest-race]
verify_jwt = false
```

- [ ] **Step 2: Implementar o handler** — `supabase/functions/ingest-race/index.ts`

```ts
import { createClient } from "jsr:@supabase/supabase-js@2";
import { tokenMatches } from "./auth.ts";
import { validateIngestBody } from "./contract.ts";

const EDGE_INGEST_TOKEN = Deno.env.get("EDGE_INGEST_TOKEN") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

function log(level: string, event: string, fields: Record<string, unknown> = {}) {
  console.log(JSON.stringify({ level, event, ...fields }));
}
function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status, headers: { "content-type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed", message: "use POST" });

  const provided = req.headers.get("x-edge-ingest-token");
  if (!(await tokenMatches(provided, EDGE_INGEST_TOKEN))) {
    log("warn", "ingest_unauthorized");
    return json(401, { error: "unauthorized", message: "invalid ingest token" });
  }

  let body: unknown;
  try { body = await req.json(); }
  catch { return json(422, { error: "invalid_json", message: "body is not valid JSON" }); }

  const v = validateIngestBody(body);
  if (!v.ok) {
    log("warn", "ingest_invalid_body", { error: v.error });
    return json(422, { error: v.error, message: "body failed contract validation" });
  }
  const payload = body as Record<string, unknown>;

  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE, { auth: { persistSession: false } });
  const { data, error } = await supabase.rpc("ingest_race", { payload });
  if (error) {
    log("error", "ingest_db_error", {
      race_id: payload.race_id, idempotency_key: payload.idempotency_key, db_error: error.message,
    });
    return json(500, { error: "db_error", message: "failed to persist race" });
  }

  const status = (data as { status?: string } | null)?.status ?? "created";
  log("info", "ingest_ok", {
    status, race_id: payload.race_id,
    idempotency_key: payload.idempotency_key, player_slot: payload.player_slot,
  });
  return json(200, { status });
});
```

- [ ] **Step 3: Criar `supabase/functions/.env` local (gitignored)**

```bash
printf 'EDGE_INGEST_TOKEN=dev-only-change-me\n' > supabase/functions/.env
```

- [ ] **Step 4: Escrever a prova de integração** — `scripts/proof-ingest.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
URL="http://127.0.0.1:54321/functions/v1/ingest-race"
DB="postgresql://postgres:postgres@127.0.0.1:54322/postgres"
TOKEN="${EDGE_INGEST_TOKEN:-dev-only-change-me}"

body() { cat <<JSON
{"schema_version":"1.0","idempotency_key":"$1","race_id":"$2","player_slot":$3,"player_email":"$4","player_uuid":null,"source":"real","started_at":1735689600000,"finished_at":1735689660000,"telemetry_points":[{"t":1735689601000,"attention":80,"meditation":55,"poor_signal_level":0,"signal_status":"ok","eeg_power":{"delta":1}}]}
JSON
}
post() { curl -s -o /dev/null -w "%{http_code}" -X POST "$URL" \
  -H "content-type: application/json" -H "x-edge-ingest-token: $1" --data "$2"; }

psql "$DB" -q -c "delete from telemetry_points; delete from race_players; delete from races; delete from players;"

R=22222222-2222-2222-2222-222222222222
c=$(post "$TOKEN" "$(body 11111111-1111-1111-1111-111111111111 $R 1 a@test.com)")
[ "$c" = 200 ] || { echo "FAIL valido=$c (esperado 200)"; exit 1; }

c=$(post "$TOKEN" "$(body 11111111-1111-1111-1111-111111111111 $R 1 a@test.com)")
[ "$c" = 200 ] || { echo "FAIL replay=$c (esperado 200)"; exit 1; }
n=$(psql "$DB" -tA -c "select count(*) from race_players")
[ "$n" = 1 ] || { echo "FAIL dup: race_players=$n (esperado 1)"; exit 1; }

c=$(post "nope" "$(body 55555555-5555-5555-5555-555555555555 $R 1 a@test.com)")
[ "$c" = 401 ] || { echo "FAIL token-errado=$c (esperado 401)"; exit 1; }

c=$(post "$TOKEN" '{"schema_version":"1.0"}')
[ "$c" = 422 ] || { echo "FAIL body-invalido=$c (esperado 422)"; exit 1; }

echo "PROOF OK: 200 / 200(sem-dup) / 401 / 422"
```

Run: `chmod +x scripts/proof-ingest.sh`

- [ ] **Step 5: Servir a função (terminal separado / background)**

Run: `supabase functions serve ingest-race --env-file supabase/functions/.env`
Expected: `Serving functions on http://127.0.0.1:54321/functions/v1/ingest-race`.
> Se a função for rejeitada por falta de JWT (HTTP 401 da plataforma, não do handler) apesar do `verify_jwt=false`, isto **confirma a hipótese §10 H1 como falsa** — então passar `--no-verify-jwt` ao `serve` e abrir issue para alinhar o deploy. **Não inferir que funcionou: a prova é o Step 6.**

- [ ] **Step 6: Rodar a prova (valida §10 H1 e H2)**

Run: `EDGE_INGEST_TOKEN=dev-only-change-me ./scripts/proof-ingest.sh`
Expected: `PROOF OK: 200 / 200(sem-dup) / 401 / 422`.
- `200` sem nenhum header `apikey`/`Authorization` prova **§10 H1** (`verify_jwt=false` deixa passar o header custom).
- linhas gravadas via rpc com service_role prova **§10 H2** (env da service_role disponível no `serve`).

- [ ] **Step 7: Commit**

```bash
git add supabase/config.toml supabase/functions/ingest-race/index.ts scripts/proof-ingest.sh
git commit -m "feat(fn): handler ingest-race (auth+validacao+rpc) + prova de integracao"
```

---

### Task 8: README + verificação final verde + sign-off das hipóteses §10

**Files:**
- Create: `README.md`

**Interfaces:**
- Consumes: tudo.
- Produces: doc de como rodar local + registro do estado das hipóteses §10.

- [ ] **Step 1: Escrever `README.md`**

```markdown
# cloud-backend — API do NeuroRace

Ingest de corridas (Supabase Edge Function `ingest-race`) + schema Postgres.
Spec: `docs/superpowers/specs/2026-06-21-cloud-backend-ingest-design.md`.

## Rodar local
1. `docker info` (precisa de Docker)
2. `supabase start`
3. `supabase db reset`  # aplica migrations
4. `cp .env.example supabase/functions/.env` e ajuste `EDGE_INGEST_TOKEN`
5. `supabase functions serve ingest-race --env-file supabase/functions/.env`

## Testes
- Banco:  `psql "$(supabase status -o env | grep -oP '(?<=DB_URL=").*(?=")')" -v ON_ERROR_STOP=1 -f supabase/tests/<arquivo>.sql`
- Função: `deno test supabase/functions/ingest-race/`
- Integração: `EDGE_INGEST_TOKEN=... ./scripts/proof-ingest.sh`

## Auth
Header `x-edge-ingest-token`. `verify_jwt=false`. service_role escreve server-side.
Em produção: `supabase secrets set EDGE_INGEST_TOKEN=...` (nunca commitar).

## Invariante de segurança
`mailer_autoconfirm` DEVE permanecer `false` — o claim de corridas por email depende de email verificado.
```

- [ ] **Step 2: Rodar TODA a suíte e confirmar verde**

Run:
```bash
supabase db reset
DB="postgresql://postgres:postgres@127.0.0.1:54322/postgres"
for f in schema ingest_race claim; do psql "$DB" -v ON_ERROR_STOP=1 -f supabase/tests/${f}_test.sql; done
deno test supabase/functions/ingest-race/
```
Expected: 3× `... OK` (banco) + `deno` `passed | 0 failed`.

- [ ] **Step 3: Sign-off das hipóteses §10 no spec**

Verificar e anotar (commit no spec) o resultado real de cada hipótese §10 após os Tasks 4/7:
- H1 `verify_jwt=false` + header custom → resultado da prova (Task 7 Step 6).
- H2 injeção da service_role no `serve` → idem.
- claim em `auth.users` (Task 4) → colunas NOT NULL que foram necessárias.
- volume de telemetria → **ainda não medido**; manter como risco aberto até rodar uma corrida do simulador.

- [ ] **Step 4: Commit**

```bash
git add README.md docs/superpowers/specs/2026-06-21-cloud-backend-ingest-design.md
git commit -m "docs: README + sign-off das hipoteses da §10"
```

---

## Self-Review (preenchido pelo autor do plano)

**1. Cobertura do spec:**
- §2 schema (4 tabelas, índices, RLS) → Task 2 ✓
- §3 normalização email / dupla idempotência → Task 3 (asserts) ✓
- §4 claim por email verificado + invariante autoconfirm → Task 4 ✓ (invariante documentada em §README/spec)
- §5 contrato estrito snake_case → Task 6 ✓
- §6 handler (auth/validação/rpc/logging) + verify_jwt=false → Task 5+6+7 ✓
- §7 semântica 200/401/422/5xx → Task 7 handler + prova ✓
- §8 RLS sem policy pública → Task 2 ✓ (read policies explicitamente fora de escopo)
- §9 testes (replay, dup slot, token, body, claim, telemetria vazia) → Tasks 3/4/6/7 ✓
- §10 hipóteses verificadas → Task 7 (H1/H2) + Task 8 sign-off ✓ (volume permanece risco aberto, declarado)

**2. Placeholders:** nenhum TODO/TBD; todo passo tem código/comando real.

**3. Consistência de tipos:** `tokenMatches(provided, expected)`, `validateIngestBody(body)→{ok|error}`, `ingest_race(payload)→{status}` usados de forma idêntica entre Tasks 5/6/7. URL/DB local idênticos em todos os tasks.

**Riscos abertos declarados (honestidade):** volume de telemetria não medido (§10); `auth.users` pode exigir colunas extras no teste de claim (Task 4, marcado); `verify_jwt=false` no `serve` é provado no Task 7 Step 6, não assumido.
