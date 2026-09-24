// Regras da senha que o gestor DIGITA para o tablet (Etapa 1.12, parte B1).
// Senha digitada é adivinhável — por isso ela tem um mínimo e uma lista de
// recusas, e por isso o login daquela loja passa a ter atraso progressivo.
import { describe, expect, it } from "bun:test";
import { conferirSenhaDoTablet } from "./segredos";

const daLoja = ["Gela Boca Centro", "gelaboca1", "Gela Boca"];

describe("senha do tablet digitada pelo gestor", () => {
  it("aceita uma senha razoável", () => {
    expect(conferirSenhaDoTablet("balcao-roxo-47!", daLoja)).toBe("balcao-roxo-47!");
  });

  it("tira os espaços das pontas", () => {
    expect(conferirSenhaDoTablet("  balcao-roxo-47!  ", daLoja)).toBe("balcao-roxo-47!");
  });

  it("recusa menos de 10 caracteres", () => {
    expect(() => conferirSenhaDoTablet("curta1234", daLoja)).toThrow(/10 caracteres/);
  });

  it("recusa repetição do mesmo caractere", () => {
    expect(() => conferirSenhaDoTablet("0000000000", daLoja)).toThrow();
    expect(() => conferirSenhaDoTablet("aaaaaaaaaaaa", daLoja)).toThrow();
  });

  it("recusa sequências", () => {
    expect(() => conferirSenhaDoTablet("xk12345mpq!", daLoja)).toThrow(/sequências/);
    expect(() => conferirSenhaDoTablet("zzabcdezz99", daLoja)).toThrow(/sequências/);
    expect(() => conferirSenhaDoTablet("pq98765wxy!", daLoja)).toThrow(/sequências/);
  });

  it("recusa palavras óbvias", () => {
    for (const ruim of ["minhasenha22", "PasswordXyz9", "tabletdobar1", "lojacentro77", "stgame2026!"]) {
      expect(() => conferirSenhaDoTablet(ruim, daLoja)).toThrow(/fácil demais/);
    }
  });

  it("recusa o nome da loja, o nome e o código da empresa", () => {
    expect(() => conferirSenhaDoTablet("xx gela boca centro", daLoja)).toThrow(/nome da loja/);
    expect(() => conferirSenhaDoTablet("zzgelaboca1zz", daLoja)).toThrow(/nome da loja/);
    // sem olhar maiúscula ou minúscula
    expect(() => conferirSenhaDoTablet("ZZGELABOCAZZ", daLoja)).toThrow(/nome da loja/);
  });

  it("recusa senha longa demais", () => {
    expect(() => conferirSenhaDoTablet("k".repeat(40) + "j".repeat(40), daLoja)).toThrow(/longa demais/);
  });
});
