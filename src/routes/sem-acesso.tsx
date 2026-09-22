import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { supabase } from "@/integrations/supabase/client";
import { Logo } from "@/ui/Logo";

export const Route = createFileRoute("/sem-acesso")({
  ssr: false,
  component: SemAcesso,
});

function SemAcesso() {
  const navigate = useNavigate();
  return (
    <main className="flex min-h-screen flex-col items-center justify-center gap-2 p-6">
      <Logo altura={40} />
      <div className="w-full max-w-md space-y-4 rounded-xl border border-border bg-card p-6 text-center">
        <h1 className="text-2xl font-bold">Sem acesso</h1>
        <p className="text-muted-foreground">
          Seu login existe, mas ainda não está ligado a nenhuma empresa. Fale com o
          administrador para liberar o seu acesso.
        </p>
        <button
          onClick={async () => {
            await supabase.auth.signOut();
            navigate({ to: "/auth" });
          }}
          className="rounded-lg border border-border px-4 py-2 text-sm"
        >
          Sair
        </button>
      </div>
    </main>
  );
}
