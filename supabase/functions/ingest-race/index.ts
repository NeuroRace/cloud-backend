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
