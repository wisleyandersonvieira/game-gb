// Chamadas à API do Telegram. O token só existe nos segredos do Supabase.
export type Botao = { text: string; callback_data?: string; url?: string };
export type Teclado = Botao[][];

export type RespostaTelegram = {
  ok: boolean;
  result?: Record<string, unknown> & { message_id?: number; file_path?: string };
  description?: string;
  error_code?: number;
  parameters?: { retry_after?: number };
};

export class Telegram {
  constructor(private token: string) {}

  async chamar(metodo: string, corpo: Record<string, unknown>): Promise<RespostaTelegram> {
    try {
      const r = await fetch(`https://api.telegram.org/bot${this.token}/${metodo}`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(corpo),
        signal: AbortSignal.timeout(15000),
      });
      return (await r.json()) as RespostaTelegram;
    } catch {
      return { ok: false, description: "sem resposta do Telegram" };
    }
  }

  enviar(chatId: number, texto: string, extra: Record<string, unknown> = {}) {
    return this.chamar("sendMessage", {
      chat_id: chatId,
      text: texto,
      parse_mode: "HTML",
      disable_web_page_preview: true,
      ...extra,
    });
  }

  responderBotao(callbackId: string, texto?: string, alerta = false) {
    return this.chamar("answerCallbackQuery", { callback_query_id: callbackId, text: texto, show_alert: alerta });
  }

  /** Baixa um arquivo enviado ao bot (fotos: até 20 MB). */
  async baixar(fileId: string): Promise<Uint8Array> {
    const info = await this.chamar("getFile", { file_id: fileId });
    const caminho = info.result?.file_path;
    if (!info.ok || !caminho) throw new Error("Não consegui baixar a foto do Telegram.");
    const r = await fetch(`https://api.telegram.org/file/bot${this.token}/${caminho}`);
    if (!r.ok) throw new Error("Não consegui baixar a foto do Telegram.");
    return new Uint8Array(await r.arrayBuffer());
  }
}

export const teclado = (linhas: Teclado) => ({ reply_markup: { inline_keyboard: linhas } });

export function escaparHtml(t: unknown): string {
  return String(t ?? "").replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");
}
