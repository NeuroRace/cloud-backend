// "Parar de receber" e "Nao vou poder". So POST: antivirus de e-mail abre links (GET) sozinhos,
// e um GET aqui faria a pessoa perder o premio sem clicar. O link do e-mail abre a pagina
// /mensagens do site, que confirma com um clique e chama esta funcao. O cabecalho
// List-Unsubscribe (um clique, RFC 8058) faz POST aqui direto, com o token na URL.
import { verificar } from "../_shared/links.ts";

export type DepsAcoes = {
  segredo: string;
  siteUrl: string;
  agoraSeg(): number;
  bloquear(mensagem: string): Promise<boolean>;
  recusar(mensagem: string): Promise<string>;
};

export function criarHandler(d: DepsAcoes): (req: Request) => Promise<Response> {
  const cors = {
    // A origem do navegador nunca tem barra no fim: SITE_URL com barra nao casaria.
    "access-control-allow-origin": d.siteUrl.replace(/\/+$/, ""),
    "access-control-allow-methods": "POST, OPTIONS",
    "access-control-allow-headers": "content-type",
    "vary": "origin",
  };
  const json = (status: number, body: unknown) =>
    new Response(JSON.stringify(body), { status, headers: { ...cors, "content-type": "application/json" } });

  async function lerToken(req: Request): Promise<string> {
    const daUrl = new URL(req.url).searchParams.get("t");
    if (daUrl) return daUrl;
    try {
      const corpo = await req.json();
      return typeof corpo?.t === "string" ? corpo.t : "";
    } catch {
      return "";
    }
  }

  return async (req) => {
    if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
    if (req.method !== "POST") return json(405, { erro: "use_post" });

    const p = await verificar(d.segredo, await lerToken(req), d.agoraSeg());
    if (!p) {
      console.log(JSON.stringify({ level: "warn", event: "message_actions_assinatura" }));
      return json(403, { erro: "assinatura" });
    }
    try {
      if (p.a === "sair") {
        if (!(await d.bloquear(p.m))) return json(404, { erro: "nao_encontrada" });
        console.log(JSON.stringify({ level: "info", event: "message_actions_sair", mensagem: p.m }));
        return json(200, { ok: true, acao: "sair" });
      }
      const resultado = await d.recusar(p.m);
      console.log(JSON.stringify({ level: "info", event: "message_actions_recusar", mensagem: p.m, resultado }));
      return json(200, { ok: true, acao: "recusar", resultado });
    } catch (err) {
      console.log(JSON.stringify({
        level: "error", event: "message_actions_erro", erro: err instanceof Error ? err.message : "desconhecido",
      }));
      return json(500, { erro: "falha_interna" });
    }
  };
}
