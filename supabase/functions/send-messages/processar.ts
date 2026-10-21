// Um lote da caixa de saida: cada mensagem num try/catch proprio, para uma falha (Brevo fora,
// erro inesperado, banco ao gravar) nao travar as outras. As novas tentativas ficam no banco.
import type { EmailMontado, ResultadoEnvio } from "./brevo.ts";
import type { MensagemFila } from "./montar.ts";

export type DepsProcessar = {
  preparar(): Promise<MensagemFila[]>;
  montar(m: MensagemFila): Promise<EmailMontado>;
  enviar(e: EmailMontado): Promise<ResultadoEnvio>;
  resultado(id: string, r: ResultadoEnvio): Promise<void>;
};
export type Resumo = { enviadas: number; falhas: number };

export async function processar(d: DepsProcessar): Promise<Resumo> {
  const resumo: Resumo = { enviadas: 0, falhas: 0 };
  for (const m of await d.preparar()) {
    let r: ResultadoEnvio;
    try {
      r = await d.enviar(await d.montar(m));
    } catch (err) {
      r = { ok: false, erro: `erro interno: ${err instanceof Error ? err.message : "desconhecido"}`, definitivo: false };
    }
    try {
      await d.resultado(m.id, r);
      if (r.ok) resumo.enviadas++;
      else resumo.falhas++;
    } catch {
      // Sem resultado gravado, a trava de 2 min vence e a mensagem volta no proximo lote.
      resumo.falhas++;
    }
  }
  return resumo;
}
