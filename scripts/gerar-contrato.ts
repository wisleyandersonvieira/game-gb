// Gera src/integrations/supabase/contrato.ts a partir de types.ts.
//
//   bun run contrato
//
// O contrato é a lista de parâmetros que o aplicativo espera em cada função
// que ele chama. A tela /saude manda essa lista para o banco e mostra o que
// não bate — é assim que uma função que mudou de parâmetros aparece antes de
// alguém descobrir testando na loja.
import { readdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const RAIZ = join(import.meta.dir, "..");

/** Do `{` na posição dada até o `}` que o fecha. */
function ateFechar(texto: string, abre: number): string {
  let nivel = 0;
  for (let i = abre; i < texto.length; i++) {
    if (texto[i] === "{") nivel++;
    else if (texto[i] === "}") {
      nivel--;
      if (nivel === 0) return texto.slice(abre + 1, i);
    }
  }
  return "";
}

export function parametrosDoTypes(types: string): Record<string, string[]> {
  const inicio = types.indexOf("    Functions: {");
  const fim = types.indexOf("\n    Enums: {", inicio);
  const bloco = types.slice(inicio, fim);
  const mapa: Record<string, string[]> = {};

  for (const m of bloco.matchAll(/^ {6}([a-z0-9_]+): \{/gm)) {
    // Contando chaves, e não procurando "\n      }": há entradas escritas numa
    // linha só, e ali o fim da entrada não tem recuo nenhum. Sem isto, os
    // parâmetros da função SEGUINTE vazavam para esta — sou_master aparecia
    // pedindo p_dia e p_tipofrequencia, que são de tarefa_cai_no_dia.
    const corpo = ateFechar(bloco, m.index! + m[0].length - 1);
    const args = corpo.match(/Args:\s*\{/);
    const nomes = args
      ? [...ateFechar(corpo, args.index! + args[0].length - 1).matchAll(/\b(p_[a-z0-9_]+)\s*\??:/g)].map((p) => p[1])
      : [];
    mapa[m[1]] = [...new Set(nomes)].sort();
  }
  return mapa;
}

export function arquivosDeCodigo(pasta: string, achados: string[] = []): string[] {
  for (const nome of readdirSync(pasta)) {
    const caminho = join(pasta, nome);
    if (statSync(caminho).isDirectory()) arquivosDeCodigo(caminho, achados);
    else if ((nome.endsWith(".ts") || nome.endsWith(".tsx")) && !nome.endsWith(".test.ts")) achados.push(caminho);
  }
  return achados;
}

/** Toda função chamada com `.rpc("nome"` no código do aplicativo. */
export function funcoesChamadas(): string[] {
  const nomes = new Set<string>();
  for (const arquivo of arquivosDeCodigo(join(RAIZ, "src"))) {
    for (const m of readFileSync(arquivo, "utf8").matchAll(/\.rpc\(\s*"([a-z0-9_]+)"/g)) nomes.add(m[1]);
  }
  return [...nomes].sort();
}

export function montarContrato(): Record<string, string[]> {
  const doTypes = parametrosDoTypes(readFileSync(join(RAIZ, "src/integrations/supabase/types.ts"), "utf8"));
  const contrato: Record<string, string[]> = {};
  for (const nome of funcoesChamadas()) if (doTypes[nome]) contrato[nome] = doTypes[nome];
  return contrato;
}

export function textoDoContrato(contrato: Record<string, string[]>): string {
  const linhas = Object.keys(contrato)
    .sort()
    .map((n) => `  ${n}: [${contrato[n].map((p) => `"${p}"`).join(", ")}],`);
  return `// O CONTRATO do aplicativo com o banco: para cada função que o app chama,
// os parâmetros que ele espera encontrar.
//
// GERADO a partir de src/integrations/supabase/types.ts, que por sua vez vem
// do banco. Não edite à mão: rode \`bun run contrato\` depois de regenerar os
// tipos. O teste em contrato.test.ts reprova se este arquivo ficar para trás.
//
// Para que serve: a tela /saude manda esta lista para o banco e mostra o que
// não bate. Sem isso, uma função que mudou de parâmetros só aparecia quando
// alguém testava na loja — foi o que aconteceu em 25/09/2026.
export const CONTRATO: Record<string, string[]> = {
${linhas.join("\n")}
};
`;
}

if (import.meta.main) {
  const destino = join(RAIZ, "src/integrations/supabase/contrato.ts");
  const contrato = montarContrato();
  writeFileSync(destino, textoDoContrato(contrato));
  console.log(`contrato gerado: ${Object.keys(contrato).length} funções`);
}
