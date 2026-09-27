import { describe, expect, it } from "bun:test";
import { faltaParaConcluir } from "./senhaEPin";

const ok = { senha: "Casa!Azul9", senha2: "Casa!Azul9", pin: "482915", pin2: "482915" };

describe("botão Concluir do primeiro acesso", () => {
  it("acende com senha e PIN válidos e confirmados", () => {
    expect(faltaParaConcluir(ok)).toBeNull();
  });
  it("fica apagado com senha curta, confirmação diferente ou PIN incompleto", () => {
    expect(faltaParaConcluir({ ...ok, senha: "curta", senha2: "curta" })).toContain("8 caracteres");
    expect(faltaParaConcluir({ ...ok, senha2: "Outra!Azul9" })).toContain("senhas");
    expect(faltaParaConcluir({ ...ok, pin: "4829", pin2: "4829" })).toContain("6 números");
    expect(faltaParaConcluir({ ...ok, pin: "48291a", pin2: "48291a" })).toContain("6 números");
    expect(faltaParaConcluir({ ...ok, pin2: "482916" })).toContain("PINs");
  });
  it("quem só precisa do PIN não é cobrado pela senha", () => {
    expect(faltaParaConcluir({ senha: "", senha2: "", pin: "482915", pin2: "482915" }, { senha: false, pin: true })).toBeNull();
  });
});
