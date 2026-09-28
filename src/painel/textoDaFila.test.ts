import { describe, expect, it } from "bun:test";
import { separarParaPegar, textoDisponivel, textoLibera } from "./textoDaFila";

const base = { hoje: "2026-09-27", fuso: "America/Sao_Paulo" };

describe("as palavras da fila (tablet e Quadro)", () => {
  it("ainda não liberou: 'libera às 16h23'", () => {
    expect(textoLibera({ ...base, liberaas: "2026-09-27T19:23:00Z", disponiveldesde: null })).toBe("libera às 16h23");
  });
  it("já vale: 'disponível agora' e 'disponível há 12 min'", () => {
    const agora = "2026-09-27T15:00:00Z";
    expect(textoDisponivel({ ...base, liberaas: null, disponiveldesde: agora }, agora)).toBe("disponível agora");
    expect(textoDisponivel({ ...base, liberaas: null, disponiveldesde: "2026-09-27T14:48:00Z" }, agora)).toBe(
      "disponível há 12 min",
    );
  });
  it("a contagem de 'Para pegar' é a do banco: só o que ele disse que está disponível", () => {
    const itens = [
      { situacao: "para_pegar", disponivel: true },
      ...Array.from({ length: 5 }, () => ({ situacao: "para_pegar", disponivel: false })),
      { situacao: "em_andamento", disponivel: false },
    ];
    const r = separarParaPegar(itens);
    expect(r.liberadas.length).toBe(1);
    expect(r.aindaNao.length).toBe(5);
  });
});
