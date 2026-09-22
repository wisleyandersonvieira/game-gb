// Layout único das telas logadas: menu lateral fixo (computador), topo e
// barra inferior (celular). O menu é sempre o mesmo, em qualquer tela.
import { Link, useNavigate, useRouterState } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { Ellipsis, LogOut, Moon, PanelLeftClose, PanelLeftOpen, Sun, X } from "lucide-react";
import { useEffect, useState, type ReactNode } from "react";
import { supabase } from "@/integrations/supabase/client";
import { SeletorDeLoja } from "@/lojas/loja-ativa";
import type { GrupoMenu, ItemMenu } from "./menu";
import { carregarTemaDoUsuario, escolherTema, temaAtual, type Tema } from "./tema";
import { useUsuario } from "./usuario";

const CHAVE_RECOLHIDO = "gamegb.menurecolhido";

function ativo(caminho: string, to: string) {
  return caminho === to || caminho.startsWith(`${to}/`);
}

function BotaoTema() {
  const [tema, setTema] = useState<Tema>("claro");
  useEffect(() => setTema(temaAtual()), []);
  const proximo: Tema = tema === "escuro" ? "claro" : "escuro";
  return (
    <button
      onClick={() => {
        setTema(proximo);
        escolherTema(proximo);
      }}
      className="inline-flex h-10 w-10 items-center justify-center rounded-lg text-muted-foreground hover:bg-muted hover:text-foreground"
      title={proximo === "escuro" ? "Usar tema escuro" : "Usar tema claro"}
      aria-label={proximo === "escuro" ? "Usar tema escuro" : "Usar tema claro"}
    >
      {tema === "escuro" ? <Sun className="h-5 w-5" /> : <Moon className="h-5 w-5" />}
    </button>
  );
}

function ItemLateral({ item, caminho, recolhido }: { item: ItemMenu; caminho: string; recolhido: boolean }) {
  const eh = ativo(caminho, item.to);
  const Icone = item.icone;
  return (
    <Link
      to={item.to}
      title={recolhido ? item.label : undefined}
      aria-current={eh ? "page" : undefined}
      className={`flex items-center gap-3 rounded-lg px-3 py-2 text-sm transition ${
        eh ? "bg-primary/10 font-semibold text-primary" : "text-muted-foreground hover:bg-muted hover:text-foreground"
      } ${recolhido ? "justify-center px-0" : ""}`}
    >
      <Icone className="h-[18px] w-[18px] shrink-0" aria-hidden />
      {!recolhido && <span className="truncate">{item.label}</span>}
    </Link>
  );
}

function MenuLateral({ menu, caminho, recolhido, alternar }: { menu: GrupoMenu[]; caminho: string; recolhido: boolean; alternar: () => void }) {
  return (
    <aside
      className={`fixed inset-y-0 left-0 z-30 hidden flex-col border-r border-border bg-card md:flex ${recolhido ? "w-16" : "w-64"}`}
      aria-label="Menu principal"
    >
      <div className={`flex h-14 items-center border-b border-border ${recolhido ? "justify-center" : "px-4"}`}>
        <span className="text-lg font-bold text-primary">{recolhido ? "ST" : "STGame"}</span>
      </div>
      <nav className="flex-1 space-y-4 overflow-y-auto px-2 py-3">
        {menu.map((g) => (
          <div key={g.titulo} className="space-y-0.5">
            {g.itens.length > 1 && !recolhido && (
              <p className="px-3 pb-1 text-[11px] font-semibold uppercase tracking-wider text-muted-foreground/80">{g.titulo}</p>
            )}
            {g.itens.map((i) => (
              <ItemLateral key={i.to} item={i} caminho={caminho} recolhido={recolhido} />
            ))}
          </div>
        ))}
      </nav>
      <button
        onClick={alternar}
        className={`flex h-12 items-center gap-2 border-t border-border text-sm text-muted-foreground hover:bg-muted ${recolhido ? "justify-center" : "px-4"}`}
        aria-label={recolhido ? "Abrir o menu" : "Recolher o menu"}
      >
        {recolhido ? <PanelLeftOpen className="h-5 w-5" /> : <PanelLeftClose className="h-5 w-5" />}
        {!recolhido && "Recolher menu"}
      </button>
    </aside>
  );
}

