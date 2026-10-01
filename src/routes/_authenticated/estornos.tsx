// Estornos (29/09/2026, pedido do Wisley): quem aprova e estorna pode apagar
// o próprio erro da tela; o livro de pontos guarda, mas ninguém olha o livro.
// Aqui o master vê cada estorno, com QUEM fez (o nome daquela hora, que não
// muda se o e-mail mudar depois) e quando. Só o master: o banco recusa os outros.
// Entregas, resgates (cancelados e estornados) e feedbacks anulados. E, desde
// 30/09/2026, toda mudança de meta (o master delega a meta e vê o que foi feito).
import { createFileRoute } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { Pagina } from "@/ui/Pagina";
import { quandoFoi, useHojeDaConta } from "@/ui/hoje";
import { AvisoSemLoja, useLojaAtiva } from "@/lojas/loja-ativa";

export const Route = createFileRoute("/_authenticated/estornos")({
  component: Estornos,
});

type Estorno = {
  tipo: string;
  quando: string;
  lojaid: number;
  loja: string;
  pessoa: string | null;
  descricao: string | null;
  pontos: number;
  motivo: string | null;
  quem: string;
};

const ROTULO: Record<string, string> = {
  entrega: "Entrega",
  "resgate cancelado": "Resgate cancelado",
  "resgate estornado": "Resgate estornado",
  "feedback anulado": "Feedback anulado",
  // Não é estorno: é a entrega que um GERENTE registrou sem foto (30/09/2026),
  // à vista do master para ele conferir.
  "entrega sem foto": "Entrega sem foto (registrada por gerente)",
  // Também não é estorno: toda mudança de meta, com o antes e o depois (30/09/2026).
  "meta alterada": "Meta alterada",
};
const VERBO: Record<string, string> = {
  "resgate cancelado": "Cancelado",
  "feedback anulado": "Anulado",
  "meta alterada": "Alterada",
};
/** Entrega estornada tira pontos; resgate desfeito devolve. */
const sinal = (p: number) => (p > 0 ? `+${p}` : `${p}`);

function Estornos() {
  const { lojaAtiva, carregando, lojas } = useLojaAtiva();
  const relogio = useHojeDaConta();
  const lista = useQuery({
    queryKey: ["estornos", lojaAtiva],
    enabled: lojaAtiva !== null,
    queryFn: async () => {
      const { data, error } = await supabase.rpc("estornos_da_conta", { p_lojaid: lojaAtiva as number });
      if (error) throw error;
      return (data ?? []) as Estorno[];
    },
  });

  if (!carregando && lojas.length === 0) {
    return (
      <Pagina titulo="Estornos">
        <AvisoSemLoja />
      </Pagina>
    );
  }

  return (
    <Pagina titulo="Estornos">
      <p className="mb-4 text-sm text-muted-foreground">
        Tudo o que foi estornado nesta loja, e toda mudança de meta, com quem fez e quando. O nome é o que a pessoa tinha
        na hora.
      </p>
      {lista.isLoading && <p className="text-muted-foreground">Carregando...</p>}
      {lista.isError && <p className="text-destructive">{(lista.error as Error).message}</p>}
      {lista.data && lista.data.length === 0 && (
        <p className="rounded-xl border border-border bg-card p-6 text-center text-muted-foreground">
          Nenhum estorno nesta loja.
        </p>
      )}
      <ul className="space-y-2">
        {lista.data?.map((e, i) => (
          <li key={`${e.tipo}-${e.quando}-${i}`} className="rounded-xl border border-border bg-card p-4">
            <div className="flex flex-wrap items-baseline justify-between gap-2">
              <p className="font-medium">
                {ROTULO[e.tipo] ?? e.tipo}: {e.descricao ?? "—"}
                {e.pessoa ? <span className="text-muted-foreground"> · {e.pessoa}</span> : null}
              </p>
              {e.tipo !== "meta alterada" && (
                <span className={`text-sm font-semibold ${e.pontos < 0 ? "text-perigo" : "text-sucesso"}`}>{sinal(e.pontos)} pontos</span>
              )}
            </div>
            <p className="mt-1 text-sm text-muted-foreground">
              {VERBO[e.tipo] ?? "Estornado"} por <strong className="text-foreground">{e.quem}</strong>{" "}
              {quandoFoi(e.quando, relogio.data?.hoje, relogio.data?.fuso)}
              {e.motivo ? ` · motivo: ${e.motivo}` : ""}
            </p>
          </li>
        ))}
      </ul>
    </Pagina>
  );
}
