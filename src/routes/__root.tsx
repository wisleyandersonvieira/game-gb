import {
  Outlet,
  createRootRoute,
  HeadContent,
  Scripts,
} from "@tanstack/react-router";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { useState } from "react";
import { OPERACIONAL } from "@/ui/prazos";
import appCss from "@/styles.css?url";
import { SCRIPT_TEMA } from "@/ui/tema";
import { VersaoNova } from "@/ui/VersaoNova";

/** A rota atual e uma tela de TV? (/tv e /tv/<codigo>) */
function ehTelaDeTv(ctx: { matches?: Array<{ routeId?: string }> }): boolean {
  return (ctx.matches ?? []).some((m) => typeof m.routeId === "string" && m.routeId.indexOf("/tv") === 0);
}

export const Route = createRootRoute({
  // A TV NAO recebe a folha de estilo do aplicativo: ela leva a propria,
  // escrita a mao em CSS antigo. O Tailwind 4 envolve tudo o que gera em
  // @layer, e o navegador da TV que nao conhece @layer descarta a folha
  // INTEIRA — foi o que deixou a TV da loja sem estilo em 25/09/2026.
  head: (ctx) => ({
    meta: [
      { charSet: "utf-8" },
      { name: "viewport", content: "width=device-width, initial-scale=1" },
      { title: "STGame" },
      { name: "description", content: "STGame: gestão de lojas e gamificação da equipe." },
      { name: "application-name", content: "STGame" },
      { name: "apple-mobile-web-app-title", content: "STGame" },
      { name: "theme-color", content: "#1f4fe0" },
      { property: "og:site_name", content: "STGame" },
    ],
    links: [
      ...(ehTelaDeTv(ctx) ? [] : [{ rel: "stylesheet", href: appCss }]),
      { rel: "icon", href: "/favicon.svg", type: "image/svg+xml" },
      { rel: "icon", href: "/favicon.ico", sizes: "any" },
      { rel: "apple-touch-icon", href: "/apple-touch-icon.png" },
      { rel: "manifest", href: "/site.webmanifest" },
    ],
  }),
  component: RootLayout,
});

function RootLayout() {
  // Antes não havia configuração nenhuma, e o padrão é "tudo vence na hora":
  // cada troca de tela e cada volta para a aba refaziam TODAS as consultas.
  // Media de 24/09/2026: resumo_das_lojas, que só existe numa tela, tinha sido
  // chamada 163 vezes. Agora o padrão é conservador (30 s) e cada consulta
  // ajusta o seu prazo (ver src/ui/prazos.ts).
  const [queryClient] = useState(
    () =>
      new QueryClient({
        defaultOptions: {
          queries: {
            staleTime: OPERACIONAL,
            gcTime: 5 * 60_000,
            // Voltar para a aba não refaz tudo. Quem precisa disso (Início,
            // tablet) liga por conta própria.
            refetchOnWindowFocus: false,
            retry: 1,
          },
        },
      }),
  );
  return (
    <html lang="pt-BR" suppressHydrationWarning>
      <head>
        <HeadContent />
        <script dangerouslySetInnerHTML={{ __html: SCRIPT_TEMA }} />
      </head>
      <body>
        <QueryClientProvider client={queryClient}>
          {/* Fica acima de TUDO (gestor, tablet e celular): quem estiver com a
              aba aberta desde antes da publicação precisa saber. */}
          <VersaoNova />
          <Outlet />
        </QueryClientProvider>
        <Scripts />
      </body>
    </html>
  );
}
