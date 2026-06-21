# Design — cloud-backend: Ingest de Corridas + Identidade por Email

> Sub-projeto (1) da API do NeuroRace. Foco: receber e armazenar o resultado de
> corrida vindo do edge-service, de forma durável e idempotente, com identidade
> de jogador por email e vínculo tardio a contas. Desbloqueia o Stage 3 do edge
> (NEU-7, dispatcher).
>
> **Convenção:** `[ev]` = verificado nesta investigação (comando/arquivo/código/API).
> `[hip]` = hipótese **não** verificada, a confirmar na implementação. `[decisão]` =
> escolha tomada no brainstorming, passível de revisão.
>
> Data: 2026-06-21. edge-service `main` @ `5dd60e8`. Supabase ref `wtaulbdkgrnrtbfezaxw`.

---

## 1. Contexto e objetivo

- `cloud-backend` está vazio (sem commits) `[ev]`. A API é campo em branco.
- O Linear do cloud-backend **não** é fonte da verdade (issues defasadas) — decisão
  do dono. O design é guiado por best-practice e pragmatismo, não pelas issues.
- Supabase `wtaulbdkgrnrtbfezaxw` (PG17, ACTIVE_HEALTHY) está 100% vazio: 0 tabelas
  em `public`, 0 edge functions, 0 migrations, `auth.users` = 0 `[ev — Management API]`.
