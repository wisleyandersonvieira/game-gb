import { supabase } from "./client";

export type Destino = "/admin" | "/inicio" | "/primeiro-acesso" | "/eu" | "/tablet" | "/sem-acesso" | "/auth";

export type Acesso = {
  /**
   * "semlogin" = não há token válido (ir para a entrada).
   * "nenhum"   = o token vale, mas a pessoa não tem vínculo (sem acesso).
   */
  tipo: "admin" | "master" | "gerente" | "loja" | "colaborador" | "desligado" | "nenhum" | "semlogin";
  conta?: string;
  loja?: string | null;
  nome?: string;
  somenteleitura?: boolean;
  semsenha?: boolean;
  sempin?: boolean;
  politicapendente?: boolean;
};

/**
 * Quem esta logado, segundo o BANCO (meu_acesso roda no Postgres com o token).
 * A tela so obedece: esconder botao nao e protecao.
 */
/**
 * Guardado por poucos segundos de propósito: trocar de tela três vezes
 * seguidas não precisa perguntar três vezes quem você é. Some a cada evento de
 * login/logout, e é curto o bastante para "desligado na hora" continuar
 * valendo — e, de todo jeito, quem nega os DADOS é a RLS, não esta resposta.
 */
let lembrado: { em: number; acesso: Acesso } | null = null;
const VALIDADE = 15_000;

export function esquecerAcesso() {
  lembrado = null;
}

if (typeof window !== "undefined") {
  supabase.auth.onAuthStateChange(() => esquecerAcesso());
}

export async function meuAcesso(): Promise<Acesso> {
  if (lembrado && Date.now() - lembrado.em < VALIDADE) return lembrado.acesso;

  // getSession() é LOCAL (não vai na rede) e renova o token sozinho quando
  // vence. Serve só para não perguntar ao banco quando nem token existe.
  const { data: sessao } = await supabase.auth.getSession();
  if (!sessao.session) return { tipo: "semlogin" };

  // Esta é a conferência de verdade: roda no banco, com o token. Se o token
  // não presta, auth.uid() é vazio e a resposta é "semlogin".
  const { data, error } = await supabase.rpc("meu_acesso");
  if (error || !data) return { tipo: "semlogin" };

  const acesso = data as Acesso;
  lembrado = { em: Date.now(), acesso };
  return acesso;
}

/** Para onde mandar quem acabou de entrar. */
export function destinoDoAcesso(a: Acesso): Destino {
  if (a.tipo === "semlogin") return "/auth";
  if (a.tipo === "admin") return "/admin";
  if (a.tipo === "master" || a.tipo === "gerente") return "/inicio";
  if (a.tipo === "colaborador") {
    // Primeiro acesso: trocar a senha, escolher o PIN e dar ciencia na politica.
    return a.semsenha || a.sempin || a.politicapendente ? "/primeiro-acesso" : "/eu";
  }
  if (a.tipo === "loja") return "/tablet";
  return "/sem-acesso";
}

export async function destinoDoUsuario(): Promise<Destino> {
  return destinoDoAcesso(await meuAcesso());
}
