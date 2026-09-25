// Quantos pedidos de resgate estão esperando o gestor.
//
// Serve à bandeirinha vermelha do menu Prêmios: sem ela, o pedido que o
// colaborador faz pelo celular pode passar dias sem ninguém ver.
//
// DESEMPENHO: esta consulta é do MENU, que envolve todas as telas — não pode
// virar uma ida ao banco a cada troca de tela. Por isso ela usa a mesma chave
// em todo lugar e o prazo OPERACIONAL (30 s) de src/ui/prazos.ts: dentro
// desses 30 segundos, trocar de tela não pergunta nada ao banco.
//
// Conta os pendentes de TODAS as lojas que o gestor enxerga, e não só a do
// seletor do topo: a lista de resgates já mostra lojas diferentes.
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { OPERACIONAL } from "./prazos";

export function useResgatesPendentes() {
  const q = useQuery({
    queryKey: ["resgates-pendentes"],
    staleTime: OPERACIONAL,
    refetchOnWindowFocus: true,
    queryFn: async () => {
      // head + count: o banco devolve só o número, sem trazer linha nenhuma.
      const { count, error } = await supabase
        .from("resgates")
        .select("resgateid", { count: "exact", head: true })
        .eq("status", "Pendente");
      if (error) throw error;
      return count ?? 0;
    },
  });
  return q.data ?? 0;
}

// ---------------------------------------------------------------------------
// As marcações de quantidade de Solicitações.
//
// São três números na mesma tela: a bandeirinha vermelha do menu (todas as
// lojas que o gestor enxerga) e, nas abas, quantas estão Aberta e quantas
// estão Em andamento na loja do seletor.
//
// DESEMPENHO: os três saem de UMA resposta só, guardada aqui pela mesma chave.
// O menu acompanha todas as telas — se cada número tivesse a sua consulta,
// trocar de tela viraria quatro idas ao banco. A conta é feita dentro do
// banco (contagem_solicitacoes): volta um número por loja, nunca a linha da
// solicitação.
// ---------------------------------------------------------------------------

/** A chave única. Quem mudar uma solicitação invalida esta, e os dois números
 *  se refazem juntos — o do menu e o da aba. */
export const CHAVE_SOLICITACOES = ["solicitacoes-a-resolver"] as const;

export type ContagemSolicitacoes = {
  /** Uma entrada por loja que tem algo esperando. */
  lojas: { lojaid: number; abertas: number; andamento: number }[];
  /** A resolver somando todas as lojas: é o número da bandeirinha do menu. */
  total: number;
};

const NENHUMA: ContagemSolicitacoes = { lojas: [], total: 0 };

export function useContagemSolicitacoes(): ContagemSolicitacoes {
  const q = useQuery({
    queryKey: CHAVE_SOLICITACOES,
    staleTime: OPERACIONAL,
    refetchOnWindowFocus: true,
    queryFn: async (): Promise<ContagemSolicitacoes> => {
      const { data, error } = await supabase.rpc("contagem_solicitacoes");
      if (error) throw error;
      return montarContagem(data ?? []);
    },
  });
  return q.data ?? NENHUMA;
}

/** Junta as linhas do banco (uma por loja e situação) no formato da tela. */
export function montarContagem(
  linhas: { loja: number; situacao: string; quantos: number }[],
): ContagemSolicitacoes {
  const porLoja = new Map<number, { lojaid: number; abertas: number; andamento: number }>();
  let total = 0;
  for (const linha of linhas) {
    const atual = porLoja.get(linha.loja) ?? { lojaid: linha.loja, abertas: 0, andamento: 0 };
    if (linha.situacao === "Aberta") atual.abertas = linha.quantos;
    else if (linha.situacao === "Em andamento") atual.andamento = linha.quantos;
    else continue; // situação que não espera ninguém: não é para contar
    porLoja.set(linha.loja, atual);
    total += linha.quantos;
  }
  return { lojas: [...porLoja.values()], total };
}

/** Os números de uma loja. Loja sem nada esperando devolve zeros. */
export function daLoja(c: ContagemSolicitacoes, lojaid: number) {
  const l = c.lojas.find((x) => x.lojaid === lojaid);
  const abertas = l?.abertas ?? 0;
  const andamento = l?.andamento ?? 0;
  return { abertas, andamento, aResolver: abertas + andamento };
}
