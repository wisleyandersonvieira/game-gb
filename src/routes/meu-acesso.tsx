// Tela de espera das visões novas (Etapa 1.12, parte A).
// O acesso já funciona; as telas do tablet (parte B) e do celular (parte C)
// vêm nas próximas etapas.
import { createFileRoute, redirect, useNavigate } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { meuAcesso } from "@/integrations/supabase/destino";
import { Logo } from "@/ui/Logo";

export const Route = createFileRoute("/meu-acesso")({
  ssr: false,
  beforeLoad: async () => {
    const { data } = await supabase.auth.getUser();
    if (!data.user) throw redirect({ to: "/auth" });
  },
  component: MeuAcesso,
});

function MeuAcesso() {
  const navigate = useNavigate();
  const acesso = useQuery({ queryKey: ["meu-acesso"], queryFn: meuAcesso });
  const a = acesso.data;

  async function sair() {
    await supabase.auth.signOut();
    navigate({ to: "/auth" });
  }

  return (
    <main className="mx-auto flex min-h-screen max-w-md flex-col items-center justify-center gap-4 p-6 text-center">
      <Logo altura={40} />
      {acesso.isLoading ? (
        <p className="text-sm text-muted-foreground">Carregando…</p>
      ) : a?.tipo === "desligado" ? (
        <p className="text-sm text-muted-foreground">Seu acesso foi encerrado. Fale com o seu gestor.</p>
      ) : (
        <>
          <h1 className="font-display text-2xl font-semibold">
            {a?.tipo === "loja" ? `Tablet da ${a?.loja ?? "loja"}` : `Olá, ${a?.nome ?? ""}`}
          </h1>
          <p className="text-sm text-muted-foreground">
            Seu acesso está pronto. As telas {a?.tipo === "loja" ? "do tablet" : "do celular"} entram no ar na próxima etapa.
          </p>
        </>
      )}
      <button onClick={sair} className="rounded-lg border border-border px-4 py-2 text-sm">
        Sair
      </button>
    </main>
  );
}
