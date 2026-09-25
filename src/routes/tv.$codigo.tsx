// Modo TV pelo link comprido: /tv/<codigo>.
//
// Continua valendo para quem ja usa. A TV nova entra por /tv, com codigo curto.
import { createFileRoute } from "@tanstack/react-router";
import { TelaDaTv } from "@/painel/TelaDaTv";

export const Route = createFileRoute("/tv/$codigo")({
  ssr: false,
  head: () => ({
    meta: [
      { title: "Painel da loja — STGame" },
      // A TV não deve aparecer em buscadores nem ser indexada.
      { name: "robots", content: "noindex, nofollow" },
    ],
  }),
  component: PorLinkComprido,
});

function PorLinkComprido() {
  const { codigo } = Route.useParams();
  return <TelaDaTv codigo={codigo} />;
}
