import { assertEquals } from "jsr:@std/assert@1";
import { assinar } from "../_shared/links.ts";
import { criarHandler, type DepsAcoes } from "./handler.ts";

const SEGREDO = "segredo-de-teste";
const SITE = "https://neurorace-v2.vercel.app";
const AGORA = 1_800_000_000;
const MSG = "11200000-0000-0000-0000-000000000001";
const URL_FN = "https://x.supabase.co/functions/v1/message-actions";

function montar(extra: Partial<DepsAcoes> = {}) {
  const chamadas: string[] = [];
  const h = criarHandler({
    segredo: SEGREDO,
    siteUrl: SITE,
    agoraSeg: () => AGORA,
    bloquear: (m) => {
      chamadas.push(`bloquear:${m}`);
      return Promise.resolve(true);
    },
    recusar: (m) => {
      chamadas.push(`recusar:${m}`);
      return Promise.resolve("recusado");
    },
    ...extra,
  });
  return { h, chamadas };
}
const token = (a: "sair" | "recusar", exp = AGORA + 60) => assinar(SEGREDO, { a, m: MSG, exp });
const post = (t: string) =>
  new Request(URL_FN, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ t }) });

Deno.test("Pronto 7: assinatura errada -> 403 e nada muda", async () => {
  const { h, chamadas } = montar();
  const outro = await assinar("outro-segredo", { a: "sair", m: MSG, exp: AGORA + 60 });
  const r = await h(post(outro));
  assertEquals(r.status, 403);
  assertEquals(await r.json(), { erro: "assinatura" });
  assertEquals(chamadas, []);
});

Deno.test("link expirado -> 403 e nada muda", async () => {
  const { h, chamadas } = montar();
  const r = await h(post(await token("recusar", AGORA)));
  assertEquals(r.status, 403);
  assertEquals(chamadas, []);
});

Deno.test("Review Focus 1: GET (antivirus abrindo o link) -> 405 e nada muda", async () => {
  const { h, chamadas } = montar();
  const r = await h(new Request(`${URL_FN}?t=${await token("recusar")}`));
  assertEquals(r.status, 405);
  assertEquals(chamadas, []);
});

Deno.test("sair: bloqueia o contato da mensagem uma vez", async () => {
  const { h, chamadas } = montar();
  const r = await h(post(await token("sair")));
  assertEquals(r.status, 200);
  assertEquals(await r.json(), { ok: true, acao: "sair" });
  assertEquals(chamadas, [`bloquear:${MSG}`]);
});

Deno.test("sair com mensagem que nao existe mais -> 404", async () => {
  const { h } = montar({ bloquear: () => Promise.resolve(false) });
  const r = await h(post(await token("sair")));
  assertEquals(r.status, 404);
});

Deno.test("recusar: devolve o resultado do banco", async () => {
  for (const resultado of ["recusado", "ja_resolvido", "invalido"]) {
    const { h, chamadas } = montar({ recusar: () => Promise.resolve(resultado) });
    const r = await h(post(await token("recusar")));
    assertEquals(r.status, 200);
    assertEquals(await r.json(), { ok: true, acao: "recusar", resultado });
    assertEquals(chamadas, []);
  }
});

Deno.test("um clique (RFC 8058): POST com o token na URL e corpo de formulario", async () => {
  const { h, chamadas } = montar();
  const r = await h(new Request(`${URL_FN}?t=${await token("sair")}`, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: "List-Unsubscribe=One-Click",
  }));
  assertEquals(r.status, 200);
  assertEquals(chamadas, [`bloquear:${MSG}`]);
});

Deno.test("sem token -> 403", async () => {
  const { h, chamadas } = montar();
  assertEquals((await h(new Request(URL_FN, { method: "POST", body: "{}" }))).status, 403);
  assertEquals((await h(new Request(URL_FN, { method: "POST", body: "nao e json" }))).status, 403);
  assertEquals(chamadas, []);
});

Deno.test("CORS: so o site, nunca *", async () => {
  const { h } = montar();
  const pre = await h(new Request(URL_FN, { method: "OPTIONS" }));
  assertEquals(pre.status, 204);
  assertEquals(pre.headers.get("access-control-allow-origin"), SITE);
  assertEquals(pre.headers.get("access-control-allow-methods"), "POST, OPTIONS");
  const r = await h(post(await token("sair")));
  assertEquals(r.headers.get("access-control-allow-origin"), SITE);
});

Deno.test("erro do banco -> 500 sem detalhe", async () => {
  const { h } = montar({ recusar: () => Promise.reject(new Error("db fora: segredo")) });
  const r = await h(post(await token("recusar")));
  assertEquals(r.status, 500);
  assertEquals(await r.json(), { erro: "falha_interna" });
});
