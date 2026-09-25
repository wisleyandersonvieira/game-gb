// O pedido no tablet: o que dá para provar sem navegador.
//
// O tablet é de todo mundo. A tela do pedido não pode ficar aberta no nome de
// uma pessoa depois que ela sai de perto.
import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { SEGUNDOS_SEM_TOQUE } from "./PedidoNoTablet";

const TELA = readFileSync(join(import.meta.dir, "PedidoNoTablet.tsx"), "utf8");
const TABLET = readFileSync(join(import.meta.dir, "../routes/tablet.tsx"), "utf8");

describe("a tela do pedido no tablet", () => {
  it("volta sozinha depois de cerca de 90 segundos sem toque", () => {
    expect(SEGUNDOS_SEM_TOQUE).toBe(90);
    // E o relógio é reiniciado a cada toque, senão fecharia no meio da digitação.
    expect(TELA).toContain("onPointerDown={marcarToque}");
    expect(TELA).toContain("setUltimoToque(Date.now())");
  });

  it("mostra de quem é o pedido, para ninguém pedir no nome errado", () => {
    expect(TELA).toContain("Pedido de {nome}");
  });

  it("não guarda o PIN: manda o passe assinado pelo servidor", () => {
    expect(TELA).toContain("passe");
    expect(TELA).not.toContain("pin");
  });

  it("os alvos de toque continuam grandes", () => {
    expect(TELA).toContain("min-h-[64px]");
    expect(TELA).toContain("min-h-[48px]");
  });
});

describe("o menu do tablet", () => {
  it("tem Solicitações e nenhum item desativado ou 'em breve'", () => {
    const menu = TABLET.slice(TABLET.indexOf("{menuAberto && ("), TABLET.indexOf("{recado &&"));
    expect(menu).toContain("Solicitações");
    expect(menu).not.toContain("em breve");
    expect(menu).not.toContain("disabled");
  });

  it("o PIN do menu usa a MESMA modal do pegar tarefa", () => {
    // Nada de caminho de PIN separado: é o mesmo componente, com o título
    // mudando conforme o item do menu.
    expect(TABLET).toContain('"Quem está lendo?" : "Quem está pedindo?"');
    const trecho = TABLET.slice(TABLET.indexOf('"Quem está lendo?"'));
    expect(trecho.slice(0, 400)).toContain("erro={abrirPedido.isError");
  });
});

describe("o mural no tablet", () => {
  const MURAL = readFileSync(join(import.meta.dir, "MuralNoTablet.tsx"), "utf8");

  it("volta sozinho depois de 90 segundos sem toque", () => {
    expect(MURAL).toContain("SEGUNDOS_SEM_TOQUE = 90");
    expect(MURAL).toContain("onPointerDown");
  });

  it("mostra de quem é o mural, para ninguém dar ciência no nome errado", () => {
    expect(MURAL).toContain("Mural de {nome}");
  });

  it("não guarda o PIN: manda o passe assinado", () => {
    expect(MURAL).toContain("passe");
    expect(MURAL).not.toMatch(/\bpin\b/);
  });

  it("não reaproveita o conteúdo de uma pessoa num aparelho de todos", () => {
    // staleTime e gcTime zerados: ao fechar, nada fica guardado em memória
    // para a próxima pessoa que abrir.
    expect(MURAL).toContain("staleTime: 0");
    expect(MURAL).toContain("gcTime: 0");
  });

  it("dois toques rápidos não registram duas ciências", () => {
    expect(MURAL).toContain("const dando = useRef(false)");
    expect(MURAL).toMatch(/if \(dando\.current\) return;/);
    expect(MURAL).toMatch(/onSettled:[\s\S]{0,60}dando\.current = false/);
  });

  it("os alvos de toque continuam grandes", () => {
    expect(MURAL).toContain("min-h-[64px]");
    expect(MURAL).toContain("min-h-[48px]");
  });
});

describe("o menu do tablet, com dois itens", () => {
  it("tem Mural e Solicitações, e nada desativado", () => {
    const menu = TABLET.slice(TABLET.indexOf("{menuAberto && ("), TABLET.indexOf("{recado &&"));
    expect(menu).toContain("Mural");
    expect(menu).toContain("Solicitações");
    expect(menu).not.toContain("em breve");
    expect(menu).not.toContain("disabled");
  });

  it("o passe é por ASSUNTO: o de pedido não abre o mural", () => {
    const servidor = readFileSync(join(import.meta.dir, "../servidor/tablet.ts"), "utf8");
    expect(servidor).toContain("emitirPasse(`${data.assunto}");
    expect(servidor).toContain("`mural:${t.contaid}:${t.lojaid}`");
    expect(servidor).toContain("`pedido:${t.contaid}:${t.lojaid}`");
  });
});
