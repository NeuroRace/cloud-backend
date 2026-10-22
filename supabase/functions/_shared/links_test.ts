import { assertEquals, assertNotEquals, assertRejects } from "jsr:@std/assert@1";
import { assinar, EXPIRA_RECUSAR_S, EXPIRA_SAIR_S, type PayloadLink, verificar } from "./links.ts";

const SEGREDO = "segredo-de-teste";
const MSG = "11200000-0000-0000-0000-000000000001";
const AGORA = 1_800_000_000;
const sair: PayloadLink = { a: "sair", m: MSG, exp: AGORA + 60 };

Deno.test("ida e volta: o token assinado volta igual", async () => {
  const t = await assinar(SEGREDO, sair);
  assertEquals(await verificar(SEGREDO, t, AGORA), sair);
});

Deno.test("token nao carrega e-mail nem nada alem de acao, mensagem e validade", async () => {
  const t = await assinar(SEGREDO, sair);
  const json = new TextDecoder().decode(
    Uint8Array.from(atob(t.split(".")[0].replaceAll("-", "+").replaceAll("_", "/")), (c) => c.charCodeAt(0)),
  );
  assertEquals(Object.keys(JSON.parse(json)).sort(), ["a", "exp", "m"]);
});

Deno.test("assinatura com outro segredo: null", async () => {
  const t = await assinar("outro-segredo", sair);
  assertEquals(await verificar(SEGREDO, t, AGORA), null);
});

Deno.test("payload alterado (troca sair por recusar): null", async () => {
  const t = await assinar(SEGREDO, sair);
  const [, sig] = t.split(".");
  const forjado = btoa(JSON.stringify({ ...sair, a: "recusar" })).replaceAll("+", "-").replaceAll("/", "_")
    .replaceAll("=", "");
  assertEquals(await verificar(SEGREDO, `${forjado}.${sig}`, AGORA), null);
});

Deno.test("expirado: null", async () => {
  const t = await assinar(SEGREDO, sair);
  assertEquals(await verificar(SEGREDO, t, AGORA + 60), null);
});

Deno.test("acao desconhecida: null", async () => {
  const t = await assinar(SEGREDO, { ...sair, a: "apagar" } as unknown as PayloadLink);
  assertEquals(await verificar(SEGREDO, t, AGORA), null);
});

Deno.test("mensagem que nao e uuid: null", async () => {
  const t = await assinar(SEGREDO, { ...sair, m: "1; drop table" });
  assertEquals(await verificar(SEGREDO, t, AGORA), null);
});

Deno.test("lixo: null", async () => {
  for (const t of ["", "abc", "a.b.c", ".", "x.", ".y", "%%%.%%%"]) {
    assertEquals(await verificar(SEGREDO, t, AGORA), null);
  }
});

Deno.test("segredo vazio: nao assina e nunca valida", async () => {
  await assertRejects(() => assinar("", sair));
  const t = await assinar(SEGREDO, sair);
  assertEquals(await verificar("", t, AGORA), null);
});

Deno.test("validades: sair 90 dias, recusar 2 dias", () => {
  assertEquals(EXPIRA_SAIR_S, 90 * 86400);
  assertEquals(EXPIRA_RECUSAR_S, 2 * 86400);
  assertNotEquals(EXPIRA_SAIR_S, EXPIRA_RECUSAR_S);
});
