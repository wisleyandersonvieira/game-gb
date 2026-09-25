// O CONTRATO entre o aplicativo e o banco.
//
// Por que existe: em 25/09/2026 a entrega no tablet quebrou porque o código
// chamava uma função com parâmetros que a migração não tinha. O `bun run
// build` passou, o TypeScript passou, e o defeito só apareceu quando o Wisley
// testou na loja.
//
// Este teste lê TODAS as chamadas `.rpc("nome", { p_... })` do código e
// confere, contra as migrações, que a função existe e que cada parâmetro
// passado existe nela. Some uma função, ou muda o nome de um parâmetro, e a
// entrega para aqui — não na loja.
import { describe, expect, it } from "bun:test";
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";
import { CONTRATO } from "./contrato";
import { montarContrato, textoDoContrato } from "../../../scripts/gerar-contrato";

const RAIZ = join(import.meta.dir, "../../..");

function arquivos(pasta: string, termina: string[], achados: string[] = []): string[] {
  for (const nome of readdirSync(pasta)) {
    const caminho = join(pasta, nome);
    if (statSync(caminho).isDirectory()) arquivos(caminho, termina, achados);
    else if (termina.some((t) => nome.endsWith(t))) achados.push(caminho);
  }
  return achados;
}

/** Do `(` seguinte à posição dada até o `)` que o fecha. */
function ateFechar(texto: string, abre: number, a = "(", f = ")"): string {
  let nivel = 0;
  for (let i = abre; i < texto.length; i++) {
    if (texto[i] === a) nivel++;
    else if (texto[i] === f) {
      nivel--;
      if (nivel === 0) return texto.slice(abre + 1, i);
    }
  }
  return "";
}

// ---------------------------------------------------------------------------
// O que o BANCO oferece: a última definição de cada função vence, porque é
// assim que as migrações funcionam (CREATE OR REPLACE por cima).
// ---------------------------------------------------------------------------
function funcoesDoBanco(): Map<string, Set<string>> {
  // Guardado por NOME e por QUANTOS argumentos: uma função pode ganhar uma
  // versão nova com mais parâmetros e a antiga ser apagada logo depois. Sem
  // contar os argumentos, esse DROP apagava a versão nova do nosso mapa — foi
  // o que aconteceu com diagnostico_do_sistema.
  const porAridade = new Map<string, Map<number, Set<string>>>();
  const migracoes = arquivos(join(RAIZ, "supabase/migrations"), [".sql"]).sort();

  /** Quantos argumentos a lista declara, e quais deles se chamam p_*. */
  function ler(lista: string): { quantos: number; params: Set<string> } {
    const limpa = lista.trim();
    const quantos = limpa === "" ? 0 : partesDoTopo(limpa).length;
    return { quantos, params: new Set([...limpa.matchAll(/\bp_[a-z0-9_]+/gi)].map((m) => m[0].toLowerCase())) };
  }

  for (const arquivo of migracoes) {
    const sql = readFileSync(arquivo, "utf8");
    // ALTER ... RENAME TO conta como criação com o nome novo: foi assim que
    // registrar_resgate virou registrar_troca.
    const eventos = [
      ...sql.matchAll(
        /(CREATE(?: OR REPLACE)?|DROP|ALTER)\s+FUNCTION\s+(?:IF EXISTS\s+)?public\.([a-z0-9_]+)\s*\(/gi,
      ),
    ];
    for (const e of eventos) {
      const palavra = e[1].toUpperCase();
      const nome = e[2].toLowerCase();
      const lista = ateFechar(sql, e.index! + e[0].length - 1);
      const { quantos, params } = ler(lista);

      if (palavra === "DROP") {
        porAridade.get(nome)?.delete(quantos);
        if (porAridade.get(nome)?.size === 0) porAridade.delete(nome);
      } else if (palavra === "ALTER") {
        const resto = sql.slice(e.index! + e[0].length + lista.length);
        const renome = resto.match(/^\s*\)?\s*RENAME\s+TO\s+([a-z0-9_]+)/i);
        if (renome) {
          porAridade.set(renome[1].toLowerCase(), porAridade.get(nome) ?? new Map([[quantos, params]]));
          porAridade.delete(nome);
        }
      } else {
        if (!porAridade.has(nome)) porAridade.set(nome, new Map());
        porAridade.get(nome)!.set(quantos, params);
      }
    }
  }

  // Para conferir, basta a união: um parâmetro vale se alguma versão o tem.
  const oferecidas = new Map<string, Set<string>>();
  for (const [nome, versoes] of porAridade) {
    const todos = new Set<string>();
    for (const params of versoes.values()) for (const p of params) todos.add(p);
    oferecidas.set(nome, todos);
  }
  return oferecidas;
}

