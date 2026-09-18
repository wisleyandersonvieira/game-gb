import { createFileRoute, Outlet } from "@tanstack/react-router";
import "@/styles.css";

export const Route = createFileRoute("__root")({
  component: RootLayout,
});

function RootLayout() {
  return <Outlet />;
}
