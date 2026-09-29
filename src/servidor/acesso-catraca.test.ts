// Trava (29/09/2026, decisões 2 e 4 do Wisley): quem pode mexer no acesso de
// uma pessoa é decidido pelo BANCO, antes de o servidor usar a chave de admin.
//
// - Criar acesso, gerar código, redefinir, emitir folhas e desativar:
//   exigirNaPessoa (o master, ou o gerente com TODAS as lojas da pessoa, nunca
//   o próprio), com o código certo do catálogo.
// - Trocar CPF e tudo do tablet da loja: só o master (exigirMaster).
// A conferência tem de vir ANTES da primeira chamada com a chave de admin.
import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const fonte = readFileSync(join(import.meta.dir, "acesso.ts"), "utf8");

/** O corpo de cada ação do servidor, até a próxima declaração de topo. */
function acao(nome: string): string {
  const i = fonte.indexOf(`export const ${nome} = createServerFn`);
  if (i < 0) throw new Error(`ação ${nome} não existe`);
  const resto = fonte.slice(i + 1);
  const fim = resto.search(/\n(export |async function |function |\/\*\*|\/\/ -{10})/);
  return resto.slice(0, fim < 0 ? undefined : fim);
}

const NA_PESSOA: Record<string, string[]> = {
  criarAcessoColaborador: ["equipe.criar_acesso"],
  gerarCodigoDeAcesso: ["equipe.criar_acesso"],
  redefinirAcessoColaborador: ["equipe.redefinir_acesso"],
  emitirFolhasDeAcesso: ["equipe.redefinir_acesso", "equipe.criar_acesso"],
  desativarColaborador: ["equipe.desativar"],
};
const SO_MASTER = ["trocarCpfDoColaborador", "criarAcessoLoja", "redefinirSenhaLoja", "definirSenhaDoTablet", "fichaDosTablets"];

describe("acesso da pessoa: o banco decide antes da chave de admin", () => {
  it("criar, redefinir, emitir e desativar: exigirNaPessoa com o código certo, antes do admin", () => {
    for (const [nome, codigos] of Object.entries(NA_PESSOA)) {
      const corpo = acao(nome);
      const conferencia = corpo.indexOf("exigirNaPessoa(");
      const admin = corpo.search(/supabaseAdmin|redefinirInterno\(|criarAcessoInterno\(|gerarCodigo\(/);
      expect({ nome, confere: conferencia >= 0 }).toEqual({ nome, confere: true });
      expect({ nome, antes: admin < 0 || conferencia < admin }).toEqual({ nome, antes: true });
      for (const c of codigos) expect({ nome, c, usa: corpo.includes(`"${c}"`) }).toEqual({ nome, c, usa: true });
      expect({ nome, master: corpo.includes("exigirMaster(") }).toEqual({ nome, master: false });
    }
  });

  it("CPF e tablet da loja: só o master, antes do admin", () => {
    for (const nome of SO_MASTER) {
      const corpo = acao(nome);
      const conferencia = corpo.indexOf("exigirMaster(");
      const admin = corpo.indexOf("supabaseAdmin");
      expect({ nome, confere: conferencia >= 0 && (admin < 0 || conferencia < admin) }).toEqual({ nome, confere: true });
    }
  });

  it("a conta vem da resposta do banco, nunca do navegador", () => {
    const helper = fonte.slice(fonte.indexOf("async function exigirNaPessoa"), fonte.indexOf("async function contaDoMaster"));
    expect(helper).toContain('rpc("posso_na_pessoa"');
    expect(helper).toContain("r?.pode !== true");
    for (const nome of Object.keys(NA_PESSOA)) expect(acao(nome)).not.toMatch(/data\.contaid/);
  });
});
