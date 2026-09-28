import { describe, expect, it } from "bun:test";
import { mensagemDoPin, quemPodeTocar } from "./mensagensDoPin";

describe("o que o tablet diz quando o PIN não passa", () => {
  it("de folga: diz a verdade, com o nome que já estava na tela", () => {
    expect(mensagemDoPin({ folga: true, nome: "Davi O." })).toBe("Davi O. está de folga hoje nesta loja.");
  });

  it("bloqueado: diz que está bloqueado e quanto falta — nunca 'confira o número'", () => {
    const m = mensagemDoPin({ bloqueado: true, minutos: 3, nome: "Ana O." })!;
    expect(m).toContain("bloqueado");
    expect(m).toContain("3 minutos");
    expect(m).toContain("peça ao gestor");
    expect(m.toLowerCase()).not.toContain("confira");
    expect(mensagemDoPin({ bloqueado: true, minutos: 1, nome: "Ana O." })).toContain("1 minuto ");
  });

  it("o erro que fecha o bloqueio avisa por quanto tempo", () => {
    const m = mensagemDoPin({ pinerrado: true, bloqueado: true, minutos: 10, nome: "Ana O." })!;
    expect(m).toContain("PIN errado");
    expect(m).toContain("10 minutos");
  });

  it("errou sem bloquear: 'PIN errado para <nome>'", () => {
    expect(mensagemDoPin({ pinerrado: true, nome: "Bia O." })).toBe("PIN errado para Bia O. Tente de novo.");
  });

  it("deu certo: nenhuma mensagem", () => {
    expect(mensagemDoPin({ funcionarioid: 1, nome: "Ana O." })).toBeNull();
  });
});

describe("a lista 'toque no seu nome'", () => {
  const equipe = [
    { funcionarioid: 1, nome: "Ana O." },
    { funcionarioid: 2, nome: "Bia O." },
    { funcionarioid: 3, nome: "Caio O." },
  ];
  it("missão da equipe: todos que trabalham hoje", () => {
    expect(quemPodeTocar(equipe, { todos: true, pessoas: [], esperando: [] })).toEqual(equipe);
  });
  it("compartilhada: só quem a regra do aceite deixa pegar", () => {
    const podem = { todos: false, pessoas: [{ nome: "Ana O.", esperamin: 0 }, { nome: "Caio O.", esperamin: 4 }], esperando: [] };
    expect(quemPodeTocar(equipe, podem).map((p) => p.funcionarioid)).toEqual([1, 3]);
  });
});
