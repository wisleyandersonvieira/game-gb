import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useQuery, useQueryClient, useMutation } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";

export const Route = createFileRoute("/_authenticated/painel")({
  component: Painel,
});

type Entrega = {
  id: string;
  status_validacao: string;
  pontos_ganhos: number;
  observacao: string | null;
  data_envio: string;
  tarefas: { titulo: string; pontos: number } | null;
  funcionarios: { nome: string; setor: string | null } | null;
};

const COLUNAS = [
  { status: "Pendente", titulo: "Pendentes de validação" },
  { status: "Aprovada", titulo: "Aprovadas" },
  { status: "Recusada", titulo: "Recusadas" },
];

function Painel() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();

  const entregas = useQuery({
    queryKey: ["entregas"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("entregas")
        .select(
          "id, status_validacao, pontos_ganhos, observacao, data_envio, tarefas(titulo, pontos), funcionarios(nome, setor)",
        )
        .order("data_envio", { ascending: false });
      if (error) throw error;
      return (data ?? []) as unknown as Entrega[];
    },
  });

  const mudarStatus = useMutation({
    mutationFn: async ({
      id,
      status,
      pontos,
    }: {
      id: string;
      status: string;
      pontos: number;
    }) => {
      const { error } = await supabase
        .from("entregas")
        .update({ status_validacao: status, pontos_ganhos: pontos })
        .eq("id", id);
      if (error) throw error;
    },
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["entregas"] }),
  });

  const ranking = (() => {
    const mapa = new Map<string, number>();
    for (const e of entregas.data ?? []) {
      if (e.status_validacao !== "Aprovada") continue;
      const nome = e.funcionarios?.nome ?? "Sem nome";
      mapa.set(nome, (mapa.get(nome) ?? 0) + (e.pontos_ganhos ?? 0));
    }
    return [...mapa.entries()].sort((a, b) => b[1] - a[1]);
  })();

  return (
    <main className="min-h-screen p-6 space-y-8">
      <Nav />
      <h1 className="text-3xl font-bold">Quadro de Tarefas</h1>

      {entregas.isLoading && <p className="text-muted-foreground">Carregando...</p>}
      {entregas.error && (
        <p className="text-destructive">Erro ao carregar as tarefas.</p>
      )}

      <div className="grid gap-4 md:grid-cols-3">
        {COLUNAS.map((col) => {
          const itens = (entregas.data ?? []).filter(
            (e) => e.status_validacao === col.status,
          );
          return (
            <section
              key={col.status}
              className="rounded-xl border border-border bg-card p-4 space-y-3"
            >
              <h2 className="font-semibold">
                {col.titulo}{" "}
                <span className="text-muted-foreground">({itens.length})</span>
              </h2>
              {itens.length === 0 && (
                <p className="text-sm text-muted-foreground">Nada por aqui.</p>
              )}
              {itens.map((e) => (
                <article
                  key={e.id}
                  className="rounded-lg border border-border bg-background p-3 space-y-2"
                >
                  <p className="font-medium">{e.tarefas?.titulo ?? "Tarefa"}</p>
                  <p className="text-sm text-muted-foreground">
                    {e.funcionarios?.nome ?? "—"} ·{" "}
                    {new Date(e.data_envio).toLocaleDateString("pt-BR")}
                  </p>
                  {e.observacao && <p className="text-sm">{e.observacao}</p>}
                  {col.status === "Pendente" && (
                    <div className="flex gap-2">
                      <button
                        onClick={() =>
                          mudarStatus.mutate({
                            id: e.id,
                            status: "Aprovada",
                            pontos: e.tarefas?.pontos ?? 0,
                          })
                        }
                        className="rounded-md bg-primary px-3 py-1 text-sm font-semibold text-primary-foreground"
                      >
                        Aprovar
                      </button>
                      <button
                        onClick={() =>
                          mudarStatus.mutate({
                            id: e.id,
                            status: "Recusada",
                            pontos: 0,
                          })
                        }
                        className="rounded-md bg-destructive px-3 py-1 text-sm font-semibold text-destructive-foreground"
                      >
                        Recusar
                      </button>
                    </div>
                  )}
                </article>
              ))}
            </section>
          );
        })}
      </div>

      <section className="rounded-xl border border-border bg-card p-4">
        <h2 className="mb-3 text-xl font-semibold">Ranking de pontos</h2>
        {ranking.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            Ainda não há tarefas aprovadas.
          </p>
        ) : (
          <ol className="space-y-2">
            {ranking.map(([nome, pontos], i) => (
              <li
                key={nome}
                className="flex items-center justify-between rounded-lg bg-background px-3 py-2"
              >
                <span>
                  <span className="mr-2 text-accent font-bold">{i + 1}º</span>
                  {nome}
                </span>
                <span className="font-semibold">{pontos} pts</span>
              </li>
            ))}
          </ol>
        )}
      </section>
    </main>
  );
}
