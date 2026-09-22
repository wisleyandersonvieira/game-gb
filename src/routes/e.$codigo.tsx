// Entrada da empresa pelo link ou QR (stgame.app/e/<codigo>).
// Só guarda o código no aparelho e leva para a tela de entrar: quem lê o QR
// uma vez não precisa digitar o código nunca mais.
import { createFileRoute, redirect } from "@tanstack/react-router";

export const Route = createFileRoute("/e/$codigo")({
  ssr: false,
  beforeLoad: ({ params }) => {
    try {
      localStorage.setItem("stgame.empresa", params.codigo.trim().toLowerCase());
    } catch {
      // Navegador sem armazenamento: a tela de entrar pede o código.
    }
    throw redirect({ to: "/auth" });
  },
});
