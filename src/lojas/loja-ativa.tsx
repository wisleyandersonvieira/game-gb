import { createContext, useContext, useMemo, useState, type ReactNode } from "react";
import { useQuery } from "@tanstack/react-query";
import { Link } from "@tanstack/react-router";
import { supabase } from "@/integrations/supabase/client";

export type Loja = {
  lojaid: number;
  nome: string;
  cidade: string | null;
  endereco: string | null;
  ativa: boolean;
  responsavelagendamentosid: number | null;
};

const CHAVE_NAVEGADOR = "gamegb.lojaAtiva";

function lerEscolha(): number | null {
  try {
    const bruto = localStorage.getItem(CHAVE_NAVEGADOR);
    const n = bruto === null ? NaN : Number(bruto);
    return Number.isInteger(n) ? n : null;
  } catch {
    // Navegador anônimo ou armazenamento bloqueado: seguimos sem memória.
    return null;
  }
}

function guardarEscolha(lojaid: number) {
  try {
    localStorage.setItem(CHAVE_NAVEGADOR, String(lojaid));
  } catch {
    /* sem memória entre visitas; a tela continua funcionando */
  }
}

type Contexto = {
  lojas: Loja[];
  carregando: boolean;
  lojaAtiva: number | null;
  loja: Loja | null;
  escolherLoja: (lojaid: number) => void;
};

const Ctx = createContext<Contexto | null>(null);

export function ProvedorLojaAtiva({ children }: { children: ReactNode }) {
  const [escolhida, setEscolhida] = useState<number | null>(() => lerEscolha());

  const consulta = useQuery({
    queryKey: ["lojas-ativas"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("lojas")
        .select("lojaid, nome, cidade, endereco, ativa, responsavelagendamentosid")
        .eq("ativa", true)
        .order("nome");
      if (error) throw error;
      return (data ?? []) as Loja[];
    },
  });

  const lojas = useMemo(() => consulta.data ?? [], [consulta.data]);

  // Uma loja só já vem escolhida. Se a lembrada saiu do ar (desativada),
  // cai para a primeira em vez de deixar a tela sem loja.
  const lojaAtiva = useMemo(() => {
    if (lojas.length === 0) return null;
    if (escolhida !== null && lojas.some((l) => l.lojaid === escolhida)) return escolhida;
    return lojas[0].lojaid;
  }, [lojas, escolhida]);

  const valor = useMemo<Contexto>(
    () => ({
      lojas,
      carregando: consulta.isLoading,
      lojaAtiva,
      loja: lojas.find((l) => l.lojaid === lojaAtiva) ?? null,
      escolherLoja: (lojaid: number) => {
        setEscolhida(lojaid);
        guardarEscolha(lojaid);
      },
    }),
    [lojas, consulta.isLoading, lojaAtiva],
  );

  return <Ctx.Provider value={valor}>{children}</Ctx.Provider>;
}

export function useLojaAtiva(): Contexto {
  const ctx = useContext(Ctx);
  if (!ctx) throw new Error("useLojaAtiva precisa estar dentro de <ProvedorLojaAtiva>.");
  return ctx;
}

/** Mostrado pelas telas do app enquanto o cliente não tem nenhuma loja. */
export function AvisoSemLoja() {
  return (
    <div className="space-y-3 rounded-xl border border-border bg-card p-6 text-center">
      <p className="font-medium">Cadastre sua primeira loja</p>
      <p className="text-sm text-muted-foreground">
        As telas do dia a dia trabalham sempre dentro de uma loja. Assim que você cadastrar
        uma, elas passam a funcionar.
      </p>
      <Link
        to="/gestao"
        className="inline-block rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground"
      >
        Ir para a gestão
      </Link>
    </div>
  );
}

/** Seletor de loja ativa, no topo do app. */
export function SeletorDeLoja() {
  const { lojas, lojaAtiva, escolherLoja } = useLojaAtiva();

  if (lojas.length === 0) return null;

  if (lojas.length === 1) {
    return (
      <span className="rounded-lg border border-border px-3 py-2 text-sm text-muted-foreground">
        {lojas[0].nome}
      </span>
    );
  }

  return (
    <label className="flex items-center gap-2 text-sm text-muted-foreground">
      <span className="sr-only">Loja ativa</span>
      <select
        value={lojaAtiva ?? ""}
        onChange={(e) => escolherLoja(Number(e.target.value))}
        className="rounded-lg border border-border bg-background px-3 py-2 text-sm text-foreground"
      >
        {lojas.map((l) => (
          <option key={l.lojaid} value={l.lojaid}>
            {l.nome}
          </option>
        ))}
      </select>
    </label>
  );
}
