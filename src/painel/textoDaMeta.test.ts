import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { textoDiasSemLancamento } from "./textoDaMeta";

describe("dias sem lançamento na meta do mês", () => {
  it("zero dias: não escreve nada", () => {
    expect(textoDiasSemLancamento(0)).toBeNull();
    expect(textoDiasSemLancamento(undefined)).toBeNull();
  });
  it("um e vários", () => {
    expect(textoDiasSemLancamento(1)).toBe("1 dia sem lançamento");
    expect(textoDiasSemLancamento(3)).toBe("3 dias sem lançamento");
  });
  it("a TV e o Início usam a mesma frase", () => {
    for (const f of ["painel/TelaDaTv.tsx", "routes/_authenticated/inicio.tsx"]) {
      expect(readFileSync(join(import.meta.dir, "..", f), "utf8")).toContain("textoDiasSemLancamento(");
    }
  });
});
