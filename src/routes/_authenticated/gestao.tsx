import { createFileRoute, Link, redirect } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { Nav } from "@/components/Nav";

export const Route = createFileRoute("/_authenticated/gestao")({
  ssr: false,
  beforeLoad: async () => {
    const { data: conta } = await supabase.rpc("minha_conta");
    if (conta === null || conta === undefined) throw redirect({ to: "/sem-acesso" });
  },
  component: Gestao,
});

function Gestao() {
  const dados = useQuery({
    queryKey: ["minha-gestao"],
    queryFn: async () => {
      const { data: conta, error } = await supabase
        .from("contas")
        .select("nome, cidade, limitelojas, status")
        .single();
      if (error) throw error;
      const { data: lojas, error: erroLojas } = await supabase
        .from("lojas")
        .select("lojaid, nome, cidade, ativa")
        .order("nome");
      if (erroLojas) throw erroLojas;
      return { conta, lojas: lojas ?? [] };
    },
  });

  const conta = dados.data?.conta;
  const lojas = dados.data?.lojas ?? [];
  const ativas = lojas.filter((l) => l.ativa).length;

  return (
    <main className="mx-auto min-h-screen max-w-4xl space-y-6 p-6">
      <Nav />

      {dados.isLoading && <p className="text-muted-foreground">Carregando...</p>}

      {conta && (
        <>
          <div className="flex flex-wrap items-baseline justify-between gap-2">
            <h1 className="text-3xl font-bold">{conta.nome}</h1>
            <p className="text-sm text-muted-foreground">
              <strong className={ativas >= conta.limitelojas ? "text-accent" : "text-foreground"}>
                {ativas}
              </strong>{" "}
              de {conta.limitelojas} lojas usadas
            </p>
          </div>

          {conta.status === "suspensa" && (
            <p className="rounded-lg border border-border bg-card px-4 py-3 text-sm text-accent">
              Sua conta está suspensa: dá para consultar, mas não para cadastrar nem alterar.
              Fale com o suporte.
            </p>
          )}

          <section className="space-y-2">
            <h2 className="text-sm font-semibold">Suas lojas</h2>
            {lojas.length === 0 ? (
              <p className="rounded-lg border border-border bg-card px-4 py-3 text-sm text-muted-foreground">
                Nenhuma loja cadastrada ainda. O cadastro de lojas entra na próxima etapa
                (Fase 4). Até lá, as telas do app ficam sem loja para mostrar.
              </p>
            ) : (
              lojas.map((l) => (
                <div
                  key={l.lojaid}
                  className="flex items-center justify-between rounded-lg border border-border bg-card px-4 py-3"
                >
                  <div>
                    <p className="font-medium">{l.nome}</p>
                    <p className="text-sm text-muted-foreground">{l.cidade ?? "—"}</p>
                  </div>
                  {!l.ativa && (
                    <span className="rounded-md border border-border px-2 py-0.5 text-xs text-muted-foreground">
                      inativa
                    </span>
                  )}
                </div>
              ))
            )}
          </section>

          <section className="space-y-2">
            <h2 className="text-sm font-semibold">Atalhos</h2>
            <Link
              to="/funcionarios"
              className="inline-block rounded-lg border border-border px-4 py-2 text-sm"
            >
              Equipe
            </Link>
          </section>
        </>
      )}

      {dados.isError && (
        <p className="text-sm text-destructive">
          Não foi possível carregar: {(dados.error as Error).message}
        </p>
      )}
    </main>
  );
}
