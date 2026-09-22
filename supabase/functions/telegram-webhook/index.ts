// Webhook do @STGameAppBot (verify_jwt = false). A proteção é o secret_token
// que o Telegram manda no cabeçalho X-Telegram-Bot-Api-Secret-Token: sem ele
// ou com valor errado, responde 401 e não faz NADA (nem abre o banco).
// Com ele certo, marca o update (cada update_id é tratado uma vez), responde
// 200 na hora e faz o trabalho em segundo plano.
import { createClient } from "npm:@supabase/supabase-js@2";
import { segredoConfere } from "../_shared/seguranca.ts";
import { Telegram } from "../_shared/telegram.ts";
import { type Banco, processar } from "./bot.ts";

// deno-lint-ignore no-explicit-any
type Update = { update_id?: number } & Record<string, any>;

export type Dependencias = {
  segredo: string | undefined;
  /** true se este update_id ainda não foi visto. */
  registrar: (updateId: number) => Promise<boolean>;
  processar: (u: Update) => Promise<void>;
  emSegundoPlano: (p: Promise<unknown>) => void;
};

export function criarWebhook(d: Dependencias) {
  return async (req: Request): Promise<Response> => {
    const ok = await segredoConfere(req.headers.get("x-telegram-bot-api-secret-token"), d.segredo);
    if (!ok) return new Response("nao autorizado", { status: 401 });
    if (req.method !== "POST") return new Response("metodo", { status: 405 });

    let u: Update;
    try {
      u = await req.json();
    } catch {
      return new Response("ok");
    }
    if (typeof u?.update_id !== "number") return new Response("ok");

    let novo = false;
    try {
      novo = await d.registrar(u.update_id);
    } catch {
      console.error("[webhook] falha ao registrar update");
      return new Response("tente de novo", { status: 500 }); // o Telegram reenvia
    }
    if (novo) {
      d.emSegundoPlano(d.processar(u).catch(() => console.error("[webhook] falha ao tratar update")));
    }
    return new Response("ok");
  };
}

if (import.meta.main) {
  const url = Deno.env.get("SUPABASE_URL")!;
  const chave = Deno.env.get("STGAME_SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const banco = createClient(url, chave, { auth: { persistSession: false, autoRefreshToken: false } });
  const tg = new Telegram(Deno.env.get("TELEGRAM_BOT_TOKEN") ?? "");
  const contexto = { banco: banco as unknown as Banco, tg, usuarioBot: Deno.env.get("TELEGRAM_BOT_USERNAME") ?? "STGameAppBot" };

  Deno.serve(criarWebhook({
    segredo: Deno.env.get("TELEGRAM_WEBHOOK_SECRET"),
    registrar: async (id) => {
      const { data, error } = await banco.rpc("bot_registrar_update", { p_updateid: id });
      if (error) throw new Error("registrar");
      return data === true;
    },
    processar: (u) => processar(contexto, u),
    // deno-lint-ignore no-explicit-any
    emSegundoPlano: (p) => (globalThis as any).EdgeRuntime?.waitUntil ? (globalThis as any).EdgeRuntime.waitUntil(p) : void p,
  }));
}
