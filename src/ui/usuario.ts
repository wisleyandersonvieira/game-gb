// Quem está logado, para EXIBIÇÃO: nome (ou e-mail) e tema.
// user_metadata é editável pelo próprio usuário: só serve para exibir,
// nunca para decidir acesso.
import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";

export type Usuario = { id: string; email: string; nome: string; nomeProprio: string };

function ler(u: { id: string; email?: string; user_metadata?: Record<string, unknown> } | null | undefined): Usuario | null {
  if (!u) return null;
  const nomeProprio = typeof u.user_metadata?.nome === "string" ? (u.user_metadata.nome as string).trim() : "";
  return { id: u.id, email: u.email ?? "", nome: nomeProprio || u.email || "usuário", nomeProprio };
}

export function useUsuario() {
  const [usuario, setUsuario] = useState<Usuario | null>(null);
  useEffect(() => {
    let vivo = true;
    supabase.auth.getUser().then(({ data }) => vivo && setUsuario(ler(data.user)));
    const { data: escuta } = supabase.auth.onAuthStateChange((_e, sessao) => setUsuario(ler(sessao?.user)));
    return () => {
      vivo = false;
      escuta.subscription.unsubscribe();
    };
  }, []);
  return usuario;
}

/** Salva o nome de exibição (cada pessoa só altera o próprio). */
export async function salvarNome(nome: string) {
  const { error } = await supabase.auth.updateUser({ data: { nome: nome.trim().slice(0, 80) } });
  if (error) throw error;
}
