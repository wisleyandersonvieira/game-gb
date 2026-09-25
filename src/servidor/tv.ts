// Etapa 1.12 — o pareamento da TV por código curto.
//
// A TV abre /tv, mostra um código de 6 caracteres e fica perguntando de tempos
// em tempos "já me parearam?". Quem responde é este servidor: as funções do
// banco recebem o segredo do aparelho e só o servidor as chama.
//
// O segredo do aparelho NUNCA sai daqui em claro para o banco: vai embaralhado
// com a chave do servidor, do mesmo jeito que o PIN do tablet.
import { createServerFn } from "@tanstack/react-start";
import { embaralhar, origemDaChamada, abrirTentativa, fecharTentativa } from "@/servidor/segredos";

/** Quanto tempo o código vale na tela. */
export const MINUTOS_DO_CODIGO = 10;

function texto(v: unknown, tamanho: number): string {
  return typeof v === "string" ? v.slice(0, tamanho) : "";
}

/**
 * A TV pede um código novo.
 *
 * Tem trava: um aparelho não pode ficar pedindo código sem parar. A trava é
 * por ORIGEM, e só atrasa — nunca bloqueia, senão bastaria um engraçadinho
 * para deixar a loja sem TV.
 */
export const pedirCodigoDaTv = createServerFn({ method: "POST" })
  .validator((d: { segredo: string }) => ({ segredo: texto(d?.segredo, 200) }))
  .handler(async ({ data }) => {
    if (data.segredo.length < 20) throw new Error("Aparelho não identificado.");

    const origem = origemDaChamada();
    const tentativa = await abrirTentativa(null, "tvcodigo", data.segredo, origem);

    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { data: codigo, error } = await supabaseAdmin.rpc("tv_novo_codigo", {
      p_segredohash: await embaralhar(data.segredo),
      p_minutos: MINUTOS_DO_CODIGO,
    });
    await fecharTentativa(tentativa, !error);
    if (error) throw new Error("Não foi possível gerar o código agora. Tente de novo.");

    return { codigo: codigo as string, minutos: MINUTOS_DO_CODIGO };
  });

export type RespostaDaTv =
  | { situacao: "esperando" | "vencido" | "sem_codigo" | "ja_entregue" }
  | { situacao: "pareada"; token: string };

/** A TV pergunta se já foi pareada. Sem trava: é ela mesma perguntando. */
export const verSeParearam = createServerFn({ method: "POST" })
  .validator((d: { segredo: string }) => ({ segredo: texto(d?.segredo, 200) }))
  .handler(async ({ data }) => {
    if (data.segredo.length < 20) return { situacao: "sem_codigo" } as RespostaDaTv;

    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { data: r, error } = await supabaseAdmin.rpc("tv_buscar_link", {
      p_segredohash: await embaralhar(data.segredo),
    });
    if (error) throw new Error("Sem conexão com o sistema.");
    return r as unknown as RespostaDaTv;
  });
