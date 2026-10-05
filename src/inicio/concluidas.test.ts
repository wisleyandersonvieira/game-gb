import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { linhasVendaOntem } from "./avisos-do-inicio";
import { textoSemLancamento } from "./tipos";

const ler = (f: string) => readFileSync(join(import.meta.dir, "..", f), "utf8");

describe("venda de ontem não lançada (aviso do Início)", () => {
  it("uma linha por loja, até três", () => {
    expect(linhasVendaOntem([{ loja: "Loja Centro" }])).toEqual(["A venda de ontem não foi lançada na Loja Centro."]);
    expect(linhasVendaOntem([{ loja: "A" }, { loja: "B" }, { loja: "C" }])).toHaveLength(3);
  });
  it("acima de três, uma linha resumida", () => {
    const l = linhasVendaOntem([{ loja: "A" }, { loja: "B" }, { loja: "C" }, { loja: "D" }, { loja: "E" }]);
    expect(l).toEqual(["A venda de ontem não foi lançada em 5 lojas: A, B, C e mais 2."]);
  });
  it("sem loja atrasada, nenhum aviso", () => {
    expect(linhasVendaOntem([])).toEqual([]);
  });
});

describe("meta do dia no Início: nunca um número parcial", () => {
  const m = { meta: 1000, vendido: 0, percentual: 0, lojas: 2 };
  it("nenhuma loja lançou: diz que não foi lançada, sem 0%", () => {
    expect(textoSemLancamento({ ...m, lancadas: 0 })).toBe("venda de hoje ainda não lançada");
  });
  it("só parte das lojas lançou: diz quantas, sem percentual", () => {
    expect(textoSemLancamento({ ...m, lancadas: 1 })).toBe("venda de hoje lançada em 1 de 2 lojas");
  });
  it("todas lançaram: mostra o número", () => {
    expect(textoSemLancamento({ ...m, lancadas: 2 })).toBeNull();
  });
});

describe("a fração de concluídas não é calculada nas telas", () => {
  it("TV, painel da loja e Início leem o percentual pronto do banco", () => {
    for (const f of ["painel/TelaDaTv.tsx", "painel/PainelDaLoja.tsx", "routes/_authenticated/inicio.tsx"]) {
      expect(ler(f), f).not.toMatch(/aprovadas\s*\/\s*\w*\.?total|feitas\s*\*\s*100|\.feitas\b/);
    }
  });
});