function MenuCompleto({ menu, caminho, fechar, sair }: { menu: GrupoMenu[]; caminho: string; fechar: () => void; sair: () => void }) {
  return (
    <div className="fixed inset-0 z-50 flex flex-col bg-background md:hidden" role="dialog" aria-modal="true" aria-label="Menu completo">
      <div className="flex h-14 items-center justify-between border-b border-border px-4">
        <span className="text-lg font-bold text-primary">Menu</span>
        <button onClick={fechar} className="inline-flex h-11 w-11 items-center justify-center rounded-lg hover:bg-muted" aria-label="Fechar o menu">
          <X className="h-6 w-6" />
        </button>
      </div>
      <nav className="flex-1 space-y-5 overflow-y-auto px-4 py-4 pb-24">
        {menu.map((g) => (
          <div key={g.titulo}>
            <p className="pb-1 text-[11px] font-semibold uppercase tracking-wider text-muted-foreground">{g.titulo}</p>
            <div className="grid grid-cols-2 gap-2">
              {g.itens.map((i) => {
                const Icone = i.icone;
                const eh = ativo(caminho, i.to);
                return (
                  <Link
                    key={i.to}
                    to={i.to}
                    onClick={fechar}
                    className={`flex min-h-12 items-center gap-2 rounded-xl border px-3 py-2 text-sm ${
                      eh ? "border-primary bg-primary/10 font-semibold text-primary" : "border-border bg-card"
                    }`}
                  >
                    <Icone className="h-5 w-5 shrink-0" aria-hidden />
                    <span className="leading-tight">{i.label}</span>
                  </Link>
                );
              })}
            </div>
          </div>
        ))}
        <button onClick={sair} className="flex min-h-12 w-full items-center justify-center gap-2 rounded-xl border border-border bg-card text-sm">
          <LogOut className="h-5 w-5" /> Sair
        </button>
      </nav>
    </div>
  );
}

function BarraInferior({ itens, caminho, abrirMais }: { itens: ItemMenu[]; caminho: string; abrirMais: () => void }) {
  return (
    <nav
      className="fixed inset-x-0 bottom-0 z-40 grid border-t border-border bg-card pb-[env(safe-area-inset-bottom)] md:hidden"
      style={{ gridTemplateColumns: `repeat(${itens.length + 1}, minmax(0, 1fr))` }}
      aria-label="Atalhos"
    >
      {itens.map((i) => {
        const Icone = i.icone;
        const eh = ativo(caminho, i.to);
        return (
          <Link
            key={i.to}
            to={i.to}
            aria-current={eh ? "page" : undefined}
            className={`flex min-h-14 flex-col items-center justify-center gap-0.5 text-[11px] ${eh ? "font-semibold text-primary" : "text-muted-foreground"}`}
          >
            <Icone className="h-5 w-5" aria-hidden />
            {i.label}
          </Link>
        );
      })}
      <button onClick={abrirMais} className="flex min-h-14 flex-col items-center justify-center gap-0.5 text-[11px] text-muted-foreground">
        <Ellipsis className="h-5 w-5" aria-hidden />
        Mais
      </button>
    </nav>
  );
}

export function Layout({
  menu,
  barra,
  comLoja = true,
  titulo,
  children,
}: {
  menu: GrupoMenu[];
  barra: ItemMenu[];
  comLoja?: boolean;
  titulo?: string;
  children: ReactNode;
}) {
  const caminho = useRouterState({ select: (s) => s.location.pathname });
  const navigate = useNavigate();
  const usuario = useUsuario();
  const [recolhido, setRecolhido] = useState(false);
  const [mais, setMais] = useState(false);

  useEffect(() => {
    carregarTemaDoUsuario();
    try {
      setRecolhido(localStorage.getItem(CHAVE_RECOLHIDO) === "1");
    } catch {
      /* sem memória: menu aberto */
    }
  }, []);
  useEffect(() => setMais(false), [caminho]);

  const conta = useQuery({
    queryKey: ["nome-da-conta"],
    enabled: comLoja,
    queryFn: async () => {
      const { data } = await supabase.from("contas").select("nome").limit(1).maybeSingle();
      return data?.nome ?? "";
    },
  });

  function alternar() {
    const novo = !recolhido;
    setRecolhido(novo);
    try {
      localStorage.setItem(CHAVE_RECOLHIDO, novo ? "1" : "0");
    } catch {
      /* sem memória */
    }
  }
  async function sair() {
    await supabase.auth.signOut();
    navigate({ to: "/auth" });
  }

  return (
    <div className="min-h-screen bg-background">
      <MenuLateral menu={menu} caminho={caminho} recolhido={recolhido} alternar={alternar} />
      <div className={recolhido ? "md:pl-16" : "md:pl-64"}>
        <header className="sticky top-0 z-20 flex h-14 items-center gap-2 border-b border-border bg-card/95 px-3 backdrop-blur sm:px-5">
          <p className="min-w-0 flex-1 truncate font-semibold">{comLoja ? conta.data || " " : titulo}</p>
          {comLoja && (
            <div className="min-w-0 max-w-[45vw] sm:max-w-none">
              <SeletorDeLoja />
            </div>
          )}
          <BotaoTema />
          <span className="hidden max-w-48 truncate text-sm text-muted-foreground lg:inline" title={usuario?.email}>
            {usuario?.nome}
          </span>
          <button
            onClick={sair}
            className="hidden h-10 items-center gap-2 rounded-lg px-3 text-sm text-muted-foreground hover:bg-muted hover:text-foreground md:inline-flex"
          >
            <LogOut className="h-4 w-4" /> Sair
          </button>
        </header>
        <main className="px-3 pb-24 pt-4 sm:px-6 sm:pt-6 md:pb-10">{children}</main>
      </div>
      <BarraInferior itens={barra} caminho={caminho} abrirMais={() => setMais(true)} />
      {mais && <MenuCompleto menu={menu} caminho={caminho} fechar={() => setMais(false)} sair={sair} />}
    </div>
  );
}
