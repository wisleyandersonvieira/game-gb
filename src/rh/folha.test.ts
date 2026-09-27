// O nome do arquivo da folha de acesso.
import { describe, expect, it } from "bun:test";
import { nomeDaFolha } from "./pdf";

describe("nome do arquivo da folha de acesso", () => {
  it("uma pessoa: acesso-<primeiro nome>-<data>", () => {
    expect(nomeDaFolha([{ nome: "Maria Aparecida dos Santos", lojas: ["Centro"] }], "2026-09-27")).toBe(
      "acesso-maria-2026-09-27.pdf",
    );
  });
  it("acento e cedilha saem do nome do arquivo", () => {
    expect(nomeDaFolha([{ nome: "João", lojas: [] }], "2026-09-27")).toBe("acesso-joao-2026-09-27.pdf");
  });
  it("em lote, da mesma loja: acessos-<loja>-<data>", () => {
    const f = [{ nome: "A", lojas: ["Gela Boca Centro"] }, { nome: "B", lojas: ["Gela Boca Centro"] }];
    expect(nomeDaFolha(f, "2026-09-27")).toBe("acessos-gela-boca-centro-2026-09-27.pdf");
  });
  it("em lote, de lojas diferentes: acessos-equipe-<data>", () => {
    const f = [{ nome: "A", lojas: ["Centro"] }, { nome: "B", lojas: ["Shopping"] }];
    expect(nomeDaFolha(f, "2026-09-27")).toBe("acessos-equipe-2026-09-27.pdf");
  });
});
