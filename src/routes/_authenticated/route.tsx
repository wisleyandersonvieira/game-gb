import { createFileRoute, Outlet, redirect } from "@tanstack/react-router";
import { supabase } from "@/integrations/supabase/client";
import { destinoDoAcesso, meuAcesso } from "@/integrations/supabase/destino";
import { ProvedorLojaAtiva } from "@/lojas/loja-ativa";
import { Layout } from "@/ui/Layout";
import { BARRA_CELULAR, MENU_MASTER } from "@/ui/menu";

export const Route = createFileRoute("/_authenticated")({
  ssr: false,
  beforeLoad: async () => {
    const { data, error } = await supabase.auth.getUser();
    if (error || !data.user) throw redirect({ to: "/auth" });

    // Estas telas são do gestor. Quem entra como loja ou como colaborador é
    // levado para a visão dele — e, mesmo que digitasse o endereço, o banco
    // não entregaria nada (minha_conta() responde vazio para eles).
    const acesso = await meuAcesso();
    if (acesso.tipo !== "master" && acesso.tipo !== "gerente") {
      throw redirect({ to: destinoDoAcesso(acesso) });
    }
    return { user: data.user };
  },
  component: () => (
    <ProvedorLojaAtiva>
      <Layout menu={MENU_MASTER} barra={BARRA_CELULAR}>
        <Outlet />
      </Layout>
    </ProvedorLojaAtiva>
  ),
});
