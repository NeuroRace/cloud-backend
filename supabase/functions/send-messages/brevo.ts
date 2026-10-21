// Envio de um e-mail pela API transacional da Brevo.
// https://developers.brevo.com/reference/sendtransacemail

export type EmailMontado = {
  para: string;
  assunto: string;
  html: string;
  texto: string;
  cancelarInscricaoUrl: string;
};
export type ResultadoEnvio = { ok: true; id: string } | { ok: false; erro: string; definitivo: boolean };

const URL_BREVO = "https://api.brevo.com/v3/smtp/email";
const TIMEOUT_MS = 10_000;

/**
 * 201 -> ok. 400 -> definitivo (dado invalido nao melhora tentando de novo). Resto (401/403/429/5xx,
 * rede, timeout) -> temporario. O erro so leva o status e o codigo da Brevo: nunca a chave nem o destino.
 */
export async function enviarBrevo(
  fetchFn: typeof fetch, apiKey: string, remetente: string, e: EmailMontado,
): Promise<ResultadoEnvio> {
  let resp: Response;
  try {
    resp = await fetchFn(URL_BREVO, {
      method: "POST",
      headers: { "api-key": apiKey, "content-type": "application/json", "accept": "application/json" },
      body: JSON.stringify({
        sender: { name: "NeuroRace", email: remetente },
        to: [{ email: e.para }],
        subject: e.assunto,
        htmlContent: e.html,
        textContent: e.texto,
        headers: {
          "List-Unsubscribe": `<${e.cancelarInscricaoUrl}>`,
          "List-Unsubscribe-Post": "List-Unsubscribe=One-Click",
        },
      }),
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
  } catch (err) {
    return { ok: false, erro: `brevo rede: ${err instanceof Error ? err.name : "erro"}`, definitivo: false };
  }

  if (resp.status === 201) {
    const corpo = await resp.json().catch(() => ({}));
    return { ok: true, id: typeof corpo?.messageId === "string" ? corpo.messageId : "" };
  }
  const corpo = await resp.json().catch(() => null);
  const codigo = typeof corpo?.code === "string" && /^[a-z_]{1,40}$/.test(corpo.code) ? ` ${corpo.code}` : "";
  return { ok: false, erro: `brevo ${resp.status}${codigo}`, definitivo: resp.status === 400 };
}
