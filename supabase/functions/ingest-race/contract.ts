export type ValidationResult = { ok: true } | { ok: false; error: string };

const SIGNAL_STATUS = new Set(["ok", "poor", "no-signal", "unknown"]);
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
// NEU-159: celular no formato do edge, +55 + DDD + 9 digitos (mesma regra de players.phone).
const PHONE_RE = /^\+55[1-9][0-9]9[0-9]{8}$/;
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
  // Vem um dos dois: e-mail (como sempre) ou, no lugar dele, player_phone (NEU-159).
  const hasEmail = typeof b.player_email === "string" && b.player_email.trim() !== "";
  const hasPhone = b.player_phone !== undefined && b.player_phone !== null;
  // Apelido do site (profiles.display_name): mesma regra do banco, 3 a 20 caracteres (char_length,
  // por isso Array.from: emoji conta 1) sem espaco nas pontas.
  if (b.player_nickname !== undefined && b.player_nickname !== null) {
    const n = b.player_nickname;
    if (typeof n !== "string" || n !== n.trim() || Array.from(n).length < 3 || Array.from(n).length > 20)
      return fail("player_nickname_invalid");
    if (hasEmail || hasPhone) return fail("player_nickname_and_other_contact");
  } else if (hasPhone) {
    if (typeof b.player_phone !== "string" || !PHONE_RE.test(b.player_phone)) return fail("player_phone_invalid");
    if (hasEmail) return fail("player_email_and_phone_both");
  } else if (!hasEmail) return fail("player_email_required");
  if (b.player_uuid !== null && (typeof b.player_uuid !== "string" || !UUID_RE.test(b.player_uuid)))
    return fail("player_uuid_must_be_uuid_or_null");
  if (b.source !== "real" && b.source !== "bot") return fail("source_invalid");
  if (!isInt(b.started_at)) return fail("started_at_must_be_int");
  if (!isInt(b.finished_at)) return fail("finished_at_must_be_int");
  if ((b.finished_at as number) < (b.started_at as number)) return fail("finished_at_before_started_at");
  if (!Array.isArray(b.telemetry_points)) return fail("telemetry_points_must_be_array");

  for (const p of b.telemetry_points as unknown[]) {
    if (typeof p !== "object" || p === null) return fail("telemetry_point_must_be_object");
    const tp = p as Record<string, unknown>;
    if (!isInt(tp.t)) return fail("telemetry_t_must_be_int");
    if (!isInt(tp.attention)) return fail("telemetry_attention_must_be_int");
    if ((tp.attention as number) < 0 || (tp.attention as number) > 100) return fail("telemetry_attention_out_of_range");
    if (!isInt(tp.meditation)) return fail("telemetry_meditation_must_be_int");
    if ((tp.meditation as number) < 0 || (tp.meditation as number) > 100) return fail("telemetry_meditation_out_of_range");
    if (tp.poor_signal_level !== null && !isInt(tp.poor_signal_level))
      return fail("telemetry_poor_signal_level_invalid");
    if (tp.poor_signal_level !== null && ((tp.poor_signal_level as number) < 0 || (tp.poor_signal_level as number) > 200))
      return fail("telemetry_poor_signal_level_invalid");
    if (typeof tp.signal_status !== "string" || !SIGNAL_STATUS.has(tp.signal_status))
      return fail("telemetry_signal_status_invalid");
    if (typeof tp.eeg_power !== "object" || tp.eeg_power === null || Array.isArray(tp.eeg_power))
      return fail("telemetry_eeg_power_must_be_object");
  }
  return { ok: true };
}

// Resposta HTTP para o status devolvido pelo ingest_race. null = status inesperado (500).
export function rpcStatusResponse(status: unknown): { status: number; body: Record<string, string> } | null {
  if (status === "created" || status === "duplicate") return { status: 200, body: { status } };
  if (status === "unknown_nickname")
    return { status: 422, body: { error: "player_nickname_not_found", message: "no account with this nickname" } };
  return null;
}
