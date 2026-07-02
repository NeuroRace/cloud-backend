# CLAUDE.md — cloud-backend (API do NeuroRace)

Guia para agentes de IA (e humanos) trabalharem neste repo. Leia antes de mexer.

## Princípios (não-negociáveis)
- **Honestidade brutal:** problemas antes de positivos; sem suavizar.
- **Evidência, nunca inferência:** não afirme "pronto/passa/deployado" sem prova (output de comando, SHA+diff, resposta HTTP, caminho de arquivo). Se não pôde verificar, diga "não verifiquei — assumindo X" e pare.
- **Não-regressão:** não declare concluído sem a suíte relevante verde. Toda mudança é aditiva/reversível por padrão.
- **Escopo:** faça exatamente o pedido; sinalize o resto, não toque sem ok.
- **PT-BR no chat.**

## O que é
API do NeuroRace no **Supabase** (não há servidor próprio). Recebe o resultado de corridas EEG do `edge-service`, guarda em Postgres, e serve dados para o front (dashboard próprio + ranking). O front fala **direto com o Supabase** (`@supabase/supabase-js` + RLS); a escrita vem só do edge.

Projeto hospedado: ref **`wtaulbdkgrnrtbfezaxw`** · endpoint de ingest: `https://wtaulbdkgrnrtbfezaxw.supabase.co/functions/v1/ingest-race`.

## Arquitetura (o que existe hoje — evidência: `supabase/migrations/`)
- **Edge Function `ingest-race`** (`supabase/functions/ingest-race/`, Deno): recebe o POST do edge, valida token (`x-edge-ingest-token`, `verify_jwt=false`) e o contrato, chama `ingest_race` via rpc com `service_role`. Arquivos: `index.ts` (handler), `auth.ts` (compare tempo-constante), `contract.ts` (validação).
- **Postgres (8 migrations)**:
  - `init_schema` — 4 tabelas de **dados**: `players` (jogador por email), `races`, `race_players` (resultado por jogador), `telemetry_points` (EEG). RLS ON.
  - `ingest_race_fn` + `fix_ingest_race` — função `ingest_race(jsonb)` transacional idempotente.
  - `claim_trigger` — `handle_email_confirmed`: vincula `players.user_id` quando o email é confirmado.
  - `grant_service_role` — grants DML ao `service_role`.
  - `rls_read_policies` — 4 policies `for select to authenticated` (own-data) nas tabelas de dados.
  - `profiles` — tabela `profiles` (alias `display_name` citext único) + RLS own + trigger `handle_new_user_profile` (cria profile no signup).
  - `get_leaderboard` — função `security definer` pública (ranking por `best_time`, sem PII).
- **Tabelas:** `players, races, race_players, telemetry_points, profiles`. **Funções:** `ingest_race, handle_email_confirmed, handle_new_user_profile, get_leaderboard`.

## Rodar local (precisa de Docker)
```bash
docker info            # Docker precisa estar de pé
supabase start
supabase db reset      # aplica TODAS as migrations do zero
```

## Testar (é assim que se prova não-regressão)
```bash
DB="postgresql://postgres:postgres@127.0.0.1:54322/postgres"
# Banco: roda TODOS os testes em supabase/tests/ via glob (teste novo entra sozinho)
for f in supabase/tests/*.sql; do echo "== $f =="; psql "$DB" -v ON_ERROR_STOP=1 -f "$f" || exit 1; done
# Função (Deno)
deno test supabase/functions/ingest-race/
# Integração e2e (requer `supabase functions serve ingest-race --env-file supabase/functions/.env`)
EDGE_INGEST_TOKEN=dev-only-change-me ./scripts/proof-ingest.sh
```
Estado verde de referência (verificado 2026-07-02): **6 testes SQL OK + `31 passed | 0 failed` no Deno**. **Não declare concluído sem isso verde.**

