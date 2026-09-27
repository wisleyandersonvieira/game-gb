// O dia escrito na tela. Roda com TZ=UTC (package.json): se alguma conta
// usasse o fuso do aparelho em vez do fuso da conta, estes testes pegariam.
import { describe, expect, it } from "bun:test";
import { diaNoFuso, quandoFoi } from "./hoje";

const SP = "America/Sao_Paulo";

describe("o dia escrito no cartão", () => {
  it("a suíte roda em UTC, para o fuso do aparelho não mascarar nada", () => {
    expect(Intl.DateTimeFormat().resolvedOptions().timeZone).toBe("UTC");
  });

  // "Agora" é 27/09 às 09h35 em São Paulo; o servidor diz hoje = 2026-09-27.
  const hoje = "2026-09-27";

  it("entrega de ontem às 23h50 é de ONTEM, e o cartão diz isso", () => {
    // 26/09 23h50 em São Paulo = 27/09 02h50 UTC. Lido em UTC (o fuso do
    // servidor), ela pareceria de hoje — é exatamente o erro a evitar.
    const iso = "2026-09-27T02:50:00Z";
    expect(diaNoFuso(iso, SP)).toBe("2026-09-26");
    expect(quandoFoi(iso, hoje, SP)).toBe("ontem às 23h50");
  });

  it("hoje às 23h50 continua sendo hoje, mesmo já sendo dia 28 em UTC", () => {
    expect(quandoFoi("2026-09-28T02:50:00Z", hoje, SP)).toBe("às 23h50");
    expect(quandoFoi("2026-09-28T12:00:00Z", hoje, SP)).toBe("amanhã às 09h00");
  });

  it("entrega de hoje às 00h10 é de hoje: só a hora", () => {
    const iso = "2026-09-27T03:10:00Z"; // 27/09 00h10 em São Paulo
    expect(diaNoFuso(iso, SP)).toBe("2026-09-27");
    expect(quandoFoi(iso, hoje, SP)).toBe("às 00h10");
  });

  it("as seis do print (ontem à tarde e à noite) saem todas como ontem", () => {
    const horas = ["14:04", "18:12", "19:52", "22:30", "22:44", "22:47"]; // UTC de 26/09
    const escritos = horas.map((h) => quandoFoi(`2026-09-26T${h}:00Z`, hoje, SP));
    expect(escritos).toEqual([
      "ontem às 11h04", "ontem às 15h12", "ontem às 16h52",
      "ontem às 19h30", "ontem às 19h44", "ontem às 19h47",
    ]);
  });

  it("mais longe que ontem, escreve a data", () => {
    expect(quandoFoi("2026-09-25T22:47:00Z", hoje, SP)).toBe("25/09 às 19h47");
  });

  it("o fuso é o DA CONTA: o mesmo instante é ontem em Rio Branco e hoje em São Paulo", () => {
    const iso = "2026-09-27T03:30:00Z"; // 00h30 em SP, 22h30 do dia 26 em Rio Branco
    expect(quandoFoi(iso, "2026-09-27", SP)).toBe("às 00h30");
    expect(quandoFoi(iso, "2026-09-27", "America/Rio_Branco")).toBe("ontem às 22h30");
  });
});
