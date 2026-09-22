import { supabase } from "./client";

export type Destino = "/admin" | "/inicio" | "/primeiro-acesso" | "/meu-acesso" | "/sem-acesso" | "/auth";

export type Acesso = {
  tipo: "admin" | "master" | "gerente" | "loja" | "colaborador" | "desligado" | "nenhum";
  conta?: string;
  loja?: string | null;
  nome?: string;
  somenteleitura?: boolean;
  senhaprovisoria?: boolean;
  pinprovisorio?: boolean;
  politicapendente?: boolean;
};

/**
 * Quem esta logado, segundo o BANCO (meu_acesso roda no Postgres com o token).
 * A tela so obedece: esconder botao nao e protecao.
 */
export async function meuAcesso(): Promise<Acesso> {
  const { data: sessao } = await supabase.auth.getUser();
  if (!sessao.user) return { tipo: "nenhum" };
  const { data, error } = await supabase.rpc("meu_acesso");
  if (error || !data) return { tipo: "nenhum" };
  return data as Acesso;
}

/** Para onde mandar quem acabou de entrar. */
export function destinoDoAcesso(a: Acesso): Destino {
  if (a.tipo === "admin") return "/admin";
  if (a.tipo === "master" || a.tipo === "gerente") return "/inicio";
  if (a.tipo === "colaborador") {
    // Primeiro acesso: trocar a senha, escolher o PIN e dar ciencia na politica.
    return a.senhaprovisoria || a.pinprovisorio || a.politicapendente ? "/primeiro-acesso" : "/meu-acesso";
  }
  if (a.tipo === "loja") return "/meu-acesso";
  return "/sem-acesso";
}

export async function destinoDoUsuario(): Promise<Destino> {
  const { data: sessao } = await supabase.auth.getUser();
  if (!sessao.user) return "/auth";
  return destinoDoAcesso(await meuAcesso());
}
