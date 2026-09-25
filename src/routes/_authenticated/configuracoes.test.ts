// A tela de Configurações contra a migração que cria os padrões.
//
// Por que existe: em 25/09/2026 a seção "Aceite de tarefas" apareceu VAZIA.
// A conta era anterior às chaves novas, e a tela escondia o campo quando a
// chave não existia. Duas regras que este teste passou a cobrar:
//   1) todo campo da tela tem um valor padrão, para nunca aparecer vazio;
//   2) esse padrão é IGUAL ao da migração, senão a tela mostra um número e o
//      banco guarda outro;
//   3) toda chave da tela é criada por cria_configuracoes_padrao — senão ela
//      nunca chega nas contas.
import { describe, expect, it } from "bun:test";
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { GRUPOS } from "./configuracoes";

/** Os padrões que a migração mais recente de cria_configuracoes_padrao grava. */
function padroesDaMigracao(): Map<string, string> {
  const pasta = join(import.meta.dir, "../../../supabase/migrations");
  const arquivos = readdirSync(pasta).filter((f) => f.endsWith(".sql")).sort();
  let corpo = "";
  for (const f of arquivos) {
    const texto = readFileSync(join(pasta, f), "utf8");
    const i = texto.indexOf("CREATE OR REPLACE FUNCTION public.cria_configuracoes_padrao");
    if (i < 0) continue;
    const fim = texto.indexOf("$fn$;", i);
    corpo = texto.slice(i, fim); // fica com a ÚLTIMA (arquivos em ordem de data)
  }
  expect(corpo).not.toBe("");

  const mapa = new Map<string, string>();
  for (const m of corpo.matchAll(/\(p_contaid,\s*'([A-Z_]+)',\s*'([^']*)'/g)) {
    mapa.set(m[1], m[2]);
  }
  return mapa;
}

const itens = GRUPOS.flatMap((g) => g.itens);
const padroes = padroesDaMigracao();

describe("Configurações: a tela nunca pode ficar vazia", () => {
  it("a migração cria pelo menos os padrões conhecidos", () => {
    expect(padroes.size).toBeGreaterThan(15);
    expect(padroes.get("MINUTOS_RODIZIO_ACEITE")).toBe("10");
  });

  it("todo campo da tela tem um valor padrão", () => {
    const sem = itens.filter((i) => i.padrao === undefined).map((i) => i.chave);
    expect(sem).toEqual([]);
  });

  it("toda chave da tela é criada pela migração em toda conta nova", () => {
    const fora = itens.filter((i) => !padroes.has(i.chave)).map((i) => i.chave);
    expect(fora).toEqual([]);
  });

  it("o padrão da tela é igual ao da migração", () => {
    const diferentes = itens
      .filter((i) => padroes.get(i.chave) !== i.padrao)
      .map((i) => `${i.chave}: tela="${i.padrao}" migração="${padroes.get(i.chave)}"`);
    expect(diferentes).toEqual([]);
  });
});
