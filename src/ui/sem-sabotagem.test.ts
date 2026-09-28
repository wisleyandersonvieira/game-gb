// Nenhuma sabotagem esquecida (29/09/2026). As sabotagens dos testes entram
// como uma migração extra e desligam checagens do teste de isolamento de
// propósito; o script as desfaz no fim. Em 29/09/2026 uma rodada interrompida
// deixou as duas coisas para trás, fora do commit por sorte. Este teste
// reprova se sobrar qualquer uma delas.
import { describe, expect, it } from "bun:test";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

const RAIZ = join(import.meta.dir, "../..");

export function sabotagensEsquecidas(migracoes: string[], isolamento: string): string[] {
  const achadas = migracoes.filter((m) => /sabotagem/i.test(m)).map((m) => `migração ${m}`);
  const desligadas = isolamento.match(/exigir\(\s*true\s+OR\b/gi) ?? [];
  if (desligadas.length > 0) achadas.push(`${desligadas.length} checagem(ns) desligada(s) com "true OR"`);
  return achadas;
}

describe("nenhuma sabotagem esquecida", () => {
  it("nem migração de sabotagem, nem checagem desligada no teste de isolamento", () => {
    const migracoes = readdirSync(join(RAIZ, "supabase/migrations"));
    const isolamento = readFileSync(join(RAIZ, "supabase/tests/isolamento.sql"), "utf8");
    expect(sabotagensEsquecidas(migracoes, isolamento)).toEqual([]);
  });

  it("reconhece as duas formas (prova de que olha o lugar certo)", () => {
    expect(sabotagensEsquecidas(["20260929299999_sabotagem.sql"], "")).toHaveLength(1);
    expect(sabotagensEsquecidas([], "PERFORM public.exigir(true OR sobra IS NULL, 'x');")).toHaveLength(1);
    expect(sabotagensEsquecidas(["20260929252000_feedbacks.sql"], "PERFORM public.exigir(sobra IS NULL, 'x');")).toHaveLength(0);
  });
});
