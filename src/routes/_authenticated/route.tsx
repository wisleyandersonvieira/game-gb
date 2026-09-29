import { createFileRoute, Link, Outlet, redirect, useRouterState } from "@tanstack/react-router";
import { destinoDoAcesso, meuAcesso } from "@/integrations/supabase/destino";
import { ProvedorLojaAtiva } from "@/lojas/loja-ativa";
import { Layout } from "@/ui/Layout";
import { BARRA_CELULAR, MENU_MASTER } from "@/ui/menu";
import { filtrarBarra, filtrarMenu, podeVerTela, useMinhasPermissoes } from "@/ui/permissoes";

export const Route = createFileRoute("/_authenticated")({
  ssr: false,
  beforeLoad: async () => {
    // UMA ida ao servidor, não três. meuAcesso() pergunta ao BANCO quem é você,
    // com o token: se o token não presta, a resposta é "semlogin". Perguntar
    // antes ao serviço de login era repetir a mesma conferência (25/09/2026).
    //
    // Estas telas são do gestor: o master e, desde a parte 4, o gerente. Quem
    // entra como loja ou como colaborador é levado para a visão dele — e, mesmo
    // que digitasse o endereço, o banco não entregaria nada.
    const acesso = await meuAcesso();
    if (acesso.tipo !== "master" && acesso.tipo !== "gerente") {
      throw redirect({ to: destinoDoAcesso(acesso) });
    }
    return {};
  },
  component: AreaDoGestor,
});

function AreaDoGestor() {
  const permissoes = useMinhasPermissoes();
  const caminho = useRouterState({ select: (s) => s.location.pathname });
  const menu = filtrarMenu(MENU_MASTER, permissoes.data);
  const barra = filtrarBarra(BARRA_CELULAR, permissoes.data);
  return (
    <ProvedorLojaAtiva>
      <Layout menu={menu} barra={barra}>
        {permissoes.isLoading ? (
          <p className="p-6 text-muted-foreground">Carregando...</p>
        ) : podeVerTela(permissoes.data, caminho) ? (
          <Outlet />
        ) : (
          <SemPermissao primeira={menu[0]?.itens[0]?.to} />
        )}
      </Layout>
    </ProvedorLojaAtiva>
  );
}

/** Quem digita o endereço de uma tela que o cargo não deixa ver: mensagem clara, nunca tela branca. */
function SemPermissao({ primeira }: { primeira?: string }) {
  return (
    <div className="mx-auto max-w-lg p-6">
      <div className="rounded-xl border border-border bg-card p-6">
        <h1 className="text-lg font-semibold">Esta tela não está liberada para você</h1>
        <p className="mt-2 text-sm text-muted-foreground">
          O seu cargo não dá acesso a esta parte do sistema. Se precisar, peça ao responsável pela conta para liberar.
        </p>
        {primeira && (
          <Link to={primeira} className="mt-4 inline-block text-sm font-medium text-primary underline">
            Ir para a primeira tela liberada
          </Link>
        )}
      </div>
    </div>
  );
}
