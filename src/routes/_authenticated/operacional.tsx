import { createFileRoute } from "@tanstack/react-router";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect } from "react";
import { supabase } from "@/integrations/supabase/client";
import { AvisoSemLoja, useLojaAtiva } from "@/lojas/loja-ativa";
import { hora, PainelDaLoja, type DadosPainel } from "@/painel/PainelDaLoja";
import { soltarFogosUmaVezPorDia } from "@/painel/fogos";
import { Pagina } from "@/ui/Pagina";

export const Route = createFileRoute("/_authenticated/operacional")({
  component: Operacional,
});

function Operacional() {
  const { lojas, lojaAtiva, carregando } = useLojaAtiva();

  if (carregando) {
    return (
      <Pagina>
        <p className="text-muted-foreground">Carregando...</p>
      </Pagina>
    );
  }

  if (lojas.length === 0 || lojaAtiva === null) {
    return (
      <Pagina titulo="Painel">
        <AvisoSemLoja />
      </Pagina>
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
    <Pagina
      titulo={<>Painel {dados ? `· ${dados.loja}` : ""}</>}
      acoes={
        <p className={`text-sm ${painel.isError ? "text-destructive" : "text-muted-foreground"}`}>
          {painel.isError
            ? "Erro ao atualizar. Tentando de novo..."
            : dados
              ? `Atualizado às ${hora(dados.atualizadoem)} · ao vivo`
              : "Carregando..."}
        </p>
      }
    >
      {dados && <PainelDaLoja dados={dados} />}
    </Pagina>
  );
}
