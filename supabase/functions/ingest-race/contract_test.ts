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
Deno.test("race_id nao-uuid falha", () => {
  const r = validateIngestBody({ ...valid, race_id: "not-a-uuid" });
  assertEquals(r.ok ? "" : r.error, "race_id_must_be_uuid");
});
Deno.test("source invalido falha", () => {
  const r = validateIngestBody({ ...valid, source: "human" });
  assertEquals(r.ok ? "" : r.error, "source_invalid");
});
Deno.test("finished_at nao-int falha", () => {
  const r = validateIngestBody({ ...valid, finished_at: 1.5 });
  assertEquals(r.ok ? "" : r.error, "finished_at_must_be_int");
});
Deno.test("player_uuid nao-string-nao-null falha", () => {
  const r = validateIngestBody({ ...valid, player_uuid: 42 });
  assertEquals(r.ok ? "" : r.error, "player_uuid_must_be_uuid_or_null");
});
Deno.test("body null falha", () => {
  const r = validateIngestBody(null);
  assertEquals(r.ok ? "" : r.error, "body_must_be_object");
});
Deno.test("telemetry_points nao-array falha", () => {
  const r = validateIngestBody({ ...valid, telemetry_points: "x" });
  assertEquals(r.ok ? "" : r.error, "telemetry_points_must_be_array");
});
Deno.test("telemetry_point nao-object falha", () => {
  const r = validateIngestBody({ ...valid, telemetry_points: [null] });
  assertEquals(r.ok ? "" : r.error, "telemetry_point_must_be_object");
});
Deno.test("telemetry eeg_power nao-object falha", () => {
  const r = validateIngestBody({ ...valid,
    telemetry_points: [{ ...valid.telemetry_points[0], eeg_power: [] }] });
  assertEquals(r.ok ? "" : r.error, "telemetry_eeg_power_must_be_object");
});
Deno.test("telemetry t nao-int falha", () => {
  const r = validateIngestBody({ ...valid,
    telemetry_points: [{ ...valid.telemetry_points[0], t: 1.5 }] });
  assertEquals(r.ok ? "" : r.error, "telemetry_t_must_be_int");
});
Deno.test("telemetry attention nao-int falha", () => {
  const r = validateIngestBody({ ...valid,
    telemetry_points: [{ ...valid.telemetry_points[0], attention: "x" }] });
  assertEquals(r.ok ? "" : r.error, "telemetry_attention_must_be_int");
});
Deno.test("telemetry meditation nao-int falha", () => {
  const r = validateIngestBody({ ...valid,
    telemetry_points: [{ ...valid.telemetry_points[0], meditation: null }] });
  assertEquals(r.ok ? "" : r.error, "telemetry_meditation_must_be_int");
});
Deno.test("telemetry poor_signal_level invalido falha", () => {
  const r = validateIngestBody({ ...valid,
    telemetry_points: [{ ...valid.telemetry_points[0], poor_signal_level: 1.5 }] });
  assertEquals(r.ok ? "" : r.error, "telemetry_poor_signal_level_invalid");
});
Deno.test("player_uuid string valido passa", () => {
  const r = validateIngestBody({ ...valid, player_uuid: "99999999-9999-9999-9999-999999999999" });
  assertEquals(r.ok, true);
});
Deno.test("player_uuid nao-uuid falha", () => {
  const r = validateIngestBody({ ...valid, player_uuid: "not-a-uuid" });
  assertEquals(r.ok ? "" : r.error, "player_uuid_must_be_uuid_or_null");
});
Deno.test("telemetry attention > 100 falha", () => {
  const r = validateIngestBody({ ...valid, telemetry_points: [{ ...valid.telemetry_points[0], attention: 101 }] });
  assertEquals(r.ok ? "" : r.error, "telemetry_attention_out_of_range");
});
Deno.test("telemetry attention < 0 falha", () => {
  const r = validateIngestBody({ ...valid, telemetry_points: [{ ...valid.telemetry_points[0], attention: -1 }] });
  assertEquals(r.ok ? "" : r.error, "telemetry_attention_out_of_range");
});
Deno.test("telemetry meditation > 100 falha", () => {
  const r = validateIngestBody({ ...valid, telemetry_points: [{ ...valid.telemetry_points[0], meditation: 101 }] });
  assertEquals(r.ok ? "" : r.error, "telemetry_meditation_out_of_range");
});
Deno.test("telemetry poor_signal_level > 200 falha", () => {
  const r = validateIngestBody({ ...valid, telemetry_points: [{ ...valid.telemetry_points[0], poor_signal_level: 201 }] });
  assertEquals(r.ok ? "" : r.error, "telemetry_poor_signal_level_invalid");
});
Deno.test("finished_at before started_at falha", () => {
  const r = validateIngestBody({ ...valid, started_at: 2, finished_at: 1 });
  assertEquals(r.ok ? "" : r.error, "finished_at_before_started_at");
});
