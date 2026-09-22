// Envio da fila de avisos do Telegram (verify_jwt = false). Quem chama é o
// próprio banco (pg_net/pg_cron), com o cabeçalho x-fila-segredo. Sem ele ou
// com valor errado: 401 e nada acontece. O banco escolhe o que sai em cada
// rodada respeitando os limites do Telegram; aqui só se envia e se devolve o
// resultado. Nada de texto de mensagem nos logs.
import { createClient } from "npm:@supabase/supabase-js@2";
import { segredoConfere } from "../_shared/seguranca.ts";
import { type RespostaTelegram, Telegram } from "../_shared/telegram.ts";

// deno-lint-ignore no-explicit-any
type Item = Record<string, any>;

export type DependenciasFila = {
  segredo: string | undefined;
  rodada: () => Promise<number>;
};

export function criarFila(d: DependenciasFila) {
  return async (req: Request): Promise<Response> => {
    const ok = await segredoConfere(req.headers.get("x-fila-segredo"), d.segredo);
    if (!ok) return new Response("nao autorizado", { status: 401 });
    const enviados = await d.rodada();
    return Response.json({ enviados });
  };
}

const espera = (ms: number) => new Promise((r) => setTimeout(r, ms));

async function enviarItem(tg: Telegram, fotoAssinada: (b: string, c: string) => Promise<string | null>, i: Item): Promise<RespostaTelegram> {
  const teclado = i.botoes ? { reply_markup: { inline_keyboard: i.botoes } } : {};
  switch (i.metodo) {
    case "sendPhoto": {
      const foto = i.foto_tg ?? (i.foto_storage ? await fotoAssinada(i.foto_storage.bucket, i.foto_storage.caminho) : null);
      if (!foto) return tg.enviar(i.chat_id, i.texto, teclado);
      return tg.chamar("sendPhoto", { chat_id: i.chat_id, photo: foto, caption: i.texto, parse_mode: "HTML", ...teclado });
    }
    case "editMessageCaption":
    case "editMessageText":
      if (!i.message_id) return { ok: true };
      return tg.chamar(i.metodo, {
        chat_id: i.chat_id, message_id: i.message_id, [i.metodo === "editMessageCaption" ? "caption" : "text"]: i.texto,
        parse_mode: "HTML", reply_markup: { inline_keyboard: [] },
      });
    default:
      return tg.enviar(i.chat_id, i.texto, teclado);
  }
}

if (import.meta.main) {
  const url = Deno.env.get("SUPABASE_URL")!;
  const chave = Deno.env.get("STGAME_SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const banco = createClient(url, chave, { auth: { persistSession: false, autoRefreshToken: false } });
  const tg = new Telegram(Deno.env.get("TELEGRAM_BOT_TOKEN") ?? "");
  const fotoAssinada = async (bucket: string, caminho: string) => {
    const { data } = await banco.storage.from(bucket).createSignedUrl(caminho, 300);
    return data?.signedUrl ?? null;
  };

  const rodada = async () => {
    const inicio = Date.now();
    let total = 0;
    while (Date.now() - inicio < 25000) {
      const { data, error } = await banco.rpc("bot_fila_pegar", { p_limite: 25 });
      if (error) {
        console.error("[fila] falha ao pegar a fila");
        break;
      }
      const itens = (data ?? []) as Item[];
      if (!itens.length) break;
      for (const i of itens) {
        const r = await enviarItem(tg, fotoAssinada, i);
        const naoMudou = !r.ok && /message is not modified/i.test(r.description ?? "");
        const certo = r.ok || naoMudou;
        await banco.rpc("bot_fila_resultado", {
          p_filaid: i.filaid,
          p_ok: certo,
          p_msgid: certo ? (r.result?.message_id ?? null) : null,
          p_erro: certo ? null : `${r.error_code ?? ""} ${r.description ?? "erro"}`.trim(),
          p_esperar: r.parameters?.retry_after ?? 0,
        });
        if (certo) total++;
        await espera(40); // ~25 por segundo, abaixo do limite de 30
      }
    }
    return total;
  };

  Deno.serve(criarFila({ segredo: Deno.env.get("TELEGRAM_FILA_SEGREDO"), rodada }));
}
