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

  it("não abre se alguém mexeu num caractere", async () => {
    const c = await cifrar("ABCD-EF23", "codigo:1:100");
    const mexido = c.slice(0, -3) + (c.at(-3) === "A" ? "B" : "A") + c.slice(-2);
    expect(await decifrar(mexido, "codigo:1:100")).toBeNull();
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
