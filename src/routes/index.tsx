import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/")({
  component: Home,
});

function Home() {
  return (
    <main className="min-h-screen flex items-center justify-center bg-background">
      <div className="text-center space-y-4 p-8">
        <h1 className="text-3xl font-bold">Painel de Gestão</h1>
        <p className="text-muted-foreground max-w-md">
          Estrutura do app restaurada. O código legado (Python/Flask) está no
          repositório e será reconstruído aqui em fases.
        </p>
      </div>
    </main>
  );
}
