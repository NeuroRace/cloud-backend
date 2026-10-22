// Monta o e-mail de uma mensagem da caixa de saida: o texto vem pronto de quem enfileirou;
// aqui so entra o rodape com os links assinados (sem e-mail nem telefone na URL).
import { assinar, EXPIRA_RECUSAR_S, EXPIRA_SAIR_S } from "../_shared/links.ts";
import type { EmailMontado } from "./brevo.ts";

export type MensagemFila = {
  id: string;
  envio_id: string; // dono da trava, vem do mensagens_preparar
  tipo: string;
  destino: string;
  assunto: string;
  corpo_texto: string;
  corpo_html: string | null;
  premio_id: string | null;
};
export type ConfigMontar = { segredo: string; siteUrl: string; funcoesUrl: string; agoraSeg: number };

// So nesses avisos o premio ainda e da pessoa e ela pode abrir mao.
const TIPOS_COM_RECUSAR = new Set(["premio_venceu", "premio_lembrete"]);

function escapar(s: string): string {
  return s.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;").replaceAll("'", "&#39;");
}

export async function montar(m: MensagemFila, cfg: ConfigMontar): Promise<EmailMontado> {
  const sair = await assinar(cfg.segredo, { a: "sair", m: m.id, exp: cfg.agoraSeg + EXPIRA_SAIR_S });
  const site = cfg.siteUrl.replace(/\/+$/, "");
  const sairUrl = `${site}/mensagens?t=${sair}`;
  const recusarUrl = TIPOS_COM_RECUSAR.has(m.tipo) && m.premio_id
    ? `${site}/mensagens?t=${await assinar(cfg.segredo, { a: "recusar", m: m.id, exp: cfg.agoraSeg + EXPIRA_RECUSAR_S })}`
    : null;

  const rodapeTexto = [
    "",
    "--",
    ...(recusarUrl ? [`Não vai conseguir vir? ${recusarUrl}`] : []),
    `Para não receber mais e-mails do NeuroRace: ${sairUrl}`,
  ].join("\n");
  const rodapeHtml = [
    '<hr style="border:none;border-top:1px solid #ddd;margin:24px 0 12px">',
    ...(recusarUrl ? [`<p>Não vai conseguir vir? <a href="${escapar(recusarUrl)}">Não vou poder buscar o prêmio</a></p>`] : []),
    `<p style="font-size:12px;color:#666">Para não receber mais e-mails do NeuroRace: ` +
    `<a href="${escapar(sairUrl)}">parar de receber</a></p>`,
  ].join("");

  return {
    para: m.destino,
    assunto: m.assunto,
    texto: m.corpo_texto + "\n" + rodapeTexto,
    html: (m.corpo_html ?? `<p>${escapar(m.corpo_texto).replaceAll("\n", "<br>")}</p>`) + rodapeHtml,
    cancelarInscricaoUrl: `${cfg.funcoesUrl}/message-actions?t=${sair}`,
  };
}
