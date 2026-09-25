// O tablet é usado com o dedo, às vezes com a mão molhada.
//
// Os cartões encolheram para caber mais tarefa na tela (25/09/2026). O que NÃO
// pode encolher junto é o alvo de toque: este teste reprova a entrega se
// alguém tirar a altura mínima do botão.
import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const TELA = readFileSync(join(import.meta.dir, "tablet.tsx"), "utf8");

describe("o alvo de toque do tablet", () => {
  it("o botão de ação tem pelo menos 48px de altura e largura cheia", () => {
    const botao = TELA.slice(TELA.indexOf("function BotaoGrande"));
    const classes = botao.slice(0, botao.indexOf("</button>"));
    expect(classes).toContain("min-h-[48px]");
    expect(classes).toContain("w-full");
  });

  it("o botão Sair também tem 48px", () => {
    expect(TELA).toMatch(/onClick=\{sair\}[\s\S]{0,120}min-h-\[48px\]/);
  });

  it("o erro do PIN aparece DENTRO da modal", () => {
    const modal = TELA.slice(TELA.indexOf("function TecladoDoPin"));
    // Espaço reservado, para a modal não pular de tamanho.
    expect(modal).toContain("min-h-");
    expect(modal).toContain("text-destructive");
    // E a modal limpa os pontinhos quando dá erro.
    expect(modal).toMatch(/if \(erro\) setPin\(""\)/);
  });

  it("a faixa do topo não repete o erro enquanto a modal está aberta", () => {
    expect(TELA).toContain("agir.isError && !pedindoPin");
  });
});
