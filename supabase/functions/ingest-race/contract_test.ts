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
