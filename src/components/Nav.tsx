import { Link, useNavigate } from "@tanstack/react-router";
import { supabase } from "@/integrations/supabase/client";

const itens = [
  { to: "/gestao", label: "Gestão" },
  { to: "/painel", label: "Quadro" },
  { to: "/funcionarios", label: "Equipe" },
  { to: "/tarefas", label: "Tarefas" },
] as const;

export function Nav() {
  const navigate = useNavigate();
  return (
    <header className="flex flex-wrap items-center justify-between gap-3 border-b border-border pb-4">
      <nav className="flex gap-2">
        {itens.map((i) => (
          <Link
            key={i.to}
            to={i.to}
            className="rounded-lg px-3 py-2 text-sm font-medium text-muted-foreground hover:bg-card"
            activeProps={{ className: "bg-card text-foreground" }}
          >
            {i.label}
          </Link>
        ))}
      </nav>
      <button
        onClick={async () => {
          await supabase.auth.signOut();
          navigate({ to: "/auth" });
        }}
        className="rounded-lg border border-border px-4 py-2 text-sm"
      >
        Sair
      </button>
    </header>
  );
}
