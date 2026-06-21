# cloud-backend — API do NeuroRace

Ingest de corridas (Supabase Edge Function `ingest-race`) + schema Postgres.
Spec: `docs/superpowers/specs/2026-06-21-cloud-backend-ingest-design.md`.

## Rodar local

1. `docker info` (precisa de Docker)
2. `supabase start`
3. `supabase db reset`  — aplica migrations
4. `cp .env.example supabase/functions/.env` e ajuste `EDGE_INGEST_TOKEN`
5. `supabase functions serve ingest-race --env-file supabase/functions/.env`

## Testes

```bash
# Banco (3 arquivos; cada um imprime "... OK" ao final)
DB="postgresql://postgres:postgres@127.0.0.1:54322/postgres"
psql "$DB" -v ON_ERROR_STOP=1 -f supabase/tests/schema_test.sql
psql "$DB" -v ON_ERROR_STOP=1 -f supabase/tests/ingest_race_test.sql
psql "$DB" -v ON_ERROR_STOP=1 -f supabase/tests/claim_test.sql

# Função (Deno)
deno test supabase/functions/ingest-race/

# Integração end-to-end (requer supabase functions serve ativo)
EDGE_INGEST_TOKEN=dev-only-change-me ./scripts/proof-ingest.sh
```

> Nota macOS: `supabase status -o env | grep -oP` não funciona no BSD grep.
> Use a URL de DB acima diretamente (válida para todos os ambientes locais padrão).

## Auth

Header `x-edge-ingest-token`. `verify_jwt=false` em `supabase/config.toml`.
service_role escreve server-side — nunca sai da Cloud.

Em produção: `supabase secrets set EDGE_INGEST_TOKEN=...` (nunca commitar o valor real).

## Invariante de segurança

`mailer_autoconfirm` DEVE permanecer `false` — o claim de corridas por email
depende de email verificado (`auth.users.email_confirmed_at IS NOT NULL`).
