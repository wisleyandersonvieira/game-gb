// Tela de saúde do sistema: diz o que está faltando para o app funcionar,
// sem mostrar o valor de segredo nenhum (só "configurado" ou "faltando").
//
// Existe porque uma publicação sem as atualizações do banco deixou todo mundo
// de fora — inclusive o administrador — com uma mensagem que não dizia o motivo.
import { createFileRoute } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
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
  // O token vai junto para o servidor conferir NO BANCO se quem pediu é o dono
  // da conta. A chave do endereço (?chave=...) é a saída para o dia em que
  // ninguém consegue entrar — foi para isso que esta tela nasceu.
  const d = useQuery({
    queryKey: ["diagnostico"],
    queryFn: async () => {
      const { data: sessao } = await supabase.auth.getSession();
      const chave = new URLSearchParams(window.location.search).get("chave") ?? undefined;
      return diagnostico({ data: { token: sessao.session?.access_token, chave } });
    },
  });

  return (
    <main className="mx-auto flex min-h-screen max-w-xl flex-col gap-4 p-6">
      <Logo altura={36} />
      <h1 className="font-display text-2xl font-semibold">Saúde do sistema</h1>
      <p className="text-sm text-muted-foreground">
        Esta tela não mostra nenhum segredo: só diz o que está configurado e o que falta.
      </p>

      {d.isLoading && <p className="text-sm text-muted-foreground">Conferindo…</p>}
      {d.isError && <p className="text-sm text-destructive">{(d.error as Error).message}</p>}

      {/* Sem login e sem a chave: só o estado geral. */}
      {d.data && !d.data.detalhe && (
        <div
          className={`rounded-lg border p-3 text-sm ${
            d.data.banco === "ok" ? "border-sucesso" : "border-destructive"
          } bg-card`}
        >
          <p className="font-medium">
            {d.data.banco === "ok"
              ? "No ar: o sistema está respondendo e o banco está atualizado."
              : d.data.banco === "desatualizado"
                ? "O banco não recebeu as atualizações desta versão."
                : "O servidor não está conseguindo falar com o banco."}
          </p>
          <p className="mt-1 text-xs text-muted-foreground">
            Entre como dono da conta para ver o detalhe. Se ninguém estiver conseguindo entrar,
            acrescente <span className="font-mono">?chave=…</span> ao endereço, com a chave
            cadastrada em STGAME_SAUDE_CHAVE.
          </p>
        </div>
      )}

      {d.data?.detalhe && (
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
              ajuda="Cadastre SITE_URL nos Secrets do Lovable, com o endereço do site (ex.: https://stgame.com.br), sem barra no fim."
            />
            <Linha
              ok={d.data.contaDeSenha}
              titulo="Conta de senha funciona nesta hospedagem"
              ajuda={
                d.data.erroDaConta
                  ? `A hospedagem recusou a conta de senha: ${d.data.erroDaConta}`
                  : "A conta de senha não funcionou. Sem ela, ninguém entra."
              }
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

          {d.data.temChave && d.data.temPepper && d.data.temSite && d.data.contaDeSenha && d.data.banco === "ok" && (
            <p className="rounded-lg border border-sucesso bg-card p-3 text-sm">
              Tudo certo: o sistema está pronto para uso.
            </p>
          )}
        </>
      )}
    </main>
  );
}
