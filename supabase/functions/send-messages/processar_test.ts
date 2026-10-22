import { assertEquals } from "jsr:@std/assert@1";
import type { EmailMontado, ResultadoEnvio } from "./brevo.ts";
import type { MensagemFila } from "./montar.ts";
import { type DepsProcessar, processar } from "./processar.ts";

function msg(id: string): MensagemFila {
  return {
    id, envio_id: `e-${id}`, tipo: "corrida_registrada", destino: `${id}@neu112.test`, assunto: "A",
    corpo_texto: "T", corpo_html: null, premio_id: null,
  };
}
function email(m: MensagemFila): EmailMontado {
  return { para: m.destino, assunto: m.assunto, html: "h", texto: "t", cancelarInscricaoUrl: "u" };
}

// Deps com relogio de mentira e registro do que foi gravado e solto.
function deps(extra: Partial<DepsProcessar> = {}) {
  const gravados: [string, string, ResultadoEnvio][] = [];
  const soltos: string[] = [];
  const d: DepsProcessar = {
    preparar: () => Promise.resolve([msg("m1"), msg("m2"), msg("m3")]),
    montar: (m) => Promise.resolve(email(m)),
    enviar: (e) => Promise.resolve({ ok: true, id: `<${e.para}>` }),
    resultado: (m, r) => {
      gravados.push([m.id, m.envio_id, r]);
      return Promise.resolve();
    },
    soltar: (m) => {
      soltos.push(m.id);
      return Promise.resolve();
    },
    agoraMs: () => 0,
    prazoMs: 45_000,
    ...extra,
  };
  return { d, gravados, soltos };
}

Deno.test("Pronto 6: a Brevo fora numa mensagem nao trava as outras", async () => {
  const { d, gravados } = deps({
    enviar: (e) =>
      Promise.resolve(
        e.para.startsWith("m2") ? { ok: false, erro: "brevo 503", definitivo: false } : { ok: true, id: `<${e.para}>` },
      ),
  });
  const r = await processar(d);
  assertEquals(r, { enviadas: 2, falhas: 1, soltas: 0 });
  assertEquals(gravados.map(([id]) => id), ["m1", "m2", "m3"]);
  assertEquals(gravados[1][2], { ok: false, erro: "brevo 503", definitivo: false });
});

Deno.test("o resultado leva o envio_id (dono da trava)", async () => {
  const { d, gravados } = deps();
  await processar(d);
  assertEquals(gravados.map(([, envio]) => envio), ["e-m1", "e-m2", "e-m3"]);
});

Deno.test("um erro inesperado (montar ou enviar lancou) vira falha temporaria e o resto segue", async () => {
  const { d, gravados } = deps({
    preparar: () => Promise.resolve([msg("m1"), msg("m2")]),
    montar: (m) => (m.id === "m1" ? Promise.reject(new Error("quebrou")) : Promise.resolve(email(m))),
  });
  const r = await processar(d);
  assertEquals(r, { enviadas: 1, falhas: 1, soltas: 0 });
  assertEquals(gravados[0][2], { ok: false, erro: "erro interno: quebrou", definitivo: false });
});

Deno.test("falha ao gravar o resultado de uma nao impede as outras", async () => {
  const gravados: string[] = [];
  const { d } = deps({
    preparar: () => Promise.resolve([msg("m1"), msg("m2")]),
    resultado: (m) => {
      if (m.id === "m1") return Promise.reject(new Error("db fora"));
      gravados.push(m.id);
      return Promise.resolve();
    },
  });
  assertEquals(await processar(d), { enviadas: 1, falhas: 1, soltas: 0 });
  assertEquals(gravados, ["m2"]);
});

Deno.test("Revisao 1: passado o prazo do lote, o resto e solto sem enviar (outro minuto pega)", async () => {
  let agora = 0;
  const enviados: string[] = [];
  const { d, soltos } = deps({
    agoraMs: () => agora,
    enviar: (e) => {
      enviados.push(e.para);
      agora += 30_000; // Brevo lenta: 30 s por e-mail
      return Promise.resolve({ ok: true, id: "<x>" });
    },
  });
  const r = await processar(d);
  assertEquals(enviados, ["m1@neu112.test", "m2@neu112.test"]);
  assertEquals(soltos, ["m3"]);
  assertEquals(r, { enviadas: 2, falhas: 0, soltas: 1 });
});

Deno.test("Revisao 9: chave da Brevo errada (sistema) solta esta e as seguintes e para", async () => {
  const enviados: string[] = [];
  const { d, gravados, soltos } = deps({
    enviar: (e) => {
      enviados.push(e.para);
      return Promise.resolve({ ok: false, erro: "brevo 401", definitivo: false, sistema: true });
    },
  });
  const r = await processar(d);
  assertEquals(enviados, ["m1@neu112.test"]);
  assertEquals(gravados, []);
  assertEquals(soltos, ["m1", "m2", "m3"]);
  assertEquals(r, { enviadas: 0, falhas: 0, soltas: 3, erroSistema: "brevo 401" });
});

Deno.test("lote vazio: nada acontece", async () => {
  const { d } = deps({
    preparar: () => Promise.resolve([]),
    montar: () => Promise.reject(new Error("nao devia")),
    enviar: () => Promise.reject(new Error("nao devia")),
  });
  assertEquals(await processar(d), { enviadas: 0, falhas: 0, soltas: 0 });
});
