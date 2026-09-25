// A folha de estilo da TV só pode usar CSS que navegador antigo entende.
//
// Por que existe: em 25/09/2026 a TV Samsung da loja mostrou a página SEM
// ESTILO NENHUM. O Tailwind 4 envolve 100% do que gera em `@layer`, e o
// navegador que não conhece `@layer` descarta o BLOCO INTEIRO — não uma cor:
// a folha toda. O gestor viu texto empilhado numa coluna, sem fundo.
//
// Este teste quebra a entrega se alguém um dia reimportar o Tailwind aqui, ou
// escrever CSS moderno na folha da TV.
import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { repartir } from "./TelaDaTv";

const RAIZ = join(import.meta.dir, "../..");
const FOLHA = join(RAIZ, "src/painel/tv.css");

/** O CSS sem comentários: o comentário desta folha CITA o que é proibido. */
function semComentarios(css: string): string {
  return css.replace(/\/\*[\s\S]*?\*\//g, "");
}

/** Cada construção, com o navegador a partir do qual ela passou a existir. */
const PROIBIDO: { nome: string; acha: RegExp; desde: string }[] = [
  { nome: "oklch()", acha: /\boklch\s*\(/i, desde: "Chrome 111 (2023)" },
  { nome: "color-mix()", acha: /\bcolor-mix\s*\(/i, desde: "Chrome 111 (2023)" },
  { nome: "@layer", acha: /@layer\b/i, desde: "Chrome 99 (2022)" },
  { nome: "@container", acha: /@container\b/i, desde: "Chrome 105 (2022)" },
  { nome: ":has()", acha: /:has\s*\(/i, desde: "Chrome 105 (2022)" },
  { nome: "@property", acha: /@property\b/i, desde: "Chrome 85 (2020)" },
  { nome: "aspect-ratio", acha: /\baspect-ratio\s*:/i, desde: "Chrome 88 (2021)" },
  { nome: "inset (atalho)", acha: /(^|[;{\s])inset\s*:/i, desde: "Chrome 87 (2020)" },
  { nome: "gap em flex", acha: /(^|[;{\s])(row-|column-)?gap\s*:/i, desde: "Chrome 84 (2020)" },
  { nome: "propriedade lógica", acha: /\b(margin|padding|border)-(inline|block)\b/i, desde: "Chrome 87 (2020)" },
  { nome: "CSS aninhado", acha: /(^|\n)\s*&/, desde: "Chrome 112 (2023)" },
  { nome: "unidade dvh/svh/lvh", acha: /\b\d+(dvh|svh|lvh|dvw|svw|lvw)\b/i, desde: "Chrome 108 (2022)" },
];

describe("a folha de estilo da TV", () => {
  const css = semComentarios(readFileSync(FOLHA, "utf8"));

  it("existe e tem conteúdo (o leitor está achando o arquivo certo)", () => {
    expect(css.length).toBeGreaterThan(500);
    expect(css).toContain(".tv-tela");
  });

  for (const c of PROIBIDO) {
    it(`não usa ${c.nome} — só existe a partir do ${c.desde}`, () => {
      expect(c.acha.test(css)).toBe(false);
    });
  }

  it("dá fundo sólido ao corpo da página (senão aparece a parede atrás)", () => {
    expect(/html\.tv[^{]*\{[^}]*background-color:\s*#[0-9a-f]{6}/i.test(css)).toBe(true);
  });

  // O piso de 24px valia para o desenho antigo. O layout aprovado em
  // 25/09/2026 usa RÓTULOS pequenos em maiúsculas com muito espaçamento entre
  // letras — eles são etiqueta de coluna, não texto de leitura. Então o piso
  // passou a valer por papel, que é mais honesto do que um número só.
  function tamanhoDe(classe: string): number {
    const bloco = css.slice(css.indexOf(classe));
    const m = bloco.slice(0, bloco.indexOf("}")).match(/font-size:\s*(\d+)px/);
    return m ? Number(m[1]) : 0;
  }

  it("o que a equipe lê de longe é grande", () => {
    // O nome da tarefa e o nome no pódio.
    expect(tamanhoDe(".tv-item-titulo")).toBeGreaterThanOrEqual(26);
    expect(tamanhoDe(".tv-podio-nome")).toBeGreaterThanOrEqual(26);
    // A linha secundária de cada item.
    expect(tamanhoDe(".tv-item-linha")).toBeGreaterThanOrEqual(20);
    expect(tamanhoDe(".tv-vazio")).toBeGreaterThanOrEqual(20);
    // E o nome da loja, que é o maior de todos.
    expect(tamanhoDe(".tv-loja")).toBeGreaterThanOrEqual(60);
  });

  it("nada na tela fica abaixo de 15px, nem as etiquetas", () => {
    const tamanhos = [...css.matchAll(/font-size:\s*(\d+)px/g)].map((m) => Number(m[1]));
    expect(tamanhos.length).toBeGreaterThan(5);
    expect(Math.min(...tamanhos)).toBeGreaterThanOrEqual(15);
  });

  it("deixa margem de segurança nas bordas (a TV corta as beiradas)", () => {
    expect(/\.tv-tela[^}]*padding:\s*4%/.test(css)).toBe(true);
  });

  it("a TV não rola: o que não couber vira página", () => {
    expect(/overflow:\s*hidden/.test(css)).toBe(true);
  });
});

describe("a tela da TV não depende do resto do sistema", () => {
  const telas = [
    "src/painel/TelaDaTv.tsx",
    "src/routes/tv.index.tsx",
    "src/routes/tv.$codigo.tsx",
  ].map((f) => ({ arquivo: f, codigo: readFileSync(join(RAIZ, f), "utf8") }));

  for (const t of telas) {
    it(`${t.arquivo} não importa a folha do aplicativo`, () => {
      expect(t.codigo).not.toContain("styles.css");
    });

    it(`${t.arquivo} não usa classe do Tailwind`, () => {
      // As classes da TV começam com "tv-". Qualquer className com outra coisa
      // é Tailwind voltando pela porta dos fundos.
      const classes = [...t.codigo.matchAll(/className="([^"]+)"/g)].flatMap((m) => m[1].split(/\s+/));
      const estranhas = classes.filter((c) => c !== "" && !c.startsWith("tv-"));
      expect(estranhas).toEqual([]);
    });
  }

  it("o aplicativo não manda a própria folha para as telas de TV", () => {
    const root = readFileSync(join(RAIZ, "src/routes/__root.tsx"), "utf8");
    expect(root).toContain("ehTelaDeTv");
  });
});

describe("como um navegador antigo leria esta folha", () => {
  // Um navegador descarta a REGRA inteira quando não entende o @-rule, e a
  // DECLARAÇÃO quando não entende o valor. Simulamos isso e conferimos que
  // não sobra nada de fora: o que ele lê é a folha inteira.
  it("um navegador antigo mantém 100% da folha", () => {
    const css = semComentarios(readFileSync(FOLHA, "utf8"));
    const descartado = css
      .split("}")
      .filter((bloco) => PROIBIDO.some((c) => c.acha.test(bloco)));
    expect(descartado).toEqual([]);
  });
});

describe("como a TV reparte as colunas em telas", () => {
  it("até 3 colunas cabem numa tela só, e aí não há troca", () => {
    expect(repartir(["a"])).toEqual([["a"]]);
    expect(repartir(["a", "b", "c"])).toEqual([["a", "b", "c"]]);
  });

  it("4 vira 2+2, 5 vira 3+2, 6 vira 3+3 — o mais equilibrado possível", () => {
    expect(repartir(["a", "b", "c", "d"]).map((t) => t.length)).toEqual([2, 2]);
    expect(repartir(["a", "b", "c", "d", "e"]).map((t) => t.length)).toEqual([3, 2]);
    expect(repartir(["a", "b", "c", "d", "e", "f"]).map((t) => t.length)).toEqual([3, 3]);
  });

  it("nenhuma tela passa de 3 colunas, e nenhuma coluna se perde", () => {
    for (let n = 1; n <= 6; n++) {
      const cols = Array.from({ length: n }, (_, i) => String(i));
      const telas = repartir(cols);
      expect(telas.flat()).toEqual(cols);
      for (const t of telas) expect(t.length).toBeLessThanOrEqual(3);
    }
  });
});
