// Um lote da caixa de saida: cada mensagem num try/catch proprio, para uma falha (Brevo fora,
// erro inesperado, banco ao gravar) nao travar as outras. As novas tentativas ficam no banco.
// Passado o prazo do lote, o resto e solto (volta no proximo minuto sem gastar tentativa): o
// lote nunca dura mais que a trava. Erro de sistema (chave da Brevo errada) solta tudo e para.
import type { EmailMontado, ResultadoEnvio } from "./brevo.ts";
import type { MensagemFila } from "./montar.ts";

export type DepsProcessar = {
  preparar(): Promise<MensagemFila[]>;
  montar(m: MensagemFila): Promise<EmailMontado>;
  enviar(e: EmailMontado): Promise<ResultadoEnvio>;
  resultado(m: MensagemFila, r: ResultadoEnvio): Promise<void>;
  soltar(m: MensagemFila): Promise<void>;
  agoraMs(): number;
  prazoMs: number;
};
export type Resumo = { enviadas: number; falhas: number; soltas: number; erroSistema?: string };

export async function processar(d: DepsProcessar): Promise<Resumo> {
  const resumo: Resumo = { enviadas: 0, falhas: 0, soltas: 0 };
  const inicio = d.agoraMs();
  const lote = await d.preparar();

  async function soltarDesde(i: number) {
    for (const m of lote.slice(i)) {
      // Se soltar falhar, a trava vence sozinha (5 min) e a mensagem volta.
      await d.soltar(m).catch(() => {});
      resumo.soltas++;
    }
  }

  for (let i = 0; i < lote.length; i++) {
    const m = lote[i];
    if (d.agoraMs() - inicio >= d.prazoMs) {
      await soltarDesde(i);
      break;
    }
    let r: ResultadoEnvio;
    try {
      r = await d.enviar(await d.montar(m));
    } catch (err) {
      r = { ok: false, erro: `erro interno: ${err instanceof Error ? err.message : "desconhecido"}`, definitivo: false };
    }
    if (!r.ok && r.sistema) {
      resumo.erroSistema = r.erro;
      await soltarDesde(i);
      break;
    }
    try {
      await d.resultado(m, r);
      if (r.ok) resumo.enviadas++;
      else resumo.falhas++;
    } catch {
      // Sem resultado gravado, a trava vence e a mensagem volta num proximo lote.
      resumo.falhas++;
    }
  }
  return resumo;
}
