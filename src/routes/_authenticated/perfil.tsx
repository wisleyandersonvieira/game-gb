import { createFileRoute } from "@tanstack/react-router";
import { MeuPerfil } from "@/perfil/MeuPerfil";

export const Route = createFileRoute("/_authenticated/perfil")({
  component: MeuPerfil,
});
