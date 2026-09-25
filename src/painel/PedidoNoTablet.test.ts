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
    // Nada de caminho de PIN separado: é o mesmo componente.
    expect(TABLET).toContain('titulo="Quem está pedindo?"');
    const trecho = TABLET.slice(TABLET.indexOf('titulo="Quem está pedindo?"'));
    expect(trecho.slice(0, 400)).toContain("erro={abrirPedido.isError");
  });
});
