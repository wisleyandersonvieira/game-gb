import { createFileRoute, Outlet, redirect } from "@tanstack/react-router";
import { supabase } from "@/integrations/supabase/client";
import { Layout } from "@/ui/Layout";
import { BARRA_CELULAR_ADMIN, MENU_ADMIN } from "@/ui/menu";

export const Route = createFileRoute("/admin")({
  ssr: false,
  // Esconder a tela nao e protecao: quem manda e a RLS e a checagem no
  // servidor. Isto aqui so evita mostrar uma pagina inutil a quem nao e admin.
  beforeLoad: async () => {
    const { data: sessao, error } = await supabase.auth.getUser();
    if (error || !sessao.user) throw redirect({ to: "/auth" });

    const { data: admin } = await supabase.rpc("eh_admin_geral");
    if (admin !== true) throw redirect({ to: "/sem-acesso" });
  },
  component: () => (
    <Layout menu={MENU_ADMIN} barra={BARRA_CELULAR_ADMIN} comLoja={false} titulo="Administração">
      <Outlet />
    </Layout>
  ),
});
