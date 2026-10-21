import { assertEquals } from "jsr:@std/assert@1";
import { criarHandler } from "./handler.ts";

function req(metodo: string, token?: string): Request {
  return new Request("http://localhost/send-messages", {
    method: metodo,
    headers: token === undefined ? {} : { "x-cron-token": token },
  });
}

Deno.test("sem a Brevo configurada: 503 e nao prepara nada (nada fica travado)", async () => {
  let rodou = false;
  const h = criarHandler({ cronToken: "tok", pronto: false, rodar: () => {
    rodou = true;
    return Promise.resolve({ enviadas: 0, falhas: 0 });
  } });
  const r = await h(req("POST", "tok"));
  assertEquals(r.status, 503);
  assertEquals(await r.json(), { erro: "nao_configurada" });
  assertEquals(rodou, false);
});

Deno.test("token do cron errado ou ausente: 401", async () => {
  let rodou = false;
  const h = criarHandler({ cronToken: "tok", pronto: true, rodar: () => {
    rodou = true;
    return Promise.resolve({ enviadas: 0, falhas: 0 });
  } });
  assertEquals((await h(req("POST", "outro"))).status, 401);
  assertEquals((await h(req("POST"))).status, 401);
  assertEquals(rodou, false);
});

Deno.test("cron token vazio no ambiente nunca autoriza", async () => {
  const h = criarHandler({ cronToken: "", pronto: true, rodar: () => Promise.resolve({ enviadas: 0, falhas: 0 }) });
  assertEquals((await h(req("POST", ""))).status, 401);
});

Deno.test("GET: 405", async () => {
  const h = criarHandler({ cronToken: "tok", pronto: true, rodar: () => Promise.resolve({ enviadas: 0, falhas: 0 }) });
  assertEquals((await h(req("GET", "tok"))).status, 405);
});

Deno.test("ok: 200 com as contagens", async () => {
  const h = criarHandler({ cronToken: "tok", pronto: true, rodar: () => Promise.resolve({ enviadas: 2, falhas: 1 }) });
  const r = await h(req("POST", "tok"));
  assertEquals(r.status, 200);
  assertEquals(await r.json(), { enviadas: 2, falhas: 1 });
});

Deno.test("erro ao preparar (banco fora): 500 sem detalhe", async () => {
  const h = criarHandler({ cronToken: "tok", pronto: true, rodar: () => Promise.reject(new Error("db fora")) });
  const r = await h(req("POST", "tok"));
  assertEquals(r.status, 500);
  assertEquals(await r.json(), { erro: "falha_interna" });
});
