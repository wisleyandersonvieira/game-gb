// A TRAVA do conferidor (29/09/2026): ele nunca pode mandar rodar um
// arquivo mais velho que o mais novo já aplicado. Para isso ele guarda a data
// da migração de cada arquivo (tabela "arquivos"). Este teste confere que
// essa tabela bate com os arquivos de verdade e que nenhuma linha fica de
// fora — senão a regra do "mais novo" compararia datas erradas.
import { describe, expect, it } from "bun:test";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

const SUPA = join(import.meta.dir, "../../supabase");
const conferidor = readFileSync(join(SUPA, "conferir-o-banco.sql"), "utf8");

const bloco = conferidor.slice(conferidor.indexOf("WITH arquivos(arquivo, versao) AS (VALUES"), conferidor.indexOf("esperado(ordem"));
const mapa = new Map([...bloco.matchAll(/\('(aplicar-[^']+\.sql)',\s*'(\d{14})'\)/g)].map((m) => [m[1], m[2]]));
const usados = new Set([...conferidor.slice(conferidor.indexOf("esperado(ordem")).matchAll(/'(aplicar-[^']+\.sql)'/g)].map((m) => m[1]));

describe("conferidor: a data de cada arquivo", () => {
  it("todo arquivo citado numa linha tem data na tabela", () => {
    const sem = [...usados].filter((a) => !mapa.has(a));
    expect(sem).toEqual([]);
  });

  it("a data é a da migração mais nova que o arquivo aplica", () => {
    const erradas: string[] = [];
    for (const [arquivo, versao] of mapa) {
      const caminho = join(SUPA, arquivo);
      expect(existsSync(caminho), arquivo).toBe(true);
      const datas = [...readFileSync(caminho, "utf8").matchAll(/(\d{14})_\w+\.sql/g)].map((m) => m[1]).sort();
      if (datas.at(-1) !== versao) erradas.push(`${arquivo}: tabela ${versao}, arquivo ${datas.at(-1)}`);
    }
    expect(erradas).toEqual([]);
  });

  it("nenhuma linha manda rodar arquivo sem passar pela regra do mais novo", () => {
    expect(conferidor).toContain("t.versao < (SELECT versao FROM aplicado)");
    expect(conferidor).not.toContain('"rode este arquivo"');
  });
});
