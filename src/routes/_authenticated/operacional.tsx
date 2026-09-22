import { createFileRoute } from "@tanstack/react-router";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect } from "react";
import { supabase } from "@/integrations/supabase/client";
import { AvisoSemLoja, useLojaAtiva } from "@/lojas/loja-ativa";
import { hora, PainelDaLoja, type DadosPainel } from "@/painel/PainelDaLoja";
import { soltarFogosUmaVezPorDia } from "@/painel/fogos";

export const Route = createFileRoute("/_authenticated/operacional")({
  component: Operacional,
});

function Operacional() {
  const { lojas, lojaAtiva, carregando } = useLojaAtiva();

  if (carregando) {
    return (
      <div className="mx-auto max-w-7xl space-y-6">
        <p className="text-muted-foreground">Carregando...</p>
      </div>
    );
  }

  if (lojas.length === 0 || lojaAtiva === null) {
    return (
      <div className="mx-auto max-w-7xl space-y-6">
        <h1 className="font-display text-2xl font-semibold tracking-tight sm:text-3xl">Painel</h1>
        <AvisoSemLoja />
      </div>
    );
  }

  return <PainelLogado lojaid={lojaAtiva} />;
}

function PainelLogado({ lojaid }: { lojaid: number }) {
  const qc = useQueryClient();
  const chave = ["painel", lojaid];

  const painel = useQuery({
    queryKey: chave,
    // Conferência de segurança a cada 60 s, caso algum aviso em tempo real se perca.
    refetchInterval: 60_000,
    queryFn: async () => {
      const { data, error } = await supabase.rpc("painel_da_loja", { p_lojaid: lojaid });
      if (error) throw error;
      return data as unknown as DadosPainel;
    },
  });

  // Tempo real: qualquer entrega ou atribuição desta loja que mudar recarrega
  // o painel na hora. O Supabase só avisa do que a RLS deixa esta conta ver.
  useEffect(() => {
    const canal = supabase
      .channel(`painel-loja-${lojaid}`)
      .on("postgres_changes", { event: "*", schema: "public", table: "entregas", filter: `lojaid=eq.${lojaid}` }, () =>
        qc.invalidateQueries({ queryKey: chave }),
      )
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "tarefasatribuidas", filter: `lojaid=eq.${lojaid}` },
        () => qc.invalidateQueries({ queryKey: chave }),
      )
      .subscribe();
    return () => {
      supabase.removeChannel(canal);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [lojaid, qc]);

  const dados = painel.data;

  // Fogos ao completar 100% das tarefas do dia.
  useEffect(() => {
    if (!dados) return;
    const { total, aprovadas } = dados.progresso;
    if (total > 0 && aprovadas >= total) soltarFogosUmaVezPorDia(`loja-${lojaid}`, dados.hoje);
    // E ao bater a meta do dia (uma vez por dia, separado dos fogos das tarefas).
    if (dados.meta?.dia?.bateu) soltarFogosUmaVezPorDia(`loja-${lojaid}-meta`, dados.hoje);
  }, [dados, lojaid]);

  return (
    <div className="mx-auto max-w-7xl space-y-6">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <h1 className="font-display text-2xl font-semibold tracking-tight sm:text-3xl">Painel {dados ? `· ${dados.loja}` : ""}</h1>
        <p className={`text-sm ${painel.isError ? "text-destructive" : "text-muted-foreground"}`}>
          {painel.isError
            ? "Erro ao atualizar. Tentando de novo..."
            : dados
              ? `Atualizado às ${hora(dados.atualizadoem)} · ao vivo`
              : "Carregando..."}
        </p>
      </div>
      {dados && <PainelDaLoja dados={dados} />}
    </div>
  );
}
