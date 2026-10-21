// send-messages: chamada pelo pg_cron (pg_net) a cada minuto. Pede um lote ao banco
// (mensagens_preparar), manda pela Brevo e grava o resultado (mensagem_resultado).
import { createClient } from "jsr:@supabase/supabase-js@2";
import { enviarBrevo } from "./brevo.ts";
import { criarHandler } from "./handler.ts";
import { type MensagemFila, montar } from "./montar.ts";
import { processar } from "./processar.ts";

const env = (k: string) => Deno.env.get(k) ?? "";
const BREVO_API_KEY = env("BREVO_API_KEY");
const REMETENTE = env("MENSAGENS_REMETENTE");
const LINK_SECRET = env("MENSAGENS_LINK_SECRET");
const SITE_URL = env("SITE_URL") || "https://neurorace-v2.vercel.app";
const SUPABASE_URL = env("SUPABASE_URL");
const LOTE = 20;

const supabase = createClient(SUPABASE_URL, env("SUPABASE_SERVICE_ROLE_KEY"), { auth: { persistSession: false } });

async function rpc<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.rpc(fn, args);
  if (error) throw new Error(`${fn}: ${error.message}`);
  return data as T;
}

Deno.serve(criarHandler({
  cronToken: env("MENSAGENS_CRON_TOKEN"),
  pronto: BREVO_API_KEY !== "" && REMETENTE !== "" && LINK_SECRET !== "",
  rodar: () =>
    processar({
      preparar: () =>
        rpc<MensagemFila[]>("mensagens_preparar", {
          p_canal: "email", p_agora: new Date().toISOString(), p_limite: LOTE,
        }),
      montar: (m) =>
        montar(m, {
          segredo: LINK_SECRET, siteUrl: SITE_URL, funcoesUrl: `${SUPABASE_URL}/functions/v1`,
          agoraSeg: Math.floor(Date.now() / 1000),
        }),
      enviar: (e) => enviarBrevo(fetch, BREVO_API_KEY, REMETENTE, e),
      resultado: (id, r) =>
        rpc("mensagem_resultado", {
          p_id: id, p_ok: r.ok, p_provedor_id: r.ok ? r.id : null, p_erro: r.ok ? null : r.erro,
          p_definitivo: r.ok ? false : r.definitivo, p_agora: new Date().toISOString(),
        }),
    }),
}));
