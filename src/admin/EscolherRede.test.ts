import { describe, expect, it } from "bun:test";
import { filtrarRedes } from "./EscolherRede";

const redes = [
  { redeid: 1, nome: "Zeca Sorvetes" },
  { redeid: 2, nome: "Açaí Brasil" },
  { redeid: 3, nome: "Gela Boca" },
];

describe("lista de redes", () => {
  it("em ordem alfabética (Açaí antes de Gela, ignorando o acento)", () => {
    expect(filtrarRedes(redes, "").map((r) => r.nome)).toEqual(["Açaí Brasil", "Gela Boca", "Zeca Sorvetes"]);
  });
  it("filtra por parte do nome, sem ligar para maiúscula nem acento", () => {
    expect(filtrarRedes(redes, "acai").map((r) => r.redeid)).toEqual([2]);
    expect(filtrarRedes(redes, "BOCA").map((r) => r.redeid)).toEqual([3]);
    expect(filtrarRedes(redes, "sorv").map((r) => r.redeid)).toEqual([1]);
  });
});
