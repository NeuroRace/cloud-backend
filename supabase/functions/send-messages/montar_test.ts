import { assert, assertEquals, assertFalse, assertStringIncludes } from "jsr:@std/assert@1";
import { verificar } from "../_shared/links.ts";
import { montar, type MensagemFila } from "./montar.ts";

const CFG = {
  segredo: "segredo-de-teste",
  siteUrl: "https://neurorace-v2.vercel.app",
  funcoesUrl: "https://x.supabase.co/functions/v1",
  agoraSeg: 1_800_000_000,
};
const BASE: MensagemFila = {
  id: "11200000-0000-0000-0000-000000000001",
  envio_id: "11200000-0000-0000-0000-0000000000e1",
  tipo: "corrida_registrada",
  destino: "ana@neu112.test",
  assunto: "Sua corrida no NeuroRace foi registrada",
  corpo_texto: "Sua corrida foi registrada: 48,3 s.",
  corpo_html: null,
  premio_id: null,
};

function tokens(texto: string): string[] {
  return [...texto.matchAll(/[?&]t=([A-Za-z0-9_\-.]+)/g)].map((m) => m[1]);
}

Deno.test("aviso de corrida: so o link de parar de receber, que verifica como 'sair'", async () => {
  const e = await montar(BASE, CFG);
  assertEquals(e.para, "ana@neu112.test");
  assertEquals(e.assunto, BASE.assunto);
  assertStringIncludes(e.texto, "Sua corrida foi registrada: 48,3 s.");
  assertStringIncludes(e.texto, "Para não receber mais e-mails do NeuroRace: https://neurorace-v2.vercel.app/mensagens?t=");
  assertFalse(e.texto.includes("Não vai conseguir vir?"));
  const [t] = tokens(e.texto);
  const p = await verificar(CFG.segredo, t, CFG.agoraSeg);
  assertEquals(p?.a, "sair");
  assertEquals(p?.m, BASE.id);
  assertEquals(p?.exp, CFG.agoraSeg + 90 * 86400);
});

Deno.test("voce venceu com premio: tem tambem o link 'Nao vou poder' (recusar, 2 dias)", async () => {
  const e = await montar({ ...BASE, tipo: "premio_venceu", premio_id: "11200000-0000-0000-0000-0000000000aa" }, CFG);
  assertStringIncludes(e.texto, "Não vai conseguir vir? https://neurorace-v2.vercel.app/mensagens?t=");
  const acoes = await Promise.all(tokens(e.texto).map((t) => verificar(CFG.segredo, t, CFG.agoraSeg)));
  assertEquals(acoes.map((p) => p?.a).sort(), ["recusar", "sair"]);
  assertEquals(acoes.find((p) => p?.a === "recusar")?.exp, CFG.agoraSeg + 2 * 86400);
  assertStringIncludes(e.html, "Não vai conseguir vir?");
});

Deno.test("premio_prazo_passou: sem 'Nao vou poder' (o premio ja passou)", async () => {
  const e = await montar({ ...BASE, tipo: "premio_prazo_passou", premio_id: "11200000-0000-0000-0000-0000000000aa" }, CFG);
  assertFalse(e.texto.includes("Não vai conseguir vir?"));
});

Deno.test("cabecalho List-Unsubscribe aponta para a funcao (um clique, RFC 8058)", async () => {
  const e = await montar(BASE, CFG);
  assert(e.cancelarInscricaoUrl.startsWith("https://x.supabase.co/functions/v1/message-actions?t="));
  const p = await verificar(CFG.segredo, tokens(e.cancelarInscricaoUrl)[0], CFG.agoraSeg);
  assertEquals(p?.a, "sair");
});

Deno.test("sem corpo_html: gera do texto, escapando HTML", async () => {
  const e = await montar({ ...BASE, corpo_texto: 'Oi <script>alert("x")</script>\nlinha 2' }, CFG);
  assertStringIncludes(e.html, "Oi &lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;<br>linha 2");
  assertFalse(e.html.includes("<script>"));
});

Deno.test("com corpo_html: usa o html de quem enfileirou e acrescenta o rodape", async () => {
  const e = await montar({ ...BASE, corpo_html: "<p><b>Corrida</b> registrada</p>" }, CFG);
  assert(e.html.startsWith("<p><b>Corrida</b> registrada</p>"));
  assertStringIncludes(e.html, "Para não receber mais e-mails do NeuroRace");
});

Deno.test("Revisao 8: SITE_URL com barra no fim nao gera //mensagens", async () => {
  const e = await montar(BASE, { ...CFG, siteUrl: "https://neurorace-v2.vercel.app/" });
  assertStringIncludes(e.texto, "https://neurorace-v2.vercel.app/mensagens?t=");
  assertFalse(e.texto.includes("app//mensagens"));
});

Deno.test("nenhuma URL leva o e-mail do destino", async () => {
  const e = await montar({ ...BASE, tipo: "premio_venceu", premio_id: "11200000-0000-0000-0000-0000000000aa" }, CFG);
  for (const url of [...e.texto.matchAll(/https:\/\/\S+/g)].map((m) => m[0]).concat(e.cancelarInscricaoUrl)) {
    assertFalse(url.includes("ana"), url);
    assertFalse(url.includes("%40"), url);
  }
});