- O edge consolida o resultado por jogador no `hasFinished` e faz `RPUSH` durável em
  `dispatch:queue` (Redis), mas **não há envio para a Cloud** no `main` — a fila só é
  produzida `[ev — session_manager.js, ausência de consumidor no main]`. O dispatcher
  real (NEU-7) ainda não existe; o que existe (PR #4) está quebrado e fora de escopo aqui.

**Critério de sucesso deste sub-projeto:** o edge consegue fazer `POST` de um
resultado de corrida e ele é armazenado de forma **durável** e **idempotente**; um
email sem conta tem a corrida gravada mesmo assim; ao se cadastrar depois com o
**mesmo email verificado**, o usuário passa a ser dono daquelas corridas. Provado com
`curl` independente do edge.

**Fora de escopo (specs próprios depois):** API/queries de leitura (dashboard pessoal,
ranking — provável PostgREST+RLS, pouco/zero código custom); métricas/IA/perfis;
bot Telegram. Estes exigem ver os dados reais primeiro.

---

## 2. Decisões do brainstorming

1. **[decisão]** Identidade: tabela `players` canônica por **email normalizado**
   (`lower(trim(email))`); conta (`auth.users`) é **opcional e tardia**.
2. **[decisão]** Execução: **Supabase Edge Function `ingest-race`** (Deno/TS).
   Migrations versionadas neste repo. Reads futuros via PostgREST+RLS.
3. **[decisão]** Auth do ingest: **só shared-secret** `EDGE_INGEST_TOKEN` em header
   custom `x-edge-ingest-token`, `verify_jwt=false`, comparação em **tempo constante**.
   A anon key é pública (vai no bundle do frontend) e por isso **não** é usada como
   fator de segurança aqui. service_role escreve server-side e **nunca** sai da Cloud.
4. **[decisão]** Contrato canônico **snake_case, versionado** (`schema_version`),
   **dono = a API**. O edge adapta (mapping no dispatcher NEU-7). Validação estrita.
5. **[decisão]** Escrita atômica via **função Postgres `ingest_race(payload jsonb)`**
   chamada por `rpc` (PostgREST não dá transação multi-tabela por request).
6. **[decisão]** Telemetria em **tabela separada** (não jsonb embutido) — é o
   combustível das métricas futuras; o edge apaga os pacotes após consolidar, então
   não guardar agora = perder para sempre.

---

## 3. Modelo de dados

`supabase/migrations/<ts>_init_ingest.sql`:

```sql
-- Jogador canônico. Keyed por email normalizado; conta é opcional/tardia.
create table players (
  id         uuid primary key default gen_random_uuid(),
  email      text not null unique,          -- SEMPRE normalizado: lower(trim(email))
  user_id    uuid unique references auth.users(id) on delete set null, -- preenchido no claim
  created_at timestamptz not null default now()
);

-- Corrida. Uma linha por race_id (= sessionId do edge).
create table races (
  id          uuid primary key,             -- race_id vindo do edge (UUID)
  started_at  timestamptz not null,         -- início compartilhado (raceStarted do edge)
  created_at  timestamptz not null default now()
);                                          -- sem finished_at: o fim é por-jogador (ver nota)

-- Resultado por jogador. Alvo da idempotência.
create table race_players (
  id              uuid primary key default gen_random_uuid(),
  idempotency_key uuid not null unique,           -- = jobId do edge; dedupe de retries
  race_id         uuid not null references races(id),
  player_id       uuid not null references players(id),
  player_slot     int  not null check (player_slot in (1,2)),
  source          text not null default 'real',
  started_at      timestamptz not null,
  finished_at     timestamptz,
  created_at      timestamptz not null default now(),
  unique (race_id, player_slot)                    -- 2ª trava de dedupe (defesa em profundidade)
);

-- Amostras de telemetria EEG.
create table telemetry_points (
  id                bigint generated always as identity primary key,
  race_player_id    uuid not null references race_players(id) on delete cascade,
  t                 timestamptz not null,
  attention         int,
  meditation        int,
  poor_signal_level int,
  signal_status     text,
  eeg_power         jsonb               -- blob opaco; chaves do dispositivo preservadas
);

create index on telemetry_points (race_player_id);
create index on race_players (player_id);
create index on race_players (race_id);
```

**Notas:**
- `player_slot` (1|2) é o slot na corrida (= `playerId` do edge `[ev — session_manager]`);
  `player_id` é o FK ao jogador canônico (resolvido pela API via email). Renomeado para
  evitar colisão semântica com o `player_id:int` do contrato original.
- **Dupla idempotência:** `unique(idempotency_key)` **e** `unique(race_id, player_slot)`.
  Se o edge gerar um `jobId` novo numa re-consolidação, a 2ª trava ainda impede duplicar
  o resultado do jogador.
- **Fim é por-jogador** [decisão do dono]: a corrida tem 2 jogadores que terminam em
  momentos diferentes. `races` **não** tem `finished_at` — o fim é a verdade por-jogador em
  `race_players.finished_at`. `races.started_at` é o início compartilhado (o edge cria a
  sessão com um único `startedAt` no `raceStarted` `[ev — session_manager.onRaceStarted]`);
  vem do payload e é fixado no 1º POST (`on conflict do nothing`). Duração por-jogador é
  derivável (`race_players.finished_at - races.started_at`).
- **Mesmo email nos dois slots** (ex.: email default de kiosk): ambos `race_players`
  apontam o mesmo `player_id`, mas `unique(race_id, player_slot)` permite (slots diferentes).
  Caso de teste explícito.
- **Telemetria vazia** é válida (jogador humano sem amostras): a corrida persiste mesmo assim.

---

## 4. Identidade e vínculo tardio (o claim)

**No ingest:** `upsert` em `players` por email normalizado (`insert ... on conflict (email)
do update set email = excluded.email returning id`, ou select-then-insert) — resolve ou cria
o jogador. **Nunca** toca em `user_id`.

**No cadastro (claim):** trigger em `auth.users` que dispara **quando o email é confirmado**
(transição de `email_confirmed_at` de null → não-null), executando:

```sql
update players
   set user_id = NEW.id
 where email = lower(trim(NEW.email))
   and user_id is null;
```

Se ainda não existe `players` para aquele email (usuário se cadastrou antes de correr),
o trigger cria a linha com `user_id` já setado, para corridas futuras vincularem.

**Segurança (o ponto crítico):** o vínculo só acontece com **email verificado pelo Supabase**.
`mailer_autoconfirm = false` no projeto `[ev — config/auth da Management API, 2026-06-21]`,
ou seja, confirmação de email está ligada. O email digitado no kiosk/edge é entrada
**não-confiável** e, sozinho, nunca dá posse de corridas/métricas.

> **Invariante de que este design depende:** `mailer_autoconfirm` **deve permanecer
> `false`**. Se for desligado, signups passam a ser auto-confirmados e o modelo de posse
> enfraquece. Registrar como invariante de config do projeto.

---

## 5. Contrato (costura edge → API)

Canônico, snake_case, versionado, dono = a API. É o `cloud-sync-contract.md` §3
ajustado (`player_id:int` → `player_slot`). Validação **estrita** (campo fora do contrato
→ `422`). O mapping camelCase→snake_case é responsabilidade do **edge** (dispatcher NEU-7),
mantendo a fronteira limpa.

**Headers:** `x-edge-ingest-token: <EDGE_INGEST_TOKEN>` + `Content-Type: application/json`.

**Body:**
```jsonc
{
  "schema_version": "1.0",
  "idempotency_key": "<uuid-v4>",   // = jobId do edge
  "race_id": "<uuid-v4>",           // = sessionId do edge
  "player_slot": 1,                 // 1 | 2
  "player_email": "jogador@ex.com", // não-vazio
  "player_uuid": null,              // sempre null hoje (validateEmail é stub no edge [ev])
  "source": "real",
  "started_at": 1735689600000,      // epoch ms UTC
  "finished_at": 1735689660000,     // epoch ms UTC
  "telemetry_points": [
    { "t": 1735689601000, "attention": 80, "meditation": 55,
      "poor_signal_level": 0, "signal_status": "ok",
      "eeg_power": { "delta": 1, "theta": 2, "lowAlpha": 3, "highAlpha": 4,
                     "lowBeta": 5, "highBeta": 6, "lowGamma": 7, "highGamma": 8 } }
  ]
}
```

**Regras:** timestamps epoch ms → `timestamptz` via `to_timestamp(ms/1000.0)`;
`signal_status` ∈ {`ok`,`poor`,`no-signal`,`unknown`} `[ev — event_contracts.js]`;
`telemetry_points` pode ser vazio; `eeg_power` armazenado como `jsonb` sem reescrever chaves.

> O mapping bate campo-a-campo com o formato real do edge (`session_manager.js` record +
> `event_contracts.js` payload) `[ev — validado na investigação]`.

---

## 6. Edge Function `ingest-race` (fluxo)

`supabase/functions/ingest-race/index.ts`. Mantida **fina**:

1. Lê `x-edge-ingest-token`; compara em **tempo constante** com o secret
   `EDGE_INGEST_TOKEN`. Falha/ausente → `401`.
2. Faz parse + **validação estrita** do body contra o contrato (§5). Falha → `422`
   com `{ "error": "<code>", "message": "<humano>" }`.
3. Chama `supabase.rpc('ingest_race', { payload })` usando a **service_role key**
   (injetada pela plataforma `[hip — confirmar injeção automática de SUPABASE_SERVICE_ROLE_KEY]`).
4. Traduz o retorno da função em status HTTP (§7).
5. **Logging estruturado** (JSON) em cada caminho (criado / duplicado / 401 / 422 / erro),
   em paridade com o broker do edge `[ev — logging JSON estruturado no edge]`. **Sem vazar
   PII/segredo:** não logar email cru nem o token; usar `race_id`/`idempotency_key`/`player_slot`.

**Deploy:** `verify_jwt=false` (a função valida o token custom ela mesma). Configurar em
`supabase/config.toml`:
```toml
[functions.ingest-race]
verify_jwt = false
```
> `[hip — não testei]` que `verify_jwt=false` + validação de header custom funciona como
> descrito nesta versão do Supabase CLI (2.107.0). **Verificar** com `supabase functions
> serve` local antes de confiar.

**Função SQL `ingest_race(payload jsonb) returns jsonb`** (transacional; `language plpgsql`):
- upsert `players` por email normalizado → `player_id`;
- upsert `races` (`insert ... on conflict (id) do nothing`; `started_at` vem do payload);
- insert `race_players` `on conflict (idempotency_key) do nothing` **e** respeitando
  `unique(race_id, player_slot)`;
- se já existia (replay) → retorna `{ "status": "duplicate" }` (a função trata como sucesso);
- insert das `telemetry_points` (somente quando a linha de `race_players` foi criada agora);
- retorna `{ "status": "created" | "duplicate" }`.

> `security definer` é **dispensável**: só a Edge Function (service_role) chama a RPC e
> service_role bypassa RLS. Usar a forma simples (`security invoker`).

---

## 7. Semântica de resposta (alinha com o retry do dispatcher NEU-7)

| Status | Quando | Edge faz |
|---|---|---|
| `200` | sucesso (`created`) **ou** replay idempotente (`duplicate`) | job sai da fila |
| `401` | token inválido/ausente | permanente → dead-letter, log `error` |
| `422` | body inválido / fora do contrato | permanente → dead-letter, log `error` |
| `5xx` / timeout | erro transitório (DB/rede) | retry com backoff |

Replay do mesmo `idempotency_key` **sempre** responde `2xx` sem duplicar (idempotência
no banco). Corpo de erro: `{ "error": "<code>", "message": "<humano>" }`.

---

## 8. Segurança / RLS

- RLS **habilitado** em todas as 4 tabelas, **sem policy de escrita pública**. Só a
  service_role (server-side, na Edge Function) escreve.
- Policies de **leitura** (para o read-path futuro) serão definidas no sub-projeto (2):
  cada usuário lê apenas linhas onde `players.user_id = auth.uid()`. Fora de escopo aqui,
  mas o schema já suporta (FK `players.user_id`).
- `EDGE_INGEST_TOKEN` é secret da função (`supabase secrets set`), forte e rotacionável.
- service_role e secrets **nunca** no chat/disco/repo. Chaves no formato novo `sb_*`.

---

## 9. Testes (a prova)

Contra Supabase local (`supabase start` / `functions serve`):
- POST canônico válido → `200` + linhas em `players`/`races`/`race_players`/`telemetry_points`.
- **Replay mesma `idempotency_key` → `200`, zero duplicata.**
- `(race_id, player_slot)` repetido com `idempotency_key` diferente → não duplica.
- Token errado/ausente → `401`. Body inválido (campo faltando, enum errado) → `422`.
- Email sem conta → corrida gravada; depois "email confirmado" (simular) → `players.user_id`
  vincula as corridas daquele email.
- Mesmo email nos dois slots → 2 linhas (slots distintos), 1 `player`.
- `telemetry_points` vazio → corrida persiste.

Unit (Deno test) para auth (tempo constante) + validação do contrato. Integração para o
fluxo completo via RPC. CI depois (não bloqueia o MVP local).

---

## 10. Hipóteses a verificar na implementação (não são fatos)

> **SIGN-OFF — 2026-06-21 (Tasks 4, 7 e 8)**

- `[ev — CONFIRMADO TRUE]` **H1:** `verify_jwt=false` + validação de header custom no
  Supabase atual. Prova: `scripts/proof-ingest.sh` retornou `PROOF OK: 200 / 200(sem-dup) / 401 / 422`
  enviando apenas `x-edge-ingest-token` (sem `apikey`/`Authorization`). A flag
  `--no-verify-jwt` no `serve` **não** foi necessária; `verify_jwt=false` no
  `config.toml` foi suficiente.

- `[ev — CONFIRMADO TRUE]` **H2:** Edge Function injeta `SUPABASE_SERVICE_ROLE_KEY` e
  `SUPABASE_URL` em runtime. As variáveis foram auto-injetadas pelo `supabase functions serve`;
  linhas gravadas via `rpc('ingest_race', …)` com service_role sem configuração adicional.

- `[ev — RESOLVIDO]` **Claim em `auth.users` (colunas NOT NULL):** o insert de teste
  (Task 4) não exigiu colunas extras além do conjunto mínimo
  (`instance_id, id, aud, role, email, created_at, updated_at`) nesta versão do Supabase local.

- `[ev — NOVO ACHADO]` **GRANT DML explícito para service_role:** `ingest_race` é
  `SECURITY INVOKER`; service_role bypassa RLS mas **não** herda permissões de tabela
  automaticamente. Solução: migration `20260621230000_grant_service_role.sql`
  (SELECT/INSERT nas 4 tabelas + EXECUTE na função). O GRANT é idempotente.

- `[hip — NÃO MEDIDO — RISCO ABERTO]` **Volume de telemetria:** não foi medido com
  uma corrida real do simulador do edge. Não é possível afirmar que o payload cabe nos
  limites de tempo/tamanho da Edge Function. **Ação necessária antes de produção:**
  rodar o simulador do edge end-to-end, medir o payload real e validar latência.
  Se grande: inserir em batch ou capar telemetria no cliente.

- `[invariante — mantido]` `mailer_autoconfirm` permanece `false` (segurança do
  claim depende de email verificado — `auth.users.email_confirmed_at IS NOT NULL`).

---

## 11. O que este sub-projeto NÃO faz (para evitar inferência)

- Não implementa o dispatcher do edge (NEU-7) — outro repo/sessão. Apenas define o alvo.
- Não implementa leitura/dashboard/ranking/métricas/IA/Telegram.
- Não resolve `player_uuid` de verdade (fica `null`; depende de identificação no edge, NEU-17).
  Mantido no contrato deliberadamente para não quebrar o schema quando NEU-17 existir.
- Não decide hospedagem de uma API standalone — a Edge Function é o único compute agora.
- **Gaps conhecidos, deferidos de propósito (não-MVP):** rate-limiting / anti-abuse no
  ingest (hoje há 1 cliente confiável); validação de *plausibilidade* de timestamps além do
  tipo (ex.: `started_at = 0`, que o `.env` vazio do PR #4 já mostrou ser possível
  `[ev — PR #4]`); backpressure para payloads de telemetria muito grandes (ver risco §10).
```
