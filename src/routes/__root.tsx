import { Outlet, createRootRoute } from "@tanstack/react-router";
import "@/styles.css";

export const Route = createRootRoute({
  component: RootLayout,
});

function RootLayout() {
  return <Outlet />;
}
