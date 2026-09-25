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