## Convenções (best practices deste repo)
- **Migrations são aditivas** — não edite uma já aplicada em produção; crie uma nova (`supabase migration new <nome>`). Exceção: uma migration ainda **não** mergeada/deployada (PR aberto) pode ser editada in-place.
- **Escrita nas 4 tabelas de dados só via `service_role`** (o ingest). RLS de leitura é own-data (`auth.uid()`). `profiles` é a única tabela com escrita via RLS (o usuário edita o próprio `display_name`).
- **Leaderboard nunca expõe PII** — `get_leaderboard` devolve só `rank/display_name/score` (sem email/ids). É `security definer` + `set search_path`.
- **Toda feature = migration + teste + review.** Testes SQL usam `assert` reais (não no-op) e limpam o próprio seed no fim.
- **`mailer_autoconfirm` DEVE ser `false` em produção** (confirmação de email obrigatória) — é o que sustenta o vínculo seguro de corridas.

## Fluxo de trabalho
1. Branch a partir de `main` (`git checkout main && git pull`, depois `git checkout -b feat/...`). Não commite direto em `main` (protegida; push é bloqueado por hook).
2. TDD por task (teste falha → implementa → passa → commit). Para planos grandes, use `superpowers:subagent-driven-development` (implementer + review por task) e `/pr-review-toolkit:review-pr` no fim.
3. **Worktrees:** opcionais — úteis para isolar trabalho paralelo (`superpowers:using-git-worktrees`); este repo até aqui usou branches simples in-place, o que basta para trabalho serial.
4. PR → review → merge. Depois: `supabase db push` no hospedado (só DDL; **verifique read-only e NÃO toque nos dados reais do edge**).
5. Deletar a branch após o merge (local e remoto).

## Segredos / tokens (NUNCA ecoar, NUNCA commitar)
- Tokens ficam em **variáveis de ambiente**: `SUPABASE_ACCESS_TOKEN` (Management API + CLI) e `LINEAR_API_KEY` (API do Linear).
- **Já estão configurados nesta máquina** (macOS Keychain → env via `~/.zshrc` que faz source de `~/.neurorace-secrets.sh`). Numa sessão nova as env vars **já vêm populadas** — apenas **use** `$SUPABASE_ACCESS_TOKEN` / `$LINEAR_API_KEY`, não refaça o setup. (O bloco "Setup de tokens" abaixo é só para uma máquina NOVA.) Setup global por-usuário: vale em qualquer diretório desta conta, não só neste repo.
- Use `$SUPABASE_ACCESS_TOKEN` / `$LINEAR_API_KEY` nos comandos (`curl -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" ...`). O valor expande em runtime; **nunca** o imprima.
- `.env`, `supabase/functions/.env`, `.secret.prod.env` são gitignored. `EDGE_INGEST_TOKEN` de produção (secret da Edge Function) fica em `.secret.prod.env` (local, `chmod 600`).
- **NÃO** rode `supabase login` com token efêmero (grava em disco); prefira `SUPABASE_ACCESS_TOKEN` como env.

### Setup de tokens (só numa máquina NOVA — já feito nesta)
```bash
# 1) guarde os tokens no Keychain (não commite, não cole em chat público)
security add-generic-password -s neurorace-supabase -a "$USER" -w '<SUPABASE_PAT>'
security add-generic-password -s neurorace-linear   -a "$USER" -w '<LINEAR_API_KEY>'
# 2) faça o ~/.zshrc dar source no helper (o ~/.neurorace-secrets.sh já foi criado, lê do Keychain):
echo '[ -f ~/.neurorace-secrets.sh ] && source ~/.neurorace-secrets.sh' >> ~/.zshrc
# 3) abra um shell novo e confirme (sem revelar o valor):
[ -n "$SUPABASE_ACCESS_TOKEN" ] && echo "SUPABASE ok" ; [ -n "$LINEAR_API_KEY" ] && echo "LINEAR ok"
```

## Ponteiros
- Specs/planos: `docs/superpowers/specs/` e `docs/superpowers/plans/`.
- Guia do front (como conectar/ler): `docs/frontend-integration.md`.
- Contrato de escrita edge→cloud: `../edge-service/docs/cloud-sync-contract.md`.
- Linear: time **NEU**, projeto **cloud-backend**. Issues relevantes: NEU-58 (ingest), NEU-63 (leitura), NEU-65 (ranking), NEU-67 (novas métricas), NEU-66 (game: "parou no meio").
- `artifacts/` e `inbox/` são scratch **não versionado** (gitignored) — não commite.
