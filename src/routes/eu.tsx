// Etapa 1.12, parte C1 — o celular do colaborador.
//
// Desenhado para caber em 360 px de largura: é o telefone que a equipe tem,
// não o do escritório. Barra de baixo com quatro destinos, alvos grandes o
// bastante para o polegar, e nada que o gestor veria (CPF, dinheiro, papéis).
//
// ACEITAR tarefa não mora aqui: isso é só no tablet da loja.
import { createFileRoute, redirect, Link, Outlet, useRouterState } from "@tanstack/react-router";
import { supabase } from "@/integrations/supabase/client";
import { meuAcesso } from "@/integrations/supabase/destino";

export const Route = createFileRoute("/eu")({
  ssr: false,
  beforeLoad: async () => {
    // getSession() é local: não gasta uma ida ao servidor só para saber se
    // existe token. Quem confere de verdade é meuAcesso(), no banco.
    const { data } = await supabase.auth.getSession();
    if (!data.session) throw redirect({ to: "/auth" });
    const acesso = await meuAcesso();
    if (acesso.tipo !== "colaborador") throw redirect({ to: "/sem-acesso" });
    if (acesso.semsenha || acesso.sempin || acesso.politicapendente) {
      throw redirect({ to: "/primeiro-acesso" });
    }
  },
  component: Celular,
});

const DESTINOS = [
  { para: "/eu", nome: "Início", icone: "M3 10.5 12 4l9 6.5V20a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z" },
  { para: "/eu/tarefas", nome: "Tarefas", icone: "M9 5h10M9 12h10M9 19h10M4 5l1 1 2-2M4 12l1 1 2-2M4 19l1 1 2-2" },
  { para: "/eu/extrato", nome: "Extrato", icone: "M4 5h16v14H4zM8 9h8M8 13h8M8 17h4" },
  { para: "/eu/perfil", nome: "Perfil", icone: "M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8ZM4 21a8 8 0 0 1 16 0" },
] as const;

function Celular() {
  const caminho = useRouterState({ select: (s) => s.location.pathname });

  return (
    <div className="mx-auto flex min-h-screen w-full max-w-md flex-col bg-background">
      {/* pb-24: a barra de baixo é fixa e não pode tapar o fim da lista. */}
      <main className="flex-1 px-4 pb-24 pt-5">
        <Outlet />
      </main>

      <nav className="fixed inset-x-0 bottom-0 z-10 mx-auto flex w-full max-w-md border-t border-border bg-background pb-[env(safe-area-inset-bottom)]">
        {DESTINOS.map((d) => {
          const aqui = d.para === "/eu" ? caminho === "/eu" : caminho.startsWith(d.para);
          return (
            <Link
              key={d.para}
              to={d.para}
              className={`flex flex-1 flex-col items-center gap-1 py-2.5 text-[11px] ${
                aqui ? "text-primary" : "text-muted-foreground"
              }`}
            >
              <svg viewBox="0 0 24 24" className="h-6 w-6" fill="none" stroke="currentColor" strokeWidth="1.8"
                   strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                <path d={d.icone} />
              </svg>
              {d.nome}
            </Link>
          );
        })}
      </nav>
    </div>
  );
}
