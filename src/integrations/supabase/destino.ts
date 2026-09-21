import { supabase } from "./client";

export type Destino = "/admin" | "/gestao" | "/sem-acesso" | "/auth";

/**
 * Para onde mandar quem acabou de entrar.
 *
 * Quem decide e o banco, nao a tela: `eh_admin_geral()` e `minha_conta()`
 * rodam no Postgres com o token do usuario. A tela so obedece ao resultado.
 */
export async function destinoDoUsuario(): Promise<Destino> {
  const { data: sessao } = await supabase.auth.getUser();
  if (!sessao.user) return "/auth";

  const { data: admin } = await supabase.rpc("eh_admin_geral");
  if (admin === true) return "/admin";

  const { data: conta } = await supabase.rpc("minha_conta");
  if (conta !== null && conta !== undefined) return "/gestao";

  return "/sem-acesso";
}
