// As bandeirinhas vermelhas do menu: Quadro, Prêmios e Solicitações.
//
// Sem elas, a entrega, o pedido de resgate ou a solicitação feitos pelo
// celular podem passar dias sem ninguém ver. Contam TODAS as lojas que o
// gestor enxerga, e não só a do seletor do topo.
import { useQuery } from "@tanstack/react-query";
import { useMemo } from "react";
import { supabase } from "@/integrations/supabase/client";
import { OPERACIONAL } from "./prazos";

// ---------------------------------------------------------------------------
// Os contadores do menu — UMA consulta só (29/09/2026).
//
// Quadro (entregas esperando aprovação), Prêmios (resgates esperando) e
// Solicitações saem da mesma resposta do banco (contagem_do_menu: só números,
// nunca linha), com UMA chave para o menu inteiro e o prazo OPERACIONAL: dentro
// de 30 segundos, trocar de tela não pergunta nada. Quem muda uma entrega, um
// resgate ou uma solicitação invalida esta chave, e os três se refazem juntos.
// ---------------------------------------------------------------------------

export const CHAVE_MENU = ["contadores-do-menu"] as const;

type ContadoresDoMenu = {
  entregas: number;
  resgates: number;
  solicitacoes: { loja: number; situacao: string; quantos: number }[];
};

const ZERADOS: ContadoresDoMenu = { entregas: 0, resgates: 0, solicitacoes: [] };

function useContadoresDoMenu(): ContadoresDoMenu {
  const q = useQuery({
    queryKey: CHAVE_MENU,
    staleTime: OPERACIONAL,
    refetchOnWindowFocus: true,
    queryFn: async (): Promise<ContadoresDoMenu> => {
      const { data, error } = await supabase.rpc("contagem_do_menu");
      if (error) throw error;
      return { ...ZERADOS, ...((data ?? {}) as Partial<ContadoresDoMenu>) };
    },
  });
  return q.data ?? ZERADOS;
}

/** Quantas entregas esperam aprovação, em todas as lojas que o gestor enxerga. */
export function useEntregasPendentes() {
  return useContadoresDoMenu().entregas;
}

export function useResgatesPendentes() {
  return useContadoresDoMenu().resgates;
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
export const CHAVE_SOLICITACOES = CHAVE_MENU;

export type ContagemSolicitacoes = {
  /** Uma entrada por loja que tem algo esperando. */
  lojas: { lojaid: number; abertas: number; andamento: number }[];
  /** A resolver somando todas as lojas: é o número da bandeirinha do menu. */
  total: number;
};

const NENHUMA: ContagemSolicitacoes = { lojas: [], total: 0 };

export function useContagemSolicitacoes(): ContagemSolicitacoes {
  const linhas = useContadoresDoMenu().solicitacoes;
  // Refeito só quando a resposta muda (o mesmo objeto enquanto o cache vale).
  return useMemo(() => (linhas.length ? montarContagem(linhas) : NENHUMA), [linhas]);
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
