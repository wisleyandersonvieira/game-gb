// Trava do aviso da "Leitura de comunicado" (29/09/2026): é a única tarefa
// cujos pontos saem sem ninguém aprovar. O aviso ao editar tem de existir e
// dizer, com todas as letras, que cada ciência paga automaticamente.
import { describe, expect, test } from "bun:test";
import { ROTINAS_POR_CODIGO, rotinaDaTarefa } from "./rotinas";

describe("rotinas que usam tarefas", () => {
  test("a Leitura de comunicado avisa que paga sozinha, sem validação", () => {
    const aviso = rotinaDaTarefa("leitura")?.pagaSemValidacao;
    expect(aviso).toBeDefined();
    const texto = aviso!(1000, 50);
    expect(texto).toContain("AUTOMATICAMENTE");
    expect(texto).toContain("SEM VALIDAÇÃO");
    expect(texto).toContain("Cada ciência");
    // O engano de digitar 1000: a conta aparece na tela.
    expect(texto).toContain("20.000");
    // O teto da conta vem escrito no aviso.
    expect(texto).toContain("O máximo permitido nesta conta é 50 pontos");
  });

  test("só a Leitura de comunicado paga sem validação", () => {
    const pagam = Object.entries(ROTINAS_POR_CODIGO)
      .filter(([, r]) => r.pagaSemValidacao)
      .map(([codigo]) => codigo);
    expect(pagam).toEqual(["leitura"]);
  });
});