/** Separa uma lista de argumentos nas vírgulas de PRIMEIRO nível. */
function partesDoTopo(lista: string): string[] {
  const partes: string[] = [];
  let nivel = 0;
  let atual = "";
  for (const c of lista) {
    if (c === "(" || c === "[") nivel++;
    else if (c === ")" || c === "]") nivel--;
    if (c === "," && nivel === 0) {
      partes.push(atual);
      atual = "";
    } else atual += c;
  }
  if (atual.trim() !== "") partes.push(atual);
  return partes;
}

// ---------------------------------------------------------------------------
// O que o APLICATIVO pede.
// ---------------------------------------------------------------------------
type Chamada = { arquivo: string; funcao: string; parametros: string[] };

function chamadasDoApp(): Chamada[] {
  const fontes = arquivos(join(RAIZ, "src"), [".ts", ".tsx"]).filter(
    (f) => !f.endsWith(".test.ts") && !f.endsWith("types.ts"),
  );
  const chamadas: Chamada[] = [];

  for (const arquivo of fontes) {
    const codigo = readFileSync(arquivo, "utf8");
    for (const m of codigo.matchAll(/\.rpc\(\s*"([a-z0-9_]+)"\s*(,)?/gi)) {
      const funcao = m[1].toLowerCase();
      let parametros: string[] = [];
      if (m[2]) {
        // Só lemos quando os parâmetros vêm escritos ali mesmo. Quando vêm de
        // uma variável, não há o que conferir — e não inventamos.
        const depois = codigo.slice(m.index! + m[0].length);
        const abre = depois.search(/\S/);
        if (depois[abre] === "{") {
          const corpo = ateFechar(depois, abre, "{", "}");
          parametros = [...corpo.matchAll(/(?:^|[,{\s])(p_[a-z0-9_]+)\s*:/gi)].map((p) => p[1].toLowerCase());
        }
      }
      chamadas.push({ arquivo: arquivo.replace(RAIZ + "/", ""), funcao, parametros });
    }
  }
  return chamadas;
}

describe("contrato entre o aplicativo e o banco", () => {
  const banco = funcoesDoBanco();
  const chamadas = chamadasDoApp();

  it("o código realmente chama funções do banco (o leitor está funcionando)", () => {
    expect(chamadas.length).toBeGreaterThan(50);
    expect(banco.size).toBeGreaterThan(50);
  });

  it("toda função que o aplicativo chama existe em alguma migração", () => {
    const faltando = [...new Set(chamadas.filter((c) => !banco.has(c.funcao)).map((c) => `${c.funcao} (${c.arquivo})`))];
    expect(faltando).toEqual([]);
  });

  // -------------------------------------------------------------------------
  // O contrato que a /saude manda para o banco não pode ficar para trás.
  // -------------------------------------------------------------------------
  it("contrato.ts está igual ao que o gerador produz hoje", () => {
    const atual = readFileSync(join(RAIZ, "src/integrations/supabase/contrato.ts"), "utf8");
    // Se isto falhar: rode `bun run contrato`.
    expect(atual).toBe(textoDoContrato(montarContrato()));
  });

  it("toda função que o aplicativo chama está no contrato da /saude", () => {
    const deFora = [...new Set(chamadas.map((c) => c.funcao))].filter((f) => !(f in CONTRATO));
    // Função nova chamada pelo app e ausente do contrato: a /saude não a
    // conferiria, e a diferença só apareceria na loja.
    expect(deFora).toEqual([]);
  });

  it("os parâmetros do contrato batem com as migrações", () => {
    const errados: string[] = [];
    for (const [funcao, params] of Object.entries(CONTRATO)) {
      const noBanco = banco.get(funcao);
      if (!noBanco) {
        errados.push(`${funcao}: está no contrato mas não existe em migração nenhuma`);
        continue;
      }
      for (const p of params) {
        if (!noBanco.has(p)) errados.push(`${funcao}: o contrato diz "${p}", que a migração não tem`);
      }
      // A /saude compara a lista INTEIRA, então parâmetro a MENOS no contrato
      // também acusa — e acusaria para sempre, num banco correto. Foi assim
      // que visao_entregar ficou para trás quando ganhou dois parâmetros.
      for (const p of noBanco) {
        if (!params.includes(p)) errados.push(`${funcao}: a migração tem "${p}", que falta no contrato`);
      }
    }
    expect(errados).toEqual([]);
  });

  it("todo parâmetro que o aplicativo passa existe na função", () => {
    const errados: string[] = [];
    for (const c of chamadas) {
      const tem = banco.get(c.funcao);
      if (!tem) continue; // já cobrado pela prova de cima
      for (const p of c.parametros) {
        if (!tem.has(p)) {
          errados.push(`${c.funcao}: o app manda "${p}", que a função não tem (${c.arquivo})`);
        }
      }
    }
    expect([...new Set(errados)]).toEqual([]);
  });
});
