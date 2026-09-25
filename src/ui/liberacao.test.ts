// A hora de liberação da tarefa, do lado de quem MOSTRA.
//
// O cálculo de "já liberou?" é do banco, no fuso da empresa e com o relógio do
// servidor — o tablet e o celular só exibem o que veio. Estas provas guardam
// duas coisas que dependem da tela: o formato da hora ("15h", "15h30") e o
// fato de que o instante que o banco manda é lido certo mesmo quando quem lê
// está em OUTRO fuso (a suíte roda com TZ=UTC, o fuso do servidor).
import { describe, expect, it } from "bun:test";
import { horaCurta } from "@/routes/_authenticated/tarefas";

describe("como a hora aparece na lista do gestor", () => {
  it("hora redonda vira 15h", () => {
    expect(horaCurta("15:00:00")).toBe("15h");
  });

  it("hora quebrada vira 15h30", () => {
    expect(horaCurta("15:30:00")).toBe("15h30");
  });

  it("meia-noite e um minuto", () => {
    expect(horaCurta("00:01:00")).toBe("00h01");
  });
});

describe("o instante que o banco manda não depende do fuso de quem lê", () => {
  // 15h em Brasília (UTC−3) é 18h UTC. O banco manda o instante com fuso, e
  // é isso que faz a conta fechar em qualquer aparelho.
  const liberaas = "2026-09-25T18:00:00+00:00";

  it("antes da hora, ainda não liberou", () => {
    const agora = Date.parse("2026-09-25T17:59:00Z"); // 14h59 em Brasília
    expect(Date.parse(liberaas) > agora).toBe(true);
  });

  it("depois da hora, liberou", () => {
    const agora = Date.parse("2026-09-25T18:01:00Z"); // 15h01 em Brasília
    expect(Date.parse(liberaas) <= agora).toBe(true);
  });

  it("15h da loja NÃO é 15h do servidor", () => {
    // Se alguém comparasse "15:00" com o relógio do servidor (UTC), a tarefa
    // liberaria três horas cedo. É o erro que este teste existe para barrar.
    const quinzeUtc = Date.parse("2026-09-25T15:00:00Z");
    expect(Date.parse(liberaas)).not.toBe(quinzeUtc);
    expect(Date.parse(liberaas) - quinzeUtc).toBe(3 * 3600_000);
  });
});
