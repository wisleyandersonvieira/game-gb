import { createFileRoute } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Nav } from "@/components/Nav";
import { AvisoSemLoja, useLojaAtiva } from "@/lojas/loja-ativa";

export const Route = createFileRoute("/_authenticated/ranking")({
  component: Ranking,
});

/** Hoje, no fuso da loja, como AAAA-MM-DD. */
function hojeEmSaoPaulo() {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "America/Sao_Paulo" }).format(new Date());
}

const MEDALHAS = ["🥇", "🥈", "🥉"];

function Ranking() {
  const { lojas, lojaAtiva, loja, carregando } = useLojaAtiva();
  const [periodo, setPeriodo] = useState<"dia" | "mes">("dia");
  const [alcance, setAlcance] = useState<"loja" | "conta">("loja");

  const hoje = hojeEmSaoPaulo();
  const de = periodo === "dia" ? hoje : `${hoje.slice(0, 7)}-01`;
  const lojaFiltro = alcance === "loja" ? lojaAtiva : null;

  const ranking = useQuery({
    queryKey: ["ranking", de, hoje, lojaFiltro],
    enabled: lojaAtiva !== null,
    queryFn: async () => {
      const { data, error } = await supabase.rpc("ranking_pontos", {
        p_de: de,
        p_ate: hoje,
        p_lojaid: lojaFiltro ?? undefined,
      });
      if (error) throw error;
      return data ?? [];
    },
  });

  if (carregando) {
    return (
      <main className="mx-auto min-h-screen max-w-3xl space-y-6 p-6">
        <Nav />
        <p className="text-muted-foreground">Carregando...</p>
      </main>
    );
  }

  if (lojas.length === 0) {
    return (
      <main className="mx-auto min-h-screen max-w-3xl space-y-6 p-6">
        <Nav />
        <h1 className="text-3xl font-bold">Ranking</h1>
        <AvisoSemLoja />
      </main>
    );
  }

  const linhas = ranking.data ?? [];
  const botao = (ativo: boolean) =>
    `rounded-lg px-3 py-1.5 text-sm ${ativo ? "bg-card font-semibold text-foreground" : "text-muted-foreground"}`;

  return (
    <main className="mx-auto min-h-screen max-w-3xl space-y-6 p-6">
      <Nav />
      <h1 className="text-3xl font-bold">Ranking</h1>

      <div className="flex flex-wrap gap-6">
        <div className="flex gap-1 rounded-lg border border-border p-1">
          <button className={botao(periodo === "dia")} onClick={() => setPeriodo("dia")}>
            Hoje
          </button>
          <button className={botao(periodo === "mes")} onClick={() => setPeriodo("mes")}>
            Este mês
          </button>
        </div>
        <div className="flex gap-1 rounded-lg border border-border p-1">
          <button className={botao(alcance === "loja")} onClick={() => setAlcance("loja")}>
            {loja?.nome ?? "Loja"}
          </button>
          <button className={botao(alcance === "conta")} onClick={() => setAlcance("conta")}>
            Todas as lojas
          </button>
        </div>
      </div>

      <p className="text-xs text-muted-foreground">
        Soma dos pontos aprovados {periodo === "dia" ? "hoje" : "neste mês"}, pela data da aprovação.
        {alcance === "conta" && " Quem trabalha em mais de uma loja soma os pontos de todas."}
      </p>

      {ranking.isLoading && <p className="text-muted-foreground">Carregando...</p>}
      {ranking.isError && <p className="text-sm text-destructive">{(ranking.error as Error).message}</p>}

      <ol className="space-y-2">
        {linhas.map((l, i) => (
          <li
            key={l.funcionarioid}
            className="flex items-center justify-between rounded-lg border border-border bg-card px-4 py-3"
          >
            <span className="flex items-center gap-3">
              <span className="w-8 text-center text-lg">{MEDALHAS[i] ?? `${i + 1}º`}</span>
              <span className="font-medium">{l.nomecompleto}</span>
            </span>
            <span className="text-sm text-muted-foreground">
              <strong className="text-accent">{l.pontos}</strong> pontos · {l.entregas}{" "}
              {l.entregas === 1 ? "entrega" : "entregas"}
            </span>
          </li>
        ))}
      </ol>

      {!ranking.isLoading && linhas.length === 0 && (
        <p className="rounded-lg border border-dashed border-border px-4 py-6 text-center text-sm text-muted-foreground">
          Ninguém pontuou {periodo === "dia" ? "hoje" : "neste mês"} ainda.
        </p>
      )}
    </main>
  );
}
