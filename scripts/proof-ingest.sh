#!/usr/bin/env bash
set -euo pipefail
URL="http://127.0.0.1:54321/functions/v1/ingest-race"
DB="postgresql://postgres:postgres@127.0.0.1:54322/postgres"
case "$DB" in *127.0.0.1:54322*|*localhost:54322*) ;; *) echo "REFUSED: proof so roda contra o Supabase local (porta 54322)"; exit 1 ;; esac
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
