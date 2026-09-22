import { Link, useNavigate, useRouterState } from "@tanstack/react-router";
import { useEffect, useRef, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { SeletorDeLoja } from "@/lojas/loja-ativa";

type Item = { to: string; label: string };
type Grupo = { titulo: string; itens: Item[] };

/** Menu em grupos. Grupo com um item só vira link direto. */
const grupos: Grupo[] = [
  {
    titulo: "Operação",
    itens: [
      { to: "/operacional", label: "Painel" },
      { to: "/painel", label: "Quadro" },
      { to: "/tarefas", label: "Tarefas" },
      { to: "/metas", label: "Metas" },
      { to: "/agenda", label: "Agenda" },
    ],
  },
  {
    titulo: "Pessoas",
    itens: [
      { to: "/funcionarios", label: "Equipe" },
      { to: "/feedbacks", label: "Feedbacks" },
      { to: "/justificativas", label: "Justificativas" },
      { to: "/solicitacoes", label: "Solicitações" },
      { to: "/canal-confidencial", label: "Canal confidencial" },
    ],
  },
  {
    titulo: "RH",
    itens: [
      { to: "/comunicados", label: "Comunicados" },
      { to: "/documentos-pessoais", label: "Documentos pessoais" },
      { to: "/onboarding", label: "Onboarding" },
    ],
  },
  {
    titulo: "Gamificação",
    itens: [
      { to: "/ranking", label: "Ranking" },
      { to: "/conquistas", label: "Conquistas" },
      { to: "/premios", label: "Prêmios" },
      { to: "/extrato", label: "Extrato" },
    ],
  },
  { titulo: "Relatórios", itens: [{ to: "/relatorios", label: "Relatórios" }] },
  {
    titulo: "Gestão",
    itens: [
      { to: "/gestao", label: "Lojas" },
      { to: "/configuracoes", label: "Configurações" },
    ],
  },
];

const estaEm = (caminho: string, g: Grupo) => g.itens.some((i) => caminho === i.to || caminho.startsWith(`${i.to}/`));

export function Nav() {
  const navigate = useNavigate();
  const caminho = useRouterState({ select: (s) => s.location.pathname });
  const [aberto, setAberto] = useState<string | null>(null);
  const [menuCelular, setMenuCelular] = useState(false);
  const barra = useRef<HTMLElement>(null);

  // Fecha tudo ao trocar de tela e ao clicar fora.
  useEffect(() => {
    setAberto(null);
    setMenuCelular(false);
  }, [caminho]);
  useEffect(() => {
    const fora = (e: MouseEvent) => {
      if (barra.current && !barra.current.contains(e.target as Node)) setAberto(null);
    };
    document.addEventListener("mousedown", fora);
    return () => document.removeEventListener("mousedown", fora);
  }, []);

  const sair = async () => {
    await supabase.auth.signOut();
    navigate({ to: "/auth" });
  };

  const atual = grupos.flatMap((g) => g.itens).find((i) => caminho === i.to);

  return (
    <header className="space-y-3 border-b border-border pb-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        {/* Computador: grupos com lista suspensa */}
        <nav ref={barra} className="hidden flex-wrap gap-1 md:flex">
          {grupos.map((g) =>
            g.itens.length === 1 ? (
              <Link
                key={g.titulo}
                to={g.itens[0].to}
                className="rounded-lg px-3 py-2 text-sm font-medium text-muted-foreground hover:bg-card"
                activeProps={{ className: "bg-card text-foreground" }}
              >
                {g.titulo}
              </Link>
            ) : (
              <div key={g.titulo} className="relative">
                <button
                  onClick={() => setAberto(aberto === g.titulo ? null : g.titulo)}
                  aria-expanded={aberto === g.titulo}
                  className={`rounded-lg px-3 py-2 text-sm font-medium hover:bg-card ${
                    estaEm(caminho, g) ? "bg-card text-foreground" : "text-muted-foreground"
                  }`}
                >
                  {g.titulo} ▾
                </button>
                {aberto === g.titulo && (
                  <div className="absolute left-0 z-30 mt-1 min-w-48 rounded-lg border border-border bg-background p-1 shadow-lg">
                    {g.itens.map((i) => (
                      <Link
                        key={i.to}
                        to={i.to}
                        className="block rounded-md px-3 py-2 text-sm text-muted-foreground hover:bg-card hover:text-foreground"
                        activeProps={{ className: "bg-card text-foreground" }}
                      >
                        {i.label}
                      </Link>
                    ))}
                  </div>
                )}
              </div>
            ),
          )}
        </nav>

        {/* Celular: um botão abre o menu inteiro */}
        <button
          onClick={() => setMenuCelular(!menuCelular)}
          aria-expanded={menuCelular}
          className="rounded-lg border border-border px-4 py-2 text-sm font-medium md:hidden"
        >
          {menuCelular ? "✕ Fechar" : `☰ ${atual?.label ?? "Menu"}`}
        </button>

        <div className="flex flex-wrap items-center gap-2">
          <SeletorDeLoja />
          <button onClick={sair} className="rounded-lg border border-border px-4 py-2 text-sm">
            Sair
          </button>
        </div>
      </div>

      {menuCelular && (
        <nav className="grid grid-cols-2 gap-x-4 gap-y-3 rounded-xl border border-border bg-card p-4 md:hidden">
          {grupos.map((g) => (
            <div key={g.titulo} className="space-y-1">
              <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">{g.titulo}</p>
              {g.itens.map((i) => (
                <Link
                  key={i.to}
                  to={i.to}
                  className="block rounded-md px-2 py-2 text-sm hover:bg-background"
                  activeProps={{ className: "bg-background font-semibold" }}
                >
                  {i.label}
                </Link>
              ))}
            </div>
          ))}
        </nav>
      )}
    </header>
  );
}
