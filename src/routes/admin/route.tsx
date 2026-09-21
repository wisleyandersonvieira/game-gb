import { createFileRoute, Outlet, redirect } from "@tanstack/react-router";
import { supabase } from "@/integrations/supabase/client";

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
  component: () => <Outlet />,
});
