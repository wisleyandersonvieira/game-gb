import { createFileRoute, Link } from "@tanstack/react-router";

export const Route = createFileRoute("/")({
  head: () => ({
    meta: [
      { title: "Painel de Gestão da Loja — Tarefas e Ranking" },
      {
        name: "description",
        content:
          "Acompanhe tarefas da equipe em quadro Kanban e o ranking de pontos por funcionário.",
      },
      { property: "og:title", content: "Painel de Gestão da Loja" },
      {
        property: "og:description",
        content: "Quadro de tarefas e ranking de pontos da equipe.",
      },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary_large_image" },
    ],
  }),
  component: Home,
});

function Home() {
  return (
    <main className="min-h-screen flex items-center justify-center p-8">
      <div className="max-w-xl space-y-6 text-center">
        <h1 className="text-4xl font-bold tracking-tight">Painel de Gestão</h1>
        <p className="text-muted-foreground">
          Fase 1: quadro de tarefas (Kanban) e ranking de pontos da equipe.
        </p>
        <Link
          to="/painel"
          className="inline-block rounded-lg bg-primary px-6 py-3 font-semibold text-primary-foreground"
        >
          Entrar no painel
        </Link>
      </div>
    </main>
  );
}
