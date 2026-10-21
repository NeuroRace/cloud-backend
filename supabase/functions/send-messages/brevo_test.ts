import { assertEquals, assertFalse, assertStringIncludes } from "jsr:@std/assert@1";
import { type EmailMontado, enviarBrevo } from "./brevo.ts";

const EMAIL: EmailMontado = {
  para: "ana@neu112.test",
  assunto: "Você venceu",
  html: "<p>oi</p>",
  texto: "oi",
  cancelarInscricaoUrl: "https://x.supabase.co/functions/v1/message-actions?t=abc",
};
const KEY = "xkeysib-segredo";

function fetchQueResponde(status: number, corpo: unknown, capturado?: { req?: Request }) {
  return ((input: string | URL | Request, init?: RequestInit) => {
    if (capturado) capturado.req = new Request(input, init);
    return Promise.resolve(new Response(JSON.stringify(corpo), { status }));
  }) as typeof fetch;
}

Deno.test("201: ok com o messageId", async () => {
  const cap: { req?: Request } = {};
  const r = await enviarBrevo(fetchQueResponde(201, { messageId: "<id@brevo>" }, cap), KEY, "premios@neurorace.com.br", EMAIL);
  assertEquals(r, { ok: true, id: "<id@brevo>" });
  assertEquals(cap.req!.url, "https://api.brevo.com/v3/smtp/email");
  assertEquals(cap.req!.method, "POST");
  assertEquals(cap.req!.headers.get("api-key"), KEY);
  const body = await cap.req!.json();
  assertEquals(body.sender, { name: "NeuroRace", email: "premios@neurorace.com.br" });
  assertEquals(body.to, [{ email: "ana@neu112.test" }]);
  assertEquals(body.subject, "Você venceu");
  assertEquals(body.htmlContent, "<p>oi</p>");
  assertEquals(body.textContent, "oi");
  assertEquals(body.headers["List-Unsubscribe"], `<${EMAIL.cancelarInscricaoUrl}>`);
  assertEquals(body.headers["List-Unsubscribe-Post"], "List-Unsubscribe=One-Click");
});

Deno.test("400: falha definitiva (endereco invalido nao melhora tentando de novo)", async () => {
  const r = await enviarBrevo(fetchQueResponde(400, { code: "invalid_parameter", message: "email is not valid" }), KEY, "r@x", EMAIL);
  assertEquals(r.ok, false);
  if (!r.ok) {
    assertEquals(r.definitivo, true);
    assertStringIncludes(r.erro, "400");
  }
});

Deno.test("500, 429 e 401: falha temporaria", async () => {
  for (const status of [500, 503, 429, 401]) {
    const r = await enviarBrevo(fetchQueResponde(status, { message: "x" }), KEY, "r@x", EMAIL);
    assertEquals(r.ok, false);
    if (!r.ok) assertEquals(r.definitivo, false, `status ${status}`);
  }
});

Deno.test("erro de rede: falha temporaria", async () => {
  const quebra = (() => Promise.reject(new TypeError("connection refused"))) as typeof fetch;
  const r = await enviarBrevo(quebra, KEY, "r@x", EMAIL);
  assertEquals(r.ok, false);
  if (!r.ok) assertEquals(r.definitivo, false);
});

Deno.test("o erro gravado nunca leva a api key nem o destino", async () => {
  const eco = ((_: unknown, init?: RequestInit) =>
    Promise.resolve(new Response(`eco: ${init?.body} ${KEY}`, { status: 400 }))) as typeof fetch;
  const r = await enviarBrevo(eco, KEY, "r@x", EMAIL);
  assertFalse(r.ok);
  if (!r.ok) {
    assertFalse(r.erro.includes(KEY), "nao vaza a api key");
    assertFalse(r.erro.includes("ana@neu112.test"), "nao vaza o destino");
  }
});
