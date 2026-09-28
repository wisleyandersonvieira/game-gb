// A TRAVA do "disponível agora" nas telas (29/09/2026).
//
// "Está disponível?" (para pegar e já liberada) é decidido UMA vez, no banco
// (fila_de_hoje.disponivel). A TV, o tablet e o Quadro só leem a resposta.
// Foi a quarta vez que a mesma pergunta tinha resposta em mais de um lugar
// ("que dia é hoje", "para pegar", o "hoje" do pódio e esta). Este teste
// reprova se alguma tela voltar a fazer a conta por conta própria; o teste de
// isolamento (seção 82) compara as três listas item por item no banco.
import { describe, expect, it } from "bun:test";
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join, relative } from "node:path";

const RAIZ = join(import.meta.dir, "../..");
const SRC = join(RAIZ, "src");

function arquivos(pasta: string, achados: string[] = []): string[] {
  for (const nome of readdirSync(pasta)) {
    const caminho = join(pasta, nome);
    if (statSync(caminho).isDirectory()) arquivos(caminho, achados);
    else if (/\.tsx?$/.test(nome) && !/\.test\.tsx?$/.test(nome)) achados.push(caminho);
  }
  return achados;
}

/** Jeitos de uma tela decidir sozinha o que está disponível. */
const DECIDE_SOZINHA = [
  /"para_pegar"\s*&&\s*!?\s*\(?\s*[\w.]*liberada\b/, // situacao === "para_pegar" && i.liberada
  /filter\(\s*\(?\s*\w+\s*\)?\s*=>\s*!?\s*\w+\.liberada\b/, // .filter((i) => i.liberada)
];

describe("catraca: nenhuma tela decide sozinha o que está disponível", () => {
  it("a TV, o tablet e o Quadro leem `disponivel` do banco", () => {
    const quem = arquivos(SRC)
      .filter((f) => !f.includes("/integrations/supabase/"))
      .filter((f) => DECIDE_SOZINHA.some((r) => r.test(readFileSync(f, "utf8"))))
      .map((f) => relative(RAIZ, f));
    expect(quem, `decidem sozinhas: ${quem.join(", ")}`).toEqual([]);
  });

  it("a TV mostra o 'Para fazer' como veio do banco, sem filtrar", () => {
    const tv = readFileSync(join(SRC, "painel/TelaDaTv.tsx"), "utf8");
    expect(/parafazer\s*\.filter\(/.test(tv)).toBe(false);
  });
});
