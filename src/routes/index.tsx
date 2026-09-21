import { createFileRoute, redirect } from "@tanstack/react-router";
import { destinoDoUsuario } from "@/integrations/supabase/destino";

export const Route = createFileRoute("/")({
  ssr: false,
  // A porta de entrada apenas encaminha: o banco decide quem e o que.
  beforeLoad: async () => {
    throw redirect({ to: await destinoDoUsuario() });
  },
  component: () => null,
});
