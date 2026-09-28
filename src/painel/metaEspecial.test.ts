import { describe, expect, it } from "bun:test";
import { AINDA_NAO_LANCADA, textosDaMetaEspecial } from "./TelaDaTv";

const base = { nome: "Dia das Crianças", pontos: 50 };

describe("a tela 'Meta especial' da TV", () => {
  it("ninguém lançou a venda: diz isso, sem barra e sem percentual", () => {
    const t = textosDaMetaEspecial({ ...base, lancado: false });
    expect(t.estado).toBe("naolancada");
    expect(t.progresso).toBe(AINDA_NAO_LANCADA);
    expect(t.progresso).not.toMatch(/%|R\$/);
    expect(t.pontos).toBe("50 pontos para cada um da equipe");
  });

  it("lançada: quanto foi e quanto falta, em percentual quando o R$ não veio", () => {
    const t = textosDaMetaEspecial({ ...base, lancado: true, percentual: 62.4, bateu: false });
    expect(t.estado).toBe("andamento");
    expect(t.progresso).toBe("62% · faltam 38%");
    expect(t.progresso).not.toContain("R$");
  });

  it("com 'mostrar valores' ligado, o banco manda o R$ e a tela escreve em reais", () => {
    const t = textosDaMetaEspecial({
      ...base, lancado: true, percentual: 61.5, bateu: false, vendido: 12300, meta: 20000, falta: 7700,
    });
    expect(t.progresso?.replace(/\s/g, " ")).toBe("R$ 12.300 de R$ 20.000 · faltam R$ 7.700");
  });

  it("batida: a comemoração com os pontos de CADA UM", () => {
    const t = textosDaMetaEspecial({ ...base, lancado: true, percentual: 104, bateu: true });
    expect(t.estado).toBe("batida");
    expect(t.pontos).toBe("a equipe bateu! 50 pontos para cada um");
    expect(t.progresso).toBeNull();
  });

  it("meta sem pontos não inventa prêmio", () => {
    expect(textosDaMetaEspecial({ ...base, pontos: 0, lancado: false }).pontos).toBeNull();
    expect(textosDaMetaEspecial({ ...base, pontos: 0, lancado: true, bateu: true }).pontos).toBe("a equipe bateu!");
  });
});
