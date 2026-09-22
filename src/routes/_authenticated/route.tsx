import { createFileRoute, Outlet, redirect } from "@tanstack/react-router";
import { supabase } from "@/integrations/supabase/client";
import { ProvedorLojaAtiva } from "@/lojas/loja-ativa";
import { Layout } from "@/ui/Layout";
import { BARRA_CELULAR, MENU_MASTER } from "@/ui/menu";

export const Route = createFileRoute("/_authenticated")({
  ssr: false,
  beforeLoad: async () => {
    const { data, error } = await supabase.auth.getUser();
    if (error || !data.user) throw redirect({ to: "/auth" });
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
