import { createFileRoute } from "@tanstack/react-router";
import { Outlet } from "@tanstack/react-router";
import { startInstance } from "@/start";

export const Route = createFileRoute("/__root")({
  component: RootLayout,
});

function RootLayout() {
  return (
    <html lang="pt-BR">
      <head>
        <meta charSet="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0" />
      </head>
      <body>
        <Outlet />
      </body>
    </html>
  );
}

// start instance must exist for TanStack Start
void startInstance;
