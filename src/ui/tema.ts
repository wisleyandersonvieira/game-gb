// Tema claro/escuro. A escolha vale por usuário: fica guardada no login
// (Supabase Auth, user_metadata.tema) e numa cópia no navegador, para a tela
// não piscar ao abrir.
//
// ATENÇÃO: user_metadata é editável pelo próprio usuário. Serve só para
// preferências de exibição (tema, nome). NUNCA use em regra de acesso.
import { supabase } from "@/integrations/supabase/client";

export type Tema = "claro" | "escuro";
const CHAVE = "gamegb.tema";

/** Roda no <head>, antes da tela aparecer. */
export const SCRIPT_TEMA = `try{if(localStorage.getItem("${CHAVE}")==="escuro")document.documentElement.classList.add("dark")}catch(e){}`;

export function temaAtual(): Tema {
  return typeof document !== "undefined" && document.documentElement.classList.contains("dark") ? "escuro" : "claro";
}

export function aplicarTema(tema: Tema) {
  document.documentElement.classList.toggle("dark", tema === "escuro");
  try {
    localStorage.setItem(CHAVE, tema);
  } catch {
    /* sem memória no navegador: vale até recarregar */
  }
}

/** Troca e guarda no login (vale no próximo acesso, em qualquer aparelho). */
export async function escolherTema(tema: Tema) {
  aplicarTema(tema);
  await supabase.auth.updateUser({ data: { tema } });
}

/** Ao entrar: o tema salvo no login manda. */
export async function carregarTemaDoUsuario() {
  const { data } = await supabase.auth.getUser();
  const salvo = data.user?.user_metadata?.tema;
  if (salvo === "claro" || salvo === "escuro") aplicarTema(salvo);
}
