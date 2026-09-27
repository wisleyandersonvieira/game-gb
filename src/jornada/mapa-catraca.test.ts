// A TRAVA do intervalo do mapa (27/09/2026).
//
// O "Intervalo (planejamento, não afeta o sistema)" serve só para enxergar e
// imprimir a escala: não cala o bot, não mexe em tarefa, liberação, nota nem
// rodízio. No banco, a seção 75 do teste de isolamento reprova qualquer
// função que passe a ler a tabela. Aqui, o mesmo para o código: só o Mapa
// (e os tipos gerados) podem falar da tabela ou das duas funções dela.
import { describe, expect, it } from "bun:test";
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join, relative } from "node:path";

const RAIZ = join(import.meta.dir, "../..");

function arquivos(pasta: string, achados: string[] = []): string[] {
  for (const nome of readdirSync(pasta)) {
    const caminho = join(pasta, nome);
    if (statSync(caminho).isDirectory()) arquivos(caminho, achados);
    else if (/\.(tsx?|mjs|js)$/.test(nome) && !/\.test\.tsx?$/.test(nome)) achados.push(caminho);
  }
  return achados;
}

const QUEM_PODE = [
  "src/integrations/supabase/contrato.ts",
  "src/integrations/supabase/types.ts",
  "src/jornada/MapaDaJornada.tsx",
];

describe("intervalo do mapa", () => {
  it("só a tela do Mapa lê ou grava o intervalo de planejamento", () => {
    const quem = [...arquivos(join(RAIZ, "src")), ...arquivos(join(RAIZ, "scripts"))]
      .filter((f) => /intervalosdomapa|salvar_intervalo_do_mapa|mapa_da_jornada/.test(readFileSync(f, "utf8")))
      .map((f) => relative(RAIZ, f))
      .sort();
    expect(quem.filter((f) => !QUEM_PODE.includes(f))).toEqual([]);
  });
});
