// Token dos links do e-mail ("Parar de receber", "Nao vou poder"): base64url(JSON).base64url(HMAC-SHA256).
// So leva a acao, o id da mensagem e a validade: nenhum e-mail ou telefone na URL.

export type AcaoLink = "sair" | "recusar";
export type PayloadLink = { a: AcaoLink; m: string; exp: number };

export const EXPIRA_SAIR_S = 90 * 86400;
export const EXPIRA_RECUSAR_S = 2 * 86400;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function b64url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes)).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}
function deB64url(s: string): Uint8Array<ArrayBuffer> {
  return Uint8Array.from(atob(s.replaceAll("-", "+").replaceAll("_", "/")), (c) => c.charCodeAt(0));
}
function chave(segredo: string): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "raw", new TextEncoder().encode(segredo), { name: "HMAC", hash: "SHA-256" }, false, ["sign", "verify"],
  );
}

export async function assinar(segredo: string, p: PayloadLink): Promise<string> {
  const corpo = b64url(new TextEncoder().encode(JSON.stringify({ a: p.a, m: p.m, exp: p.exp })));
  const sig = await crypto.subtle.sign("HMAC", await chave(segredo), new TextEncoder().encode(corpo));
  return `${corpo}.${b64url(new Uint8Array(sig))}`;
}

/** null em formato ruim, assinatura errada, expirado, acao desconhecida ou mensagem que nao e uuid. */
export async function verificar(segredo: string, token: string, agoraSeg: number): Promise<PayloadLink | null> {
  if (segredo === "") return null;
  const partes = token.split(".");
  if (partes.length !== 2 || partes[0] === "" || partes[1] === "") return null;
  try {
    // crypto.subtle.verify compara em tempo constante.
    const ok = await crypto.subtle.verify(
      "HMAC", await chave(segredo), deB64url(partes[1]), new TextEncoder().encode(partes[0]),
    );
    if (!ok) return null;
    const p = JSON.parse(new TextDecoder().decode(deB64url(partes[0])));
    if (p?.a !== "sair" && p?.a !== "recusar") return null;
    if (typeof p.m !== "string" || !UUID.test(p.m)) return null;
    if (typeof p.exp !== "number" || p.exp <= agoraSeg) return null;
    return { a: p.a, m: p.m, exp: p.exp };
  } catch {
    return null;
  }
}
