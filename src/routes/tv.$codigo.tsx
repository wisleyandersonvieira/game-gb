// Modo TV: painel de UMA loja, sem login, só leitura.
// Tudo chega por uma única função do banco (painel_da_tv), que recebe o código
// do link. Link revogado, loja desativada ou conta suspensa: "Painel indisponível".
import { createFileRoute } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { hora, PainelDaLoja, type DadosPainel } from "@/painel/PainelDaLoja";
import { soltarFogosUmaVezPorDia } from "@/painel/fogos";

export const Route = createFileRoute("/tv/$codigo")({
  ssr: false,
  head: () => ({
    meta: [
      { title: "Painel da loja" },
      // A TV não deve aparecer em buscadores nem ser indexada.
      { name: "robots", content: "noindex, nofollow" },
    ],
  }),
  component: TelaTv,
});

const ATUALIZAR_A_CADA = 30_000;

type Resposta = ({ disponivel: true } & DadosPainel) | { disponivel: false };

function TelaTv() {
  const { codigo } = Route.useParams();
  const [dica, setDica] = useState(true);

  const painel = useQuery({
    queryKey: ["tv", codigo],
    refetchInterval: ATUALIZAR_A_CADA,
    refetchIntervalInBackground: true,
    retry: true,
    queryFn: async () => {
      const { data, error } = await supabase.rpc("painel_da_tv", { p_codigo: codigo });
      if (error) throw error;
      return data as unknown as Resposta;
    },
  });

  // Mantém a tela acesa (celulares e TVs com navegador que suportam).
  useEffect(() => {
    let trava: { release: () => Promise<void> } | null = null;
    const pedir = async () => {
      try {
        trava = await (navigator as any).wakeLock?.request("screen");
      } catch {
        /* sem suporte: a tela pode apagar sozinha */
      }
    };
    pedir();
    const aoVoltar = () => document.visibilityState === "visible" && pedir();
    document.addEventListener("visibilitychange", aoVoltar);
    return () => {
      document.removeEventListener("visibilitychange", aoVoltar);
      trava?.release().catch(() => {});
    };
  }, []);

  // A dica de tela cheia some sozinha.
  useEffect(() => {
    const t = window.setTimeout(() => setDica(false), 8000);
    return () => window.clearTimeout(t);
  }, []);

  const r = painel.data;
  const dados = r && r.disponivel ? r : null;

  useEffect(() => {
    if (!dados) return;
    const { total, aprovadas } = dados.progresso;
    if (total > 0 && aprovadas >= total) soltarFogosUmaVezPorDia(`tv-${dados.loja}`, dados.hoje);
  }, [dados]);

  // Tocar em qualquer lugar liga a tela cheia (o navegador exige um toque).
  function telaCheia() {
    setDica(false);
    document.documentElement.requestFullscreen?.().catch(() => {});
  }

  if (r && !r.disponivel) {
    return (
      <main className="flex min-h-screen items-center justify-center p-8 text-center">
        <div className="space-y-3">
          <p className="text-5xl font-bold">Painel indisponível</p>
          <p className="text-xl text-muted-foreground">Peça um link novo ao responsável pela loja.</p>
        </div>
      </main>
    );
  }

  return (
    <main onClick={telaCheia} className="min-h-screen cursor-none space-y-8 p-8">
      <header className="flex flex-wrap items-baseline justify-between gap-4">
        <h1 className="text-5xl font-bold">{dados?.loja ?? "Carregando..."}</h1>
        <p className={`text-2xl ${painel.isError ? "text-destructive" : "text-muted-foreground"}`}>
          {painel.isError
            ? "Sem conexão. Tentando de novo..."
            : dados
              ? `Atualizado às ${hora(dados.atualizadoem)}`
              : ""}
        </p>
      </header>

      {dados && <PainelDaLoja dados={dados} tv />}

      {dica && (
        <p className="fixed bottom-4 left-1/2 -translate-x-1/2 rounded-lg bg-card px-4 py-2 text-lg text-muted-foreground">
          Toque na tela para tela cheia
        </p>
      )}
    </main>
  );
}
