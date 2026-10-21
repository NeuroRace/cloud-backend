import { assertEquals } from "jsr:@std/assert@1";
import type { EmailMontado, ResultadoEnvio } from "./brevo.ts";
import type { MensagemFila } from "./montar.ts";
import { processar } from "./processar.ts";

function msg(id: string): MensagemFila {
  return {
    id, tipo: "corrida_registrada", destino: `${id}@neu112.test`, assunto: "A", corpo_texto: "T",
    corpo_html: null, premio_id: null,
  };
}
function email(m: MensagemFila): EmailMontado {
  return { para: m.destino, assunto: m.assunto, html: "h", texto: "t", cancelarInscricaoUrl: "u" };
}

Deno.test("Pronto 6: a Brevo fora numa mensagem nao trava as outras", async () => {
  const gravados: [string, ResultadoEnvio][] = [];
  const r = await processar({
    preparar: () => Promise.resolve([msg("m1"), msg("m2"), msg("m3")]),
    montar: (m) => Promise.resolve(email(m)),
    enviar: (e) =>
      Promise.resolve(
        e.para.startsWith("m2") ? { ok: false, erro: "brevo 503", definitivo: false } : { ok: true, id: `<${e.para}>` },
      ),
    resultado: (id, res) => {
      gravados.push([id, res]);
      return Promise.resolve();
    },
  });
  assertEquals(r, { enviadas: 2, falhas: 1 });
  assertEquals(gravados.map(([id]) => id), ["m1", "m2", "m3"]);
  assertEquals(gravados[1][1], { ok: false, erro: "brevo 503", definitivo: false });
});

Deno.test("um erro inesperado (montar ou enviar lancou) vira falha temporaria e o resto segue", async () => {
  const gravados: [string, ResultadoEnvio][] = [];
  const r = await processar({
    preparar: () => Promise.resolve([msg("m1"), msg("m2")]),
    montar: (m) => (m.id === "m1" ? Promise.reject(new Error("quebrou")) : Promise.resolve(email(m))),
    enviar: () => Promise.resolve({ ok: true, id: "<x>" }),
    resultado: (id, res) => {
      gravados.push([id, res]);
      return Promise.resolve();
    },
  });
  assertEquals(r, { enviadas: 1, falhas: 1 });
  assertEquals(gravados[0], ["m1", { ok: false, erro: "erro interno: quebrou", definitivo: false }]);
});

Deno.test("falha ao gravar o resultado de uma nao impede as outras", async () => {
  const gravados: string[] = [];
  const r = await processar({
    preparar: () => Promise.resolve([msg("m1"), msg("m2")]),
    montar: (m) => Promise.resolve(email(m)),
    enviar: () => Promise.resolve({ ok: true, id: "<x>" }),
    resultado: (id) => {
      if (id === "m1") return Promise.reject(new Error("db fora"));
      gravados.push(id);
      return Promise.resolve();
    },
  });
  assertEquals(gravados, ["m2"]);
  assertEquals(r, { enviadas: 1, falhas: 1 });
});

Deno.test("lote vazio: nada acontece", async () => {
  const r = await processar({
    preparar: () => Promise.resolve([]),
    montar: () => Promise.reject(new Error("nao devia")),
    enviar: () => Promise.reject(new Error("nao devia")),
    resultado: () => Promise.reject(new Error("nao devia")),
  });
  assertEquals(r, { enviadas: 0, falhas: 0 });
});
