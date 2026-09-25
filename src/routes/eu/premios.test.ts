// A tela de pedir resgate, do lado de quem MOSTRA.
//
// Esta tela mexe em pontos. O banco é a garantia final (trava por pessoa e
// FOR UPDATE), mas a tela não pode deixar a pessoa ver dois pedidos iguais
// nascendo, nem mandar um número que ninguém entendeu.
import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const TELA = readFileSync(join(import.meta.dir, "premios.tsx"), "utf8");
const SERVIDOR = readFileSync(join(import.meta.dir, "../../servidor/colaborador.ts"), "utf8");

/** A mesma regra que a tela usa para entender o valor digitado. */
function valorDigitado(valor: string): number | null {
  const limpo = valor.trim().replace(",", ".");
  if (!/^\d+(\.\d{1,2})?$/.test(limpo)) return null;
  const n = Number(limpo);
  return n > 0 ? n : null;
}

describe("o valor do abate, como a tela entende", () => {
  it("aceita o que a pessoa escreve de verdade", () => {
    expect(valorDigitado("10")).toBe(10);
    expect(valorDigitado("10,50")).toBe(10.5);
    expect(valorDigitado("10.50")).toBe(10.5);
    expect(valorDigitado(" 7,25 ")).toBe(7.25);
  });

  it("recusa o que ninguém entenderia, em vez de mandar NaN para o banco", () => {
    // Antes, "1.234,56" virava NaN e a pessoa lia "escolha um prêmio do
    // catálogo" — uma mensagem que não tem nada a ver com o que ela fez.
    expect(valorDigitado("1.234,56")).toBeNull();
    expect(valorDigitado("abc")).toBeNull();
    expect(valorDigitado("")).toBeNull();
    expect(valorDigitado("0")).toBeNull();
    expect(valorDigitado("-5")).toBeNull();
    expect(valorDigitado("10,555")).toBeNull();
  });
});

describe("dois toques rápidos", () => {
  it("a tela tem trava SÍNCRONA, e não só o botão desabilitado", () => {
    // O botão desabilitado depende de um redesenho; dois toques na mesma
    // fração de segundo passam antes dele.
    expect(TELA).toContain("const pedindo = useRef(false)");
    expect(TELA).toMatch(/if \(pedindo\.current\) return;/);
    // E a trava é liberada aconteça o que acontecer (onSettled, não onSuccess).
    expect(TELA).toMatch(/onSettled:[\s\S]{0,60}pedindo\.current = false/);
  });

  it("desistir também", () => {
    expect(TELA).toContain("const desistindo = useRef(false)");
    expect(TELA).toMatch(/onSettled:[\s\S]{0,60}desistindo\.current = false/);
  });

  it("nenhum onClick chama a mutação direto: todos passam pela trava", () => {
    // pedir.mutate() existe UMA vez, dentro da própria trava. O que não pode
    // é um botão chamá-la sem passar por lá.
    const cliques = [...TELA.matchAll(/onClick=\{[\s\S]*?\n?\s*\}/g)].map((m) => m[0]);
    const direto = cliques.filter((c) => /\b(pedir|desistir)\.mutate\(/.test(c));
    expect(direto).toEqual([]);
    expect(TELA.match(/pedir\.mutate\(/g) ?? []).toHaveLength(1);
    expect(TELA.match(/desistir\.mutate\(/g) ?? []).toHaveLength(1);
  });
});

describe("o que a tela NÃO decide", () => {
  it("quem pede vem do token, e a tela não manda funcionarioid", () => {
    expect(TELA).not.toContain("funcionarioid");
    expect(SERVIDOR).toContain("p_funcionarioid: p.funcionarioid");
  });

  it("a loja do pedido é decidida no servidor, não na tela", () => {
    expect(TELA).not.toContain("lojaid");
    expect(SERVIDOR).toContain("umaLojaSo");
  });

  it('"cabe no saldo" vem do servidor, não de uma conta da tela', () => {
    // A tela só exibe o que eu_premios calculou.
    expect(TELA).toContain("p.cabe");
    expect(TELA).not.toMatch(/saldo\s*[<>]=?\s*p\.custo/);
  });
});
