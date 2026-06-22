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
# Banco — roda TODOS os testes em supabase/tests/ (cada um imprime "... OK" ao final).
# O glob garante que qualquer teste novo entre no runner automaticamente.
DB="postgresql://postgres:postgres@127.0.0.1:54322/postgres"
for f in supabase/tests/*.sql; do
  echo "== $f =="; psql "$DB" -v ON_ERROR_STOP=1 -f "$f" || exit 1
done

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

A confirmação de email DEVE estar ligada **em produção** — o claim de corridas por
email depende de email verificado (`auth.users.email_confirmed_at IS NOT NULL`).

- **Produção (projeto hospedado):** na config de Auth do Supabase, `mailer_autoconfirm`
  DEVE permanecer `false` (autoconfirm desligado = confirmação exigida). Verificado via
  Management API em 2026-06-21.
- **Local (`supabase/config.toml`):** a chave equivalente é `[auth.email] enable_confirmations`,
  hoje `false` — tolerado localmente porque os testes setam `email_confirmed_at` diretamente.
  Não use o comportamento local como referência do invariante de produção.
