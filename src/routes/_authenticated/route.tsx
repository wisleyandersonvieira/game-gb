import { createFileRoute, Outlet, redirect } from "@tanstack/react-router";
import { destinoDoAcesso, meuAcesso } from "@/integrations/supabase/destino";
import { ProvedorLojaAtiva } from "@/lojas/loja-ativa";
import { Layout } from "@/ui/Layout";
import { BARRA_CELULAR, MENU_MASTER } from "@/ui/menu";

export const Route = createFileRoute("/_authenticated")({
  ssr: false,
  beforeLoad: async () => {
    // UMA ida ao servidor, não três. meuAcesso() pergunta ao BANCO quem é você,
    // com o token: se o token não presta, a resposta é "semlogin". Perguntar
    // antes ao serviço de login era repetir a mesma conferência (25/09/2026).
    //
    // Estas telas são do gestor. Quem entra como loja ou como colaborador é
    // levado para a visão dele — e, mesmo que digitasse o endereço, o banco
    // não entregaria nada (minha_conta() responde vazio para eles).
    const acesso = await meuAcesso();
    if (acesso.tipo !== "master" && acesso.tipo !== "gerente") {
      throw redirect({ to: destinoDoAcesso(acesso) });
    }
    return {};
  },
  component: () => (
    <ProvedorLojaAtiva>
      <Layout menu={MENU_MASTER} barra={BARRA_CELULAR}>
        <Outlet />
      </Layout>
    </ProvedorLojaAtiva>
  ),
});
