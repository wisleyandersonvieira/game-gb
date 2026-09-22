// Tela de saúde do sistema: diz o que está faltando para o app funcionar,
// sem mostrar o valor de segredo nenhum (só "configurado" ou "faltando").
//
// Existe porque uma publicação sem as atualizações do banco deixou todo mundo
// de fora — inclusive o administrador — com uma mensagem que não dizia o motivo.
import { createFileRoute } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { diagnostico } from "@/servidor/acesso";
import { Logo } from "@/ui/Logo";

export const Route = createFileRoute("/saude")({
  ssr: false,
  head: () => ({ meta: [{ title: "Saúde do sistema — STGame" }, { name: "robots", content: "noindex, nofollow" }] }),
  component: Saude,
});

function Linha({ ok, titulo, ajuda }: { ok: boolean; titulo: string; ajuda: string }) {
  return (
    <li className="flex gap-3 rounded-lg border border-border bg-card p-3">
      <span className={ok ? "text-sucesso" : "text-destructive"}>{ok ? "✓" : "✗"}</span>
      <div>
        <p className="font-medium">{titulo}</p>
        {!ok && <p className="text-xs text-muted-foreground">{ajuda}</p>}
      </div>
    </li>
  );
}

function Saude() {
  const d = useQuery({ queryKey: ["diagnostico"], queryFn: () => diagnostico() });

  return (
    <main className="mx-auto flex min-h-screen max-w-xl flex-col gap-4 p-6">
      <Logo altura={36} />
      <h1 className="font-display text-2xl font-semibold">Saúde do sistema</h1>
      <p className="text-sm text-muted-foreground">
        Esta tela não mostra nenhum segredo: só diz o que está configurado e o que falta.
      </p>

      {d.isLoading && <p className="text-sm text-muted-foreground">Conferindo…</p>}
      {d.isError && <p className="text-sm text-destructive">{(d.error as Error).message}</p>}

      {d.data && (
        <>
          <ul className="space-y-2">
            <Linha
              ok={d.data.temChave}
              titulo="Chave de servidor do Supabase"
              ajuda="Cadastre STGAME_SERVICE_ROLE_KEY nos Secrets do Lovable."
            />
            <Linha
              ok={d.data.temPepper}
              titulo="Chave de segredos do app"
              ajuda="Cadastre STGAME_PIN_PEPPER nos Secrets do Lovable (pelo menos 16 caracteres)."
            />
            <Linha
              ok={d.data.temSite}
              titulo="Endereço do site"
              ajuda="Cadastre SITE_URL nos Secrets do Lovable (ex.: https://stgame.lovable.app)."
            />
            <Linha
              ok={d.data.banco === "ok"}
              titulo="Banco de dados atualizado"
              ajuda={
                d.data.banco === "desatualizado"
                  ? "O banco não recebeu as atualizações desta versão. Aplique as migrações (supabase db push)."
                  : "O servidor não conseguiu falar com o banco. Confira a chave de servidor."
              }
            />
          </ul>

          {d.data.faltando.length > 0 && (
            <div className="rounded-lg border border-destructive bg-card p-3">
              <p className="text-sm font-medium">Faltando no banco:</p>
              <p className="mt-1 break-words font-mono text-xs text-muted-foreground">
                {d.data.faltando.join(", ")}
              </p>
            </div>
          )}

          {d.data.temChave && d.data.temPepper && d.data.temSite && d.data.banco === "ok" && (
            <p className="rounded-lg border border-sucesso bg-card p-3 text-sm">
              Tudo certo: o sistema está pronto para uso.
            </p>
          )}
        </>
      )}
    </main>
  );
}
