import { describe, expect, it } from "bun:test";
import { montarEtapas } from "./medicaoDoTablet";

const valor = (etapas: [string, number][], trecho: string) => etapas.find(([r]) => r.includes(trecho))?.[1];

describe("medição do tablet", () => {
  it("a rede tablet↔servidor é o que a chamada levou menos o que o servidor trabalhou", () => {
    const e = montarEtapas("aceite", { chamada: 600, desenho: 20 }, { token: 5, tablet: 150, banco: 190, banco_pin: 3, banco_acao: 20, banco_fila: 12, servidor: 350 });
    expect(valor(e, "tablet ↔ servidor")).toBe(250);
  });

  it("abre a ida única ao banco em rede + trabalho do banco", () => {
    const e = montarEtapas("aceite", { chamada: 600, desenho: 20 }, { tablet: 150, banco: 190, banco_pin: 3, banco_acao: 20, banco_fila: 12, servidor: 345 });
    expect(valor(e, "servidor ↔ banco")).toBe(155);
    expect(valor(e, "trava + conferir o PIN")).toBe(3);
    expect(valor(e, "rodízio + gravar o aceite")).toBe(20);
    expect(valor(e, "fila já atualizada")).toBe(12);
  });

  it("nunca mostra tempo negativo, mesmo com relógios diferentes", () => {
    const e = montarEtapas("aceite", { chamada: 100, desenho: 5 }, { servidor: 140, banco: 10, banco_pin: 8, banco_acao: 8, banco_fila: 0 });
    for (const [, ms] of e) expect(ms).toBeGreaterThanOrEqual(0);
  });

  it("no caminho antigo, cada ida ao banco aparece separada, e a recarga também", () => {
    const e = montarEtapas(
      "aceite",
      { chamada: 1300, recarga: 900, desenho: 20 },
      { token: 4, tablet_meuacesso: 150, tablet_vinculo: 150, trava_abrir: 220, pin: 150, trava_fechar: 150, aceite: 170, servidor: 994 },
    );
    expect(valor(e, "abrir a trava")).toBe(220);
    expect(valor(e, "fechar a trava")).toBe(150);
    expect(valor(e, "Recarga da fila")).toBe(900);
    expect(e.some(([r]) => r.includes("ida única"))).toBe(false);
  });

  it("na entrega, a foto aparece separada do PIN", () => {
    const e = montarEtapas(
      "entrega",
      { chamada: 1500, fotoAutorizacao: 400, fotoEnvio: 3200, desenho: 20 },
      { tablet: 150, foto_baixar_e_conferir: 700, banco: 200, banco_pin: 3, banco_acao: 15, banco_fila: 12, servidor: 1050 },
    );
    expect(valor(e, "envio do arquivo")).toBe(3200);
    expect(valor(e, "baixa e confere")).toBe(700);
    expect(valor(e, "trava + conferir o PIN")).toBe(3);
    expect(valor(e, "gravar a entrega")).toBe(15);
  });
});
