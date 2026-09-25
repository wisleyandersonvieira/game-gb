// Meu perfil: quem sou, onde trabalho, e a saída.
import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { esquecerAcesso, meuAcesso } from "@/integrations/supabase/destino";
import { ESTAVEL } from "@/ui/prazos";

export const Route = createFileRoute("/eu/perfil")({ component: Perfil });

function Perfil() {
  const navigate = useNavigate();
  const acesso = useQuery({ queryKey: ["meu-acesso"], queryFn: meuAcesso, staleTime: ESTAVEL });

  async function sair() {
    await supabase.auth.signOut();
    esquecerAcesso();
    navigate({ to: "/auth" });
  }

  return (
    <div className="space-y-4">
      <h1 className="font-display text-2xl font-semibold">Meu perfil</h1>

      <section className="space-y-3 rounded-2xl border border-border bg-card p-5">
        <Linha rotulo="Nome" valor={acesso.data?.nome ?? "—"} />
        <Linha rotulo="Empresa" valor={acesso.data?.conta ?? "—"} />
        <Linha rotulo="Loja" valor={acesso.data?.loja ?? "—"} />
      </section>

      <p className="rounded-2xl border border-border bg-muted/40 p-4 text-sm text-muted-foreground">
        Seu PIN de 6 dígitos é o que assina o que você pega e entrega no tablet da loja. Não conte para ninguém.
      </p>

      <button onClick={sair} className="w-full rounded-xl border border-border px-4 py-3 text-sm">
        Sair
      </button>
    </div>
  );
}

function Linha({ rotulo, valor }: { rotulo: string; valor: string }) {
  return (
    <div className="flex items-baseline justify-between gap-3">
      <span className="text-sm text-muted-foreground">{rotulo}</span>
      <span className="truncate text-sm font-medium">{valor}</span>
    </div>
  );
}
