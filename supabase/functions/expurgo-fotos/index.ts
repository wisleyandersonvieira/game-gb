// Expurgo das fotos de entrega vencidas (verify_jwt = false). Quem chama é o
// próprio banco (pg_net), com o cabeçalho x-expurgo-segredo. Sem ele ou com
// valor errado: 401 e nada acontece.
//
// SQL não apaga arquivo do Storage. A rotina do banco já marcou a entrega
// ("foto removida por tempo") e guardou o caminho na fila; aqui só se apaga o
// arquivo e se devolve o resultado. Nenhum caminho vai para log.
import { createClient } from "npm:@supabase/supabase-js@2";
import { segredoConfere } from "../_shared/seguranca.ts";

const BUCKET = "entregas";
const POR_RODADA = 100;

export type DependenciasExpurgo = {
  segredo: string | undefined;
  rodada: () => Promise<number>;
};

export function criarExpurgo(d: DependenciasExpurgo) {
  return async (req: Request): Promise<Response> => {
    const ok = await segredoConfere(req.headers.get("x-expurgo-segredo"), d.segredo);
    if (!ok) return new Response("nao autorizado", { status: 401 });
    const apagados = await d.rodada();
    return Response.json({ apagados });
  };
}

if (import.meta.main) {
  const url = Deno.env.get("SUPABASE_URL")!;
  const chave = Deno.env.get("STGAME_SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const banco = createClient(url, chave, { auth: { persistSession: false, autoRefreshToken: false } });

  const rodada = async () => {
    let apagados = 0;
    // Vai pegando lotes até a fila secar (ou até 50 lotes, por segurança).
    for (let volta = 0; volta < 50; volta++) {
      const { data, error } = await banco.rpc("expurgo_pegar", { p_limite: POR_RODADA });
      if (error) {
        console.error("expurgo: falha ao pegar a lista", error.message);
        return apagados;
      }
      const itens = (data ?? []) as { id: number; caminho: string }[];
      if (itens.length === 0) return apagados;

      const { error: erroStorage } = await banco.storage.from(BUCKET).remove(itens.map((i) => i.caminho));
      const ids = itens.map((i) => i.id);
      if (erroStorage) {
        // Não marca como removido: a rotina tenta de novo amanhã (até 5 vezes).
        console.error("expurgo: falha ao apagar no Storage", erroStorage.message);
        await banco.rpc("expurgo_resultado", { p_ids: ids, p_erro: erroStorage.message });
        return apagados;
      }
      const { error: erroResultado } = await banco.rpc("expurgo_resultado", { p_ids: ids, p_erro: null });
      if (erroResultado) {
        console.error("expurgo: falha ao registrar o resultado", erroResultado.message);
        return apagados;
      }
      apagados += itens.length;
    }
    return apagados;
  };

  Deno.serve(criarExpurgo({ segredo: Deno.env.get("STGAME_EXPURGO_SEGREDO"), rodada }));
}
