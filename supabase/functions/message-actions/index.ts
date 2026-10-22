// message-actions: "Parar de receber" e "Nao vou poder" dos e-mails da premiacao (NEU-112).
import { createClient } from "jsr:@supabase/supabase-js@2";
import { criarHandler } from "./handler.ts";

const env = (k: string) => Deno.env.get(k) ?? "";
const supabase = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
  auth: { persistSession: false },
});

async function rpc<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.rpc(fn, args);
  if (error) throw new Error(`${fn}: ${error.message}`);
  return data as T;
}

Deno.serve(criarHandler({
  segredo: env("MENSAGENS_LINK_SECRET"),
  siteUrl: env("SITE_URL") || "https://neurorace-v2.vercel.app",
  agoraSeg: () => Math.floor(Date.now() / 1000),
  bloquear: (m) =>
    rpc<boolean>("mensagem_bloquear", { p_mensagem: m, p_origem: "link do e-mail", p_agora: new Date().toISOString() }),
  recusar: (m) => rpc<string>("mensagem_recusar_premio", { p_mensagem: m, p_agora: new Date().toISOString() }),
}));
