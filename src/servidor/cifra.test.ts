// A cifra do código de acesso: abre o que foi fechado, e NADA além disso.
import { beforeAll, describe, expect, it } from "bun:test";
import { cifrar, decifrar } from "./segredos";

beforeAll(() => {
  process.env["STGAME_PIN_PEPPER"] = "chave-de-teste-com-mais-de-16";
});

describe("cifra do código de acesso", () => {
  it("abre o que fechou, no mesmo contexto", async () => {
    const c = await cifrar("ABCD-EF23", "codigo:1:100");
    expect(c).not.toContain("ABCD");
    expect(await decifrar(c, "codigo:1:100")).toBe("ABCD-EF23");
  });

  it("não abre na linha de outra pessoa nem de outra conta", async () => {
    const c = await cifrar("ABCD-EF23", "codigo:1:100");
    expect(await decifrar(c, "codigo:1:101")).toBeNull();
    expect(await decifrar(c, "codigo:2:100")).toBeNull();
  });

  // Troca um caractere do MEIO dos dados (29/09/2026). Antes trocava o
  // último antes do "==" do base64, cujos bits mais baixos são só
  // preenchimento: em 1 de cada 4 vezes a troca não mudava byte nenhum, o
  // código abria e o teste falhava sozinho. No meio, todo bit conta. Repete
  // 200 vezes: se voltar a ser instável, aparece aqui, não de vez em quando.
  it("não abre se alguém mexeu num caractere", async () => {
    for (let i = 0; i < 200; i++) {
      const c = await cifrar("ABCD-EF23", "codigo:1:100");
      const [versao, iv, dados] = c.split(".");
      const meio = Math.floor(dados.length / 2);
      const mexido = `${versao}.${iv}.${dados.slice(0, meio)}${dados[meio] === "A" ? "B" : "A"}${dados.slice(meio + 1)}`;
      expect(await decifrar(mexido, "codigo:1:100")).toBeNull();
    }
  });

  it("não abre com outra chave de servidor", async () => {
    const c = await cifrar("ABCD-EF23", "codigo:1:100");
    process.env["STGAME_PIN_PEPPER"] = "outra-chave-com-mais-de-16-letras";
    expect(await decifrar(c, "codigo:1:100")).toBeNull();
    process.env["STGAME_PIN_PEPPER"] = "chave-de-teste-com-mais-de-16";
  });

  it("dois cifrados do mesmo código são diferentes (não dá para comparar)", async () => {
    expect(await cifrar("ABCD-EF23", "codigo:1:100")).not.toBe(await cifrar("ABCD-EF23", "codigo:1:100"));
  });

  it("vazio ou lixo: não abre, sem quebrar", async () => {
    expect(await decifrar(null, "x")).toBeNull();
    expect(await decifrar("lixo", "x")).toBeNull();
  });
});
