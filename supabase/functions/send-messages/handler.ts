import { tokenMatches } from "../_shared/token.ts";
import type { Resumo } from "./processar.ts";

export type DepsHandler = {
  cronToken: string;
  // false sem BREVO_API_KEY, MENSAGENS_REMETENTE ou MENSAGENS_LINK_SECRET: nada e preparado (nada trava).
  pronto: boolean;
  rodar(): Promise<Resumo>;
};

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
}

export function criarHandler(d: DepsHandler): (req: Request) => Promise<Response> {
  return async (req) => {
    if (req.method !== "POST") return json(405, { erro: "use_post" });
    if (!(await tokenMatches(req.headers.get("x-cron-token"), d.cronToken))) {
      console.log(JSON.stringify({ level: "warn", event: "send_messages_unauthorized" }));
      return json(401, { erro: "nao_autorizado" });
    }
    if (!d.pronto) {
      console.log(JSON.stringify({ level: "warn", event: "send_messages_nao_configurada" }));
      return json(503, { erro: "nao_configurada" });
    }
    try {
      const resumo = await d.rodar();
      // Erro de sistema (chave da Brevo errada): nada sai ate alguem corrigir o secret.
      const level = resumo.erroSistema ? "error" : "info";
      console.log(JSON.stringify({ level, event: "send_messages_ok", ...resumo }));
      return json(200, resumo);
    } catch (err) {
      console.log(JSON.stringify({
        level: "error", event: "send_messages_erro", erro: err instanceof Error ? err.message : "desconhecido",
      }));
      return json(500, { erro: "falha_interna" });
    }
  };
}
