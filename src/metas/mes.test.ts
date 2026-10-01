// A meta do mês dia a dia (30/09/2026): o Replicar e o Salvar da tela.
// O banco recusa de novo (seção 118 do teste de isolamento); aqui a tela
// prova que nem manda o que não pode.
import { describe, expect, it } from "bun:test";
import { deOndeVem, mudancas, nomeDoMes, replicar, somarMes, temAlteracao, type DiaDoMes, type Semana } from "./mes";

// Outubro de 2026: dia 1 é quinta-feira.
const dia = (n: number, o: Partial<DiaDoMes> = {}): DiaDoMes => ({
  dia: `2026-10-${String(n).padStart(2, "0")}`,
  lancado: false,
  origem: "semana",
  meta: 100,
  pontos: 1,
  descricao: null,
  modelo: 100,
  modelopontos: 1,
  ...o,
});

const MES = [
  dia(1, { lancado: true, meta: 90 }), // quinta, já lançado
  dia(2, { origem: "especial", meta: 300, pontos: 3, descricao: "Especial" }), // sexta, especial
  dia(3, { origem: "mes", meta: 250, pontos: 5 }), // sábado, já tem valor deste mês
  dia(4), // domingo, em branco (segue o modelo)
  dia(5), // segunda, em branco
];
const SEMANA: Semana = [
  { valor: "700", pontos: "7" }, // domingo
  { valor: "100", pontos: "1" },
  { valor: "200", pontos: "2" },
  { valor: "300", pontos: "3" },
  { valor: "400", pontos: "4" }, // quinta
  { valor: "500", pontos: "5" }, // sexta
  { valor: "600", pontos: "6" }, // sábado
];

describe("replicar", () => {
  it("por padrão preenche SÓ os dias em branco, com o valor do dia da semana de cada um", () => {
    const { rascunho, mudou } = replicar(MES, {}, SEMANA, false);
    expect(mudou).toBe(2);
    expect(rascunho).toEqual({ "2026-10-04": { valor: "700", pontos: "7" }, "2026-10-05": { valor: "100", pontos: "1" } });
  });
  it("com 'substituir', também os dias que já têm valor deste mês", () => {
    const { rascunho } = replicar(MES, {}, SEMANA, true);
    expect(rascunho["2026-10-03"]).toEqual({ valor: "600", pontos: "6" });
  });
  it("NUNCA toca em dia já lançado nem em dia com meta especial, nem substituindo", () => {
    const { rascunho } = replicar(MES, {}, SEMANA, true);
    expect(rascunho["2026-10-01"]).toBeUndefined();
    expect(rascunho["2026-10-02"]).toBeUndefined();
    expect(mudancas(MES, rascunho).linhas.map((l) => l.dia)).not.toContain("2026-10-01");
  });
  it("o que foi digitado conta como 'já tem valor' (não é apagado sem 'substituir')", () => {
    const { rascunho } = replicar(MES, { "2026-10-04": { valor: "999", pontos: "9" } }, SEMANA, false);
    expect(rascunho["2026-10-04"]).toEqual({ valor: "999", pontos: "9" });
  });
  it("dia da semana com o campo vazio não mexe em nada", () => {
    const semana = SEMANA.map((s, i) => (i === 0 ? { valor: "", pontos: "" } : s));
    expect(replicar(MES, {}, semana, false).rascunho["2026-10-04"]).toBeUndefined();
  });
});

describe("salvar: só o que mudou, e nada de dia que não se edita", () => {
  it("manda só os dias alterados; valor vazio devolve o dia ao modelo", () => {
    const { linhas, erros } = mudancas(MES, {
      "2026-10-03": { valor: "", pontos: "" }, // tinha 250 deste mês: volta ao modelo
      "2026-10-04": { valor: "1.234,50", pontos: "3" },
      "2026-10-05": { valor: "", pontos: "" }, // já estava em branco: nada
    });
    expect(erros).toEqual({});
    expect(linhas).toEqual([
      { dia: "2026-10-03", valormeta: null, pontospremio: null },
      { dia: "2026-10-04", valormeta: 1234.5, pontospremio: 3 },
    ]);
  });
  it("digitado num dia lançado ou com especial (ex.: tela velha): não vai", () => {
    const { linhas } = mudancas(MES, { "2026-10-01": { valor: "1", pontos: "1" }, "2026-10-02": { valor: "1", pontos: "1" } });
    expect(linhas).toEqual([]);
  });
  it("pontos quebrados ou vazios e meta negativa viram erro no dia, sem perder o resto", () => {
    const { linhas, erros } = mudancas(MES, {
      "2026-10-04": { valor: "10", pontos: "1,5" },
      "2026-10-05": { valor: "-3", pontos: "1" },
      "2026-10-03": { valor: "260", pontos: "" },
    });
    expect(Object.keys(erros).sort()).toEqual(["2026-10-03", "2026-10-04", "2026-10-05"]);
    expect(linhas).toEqual([]);
  });
  it("sabe se há alteração não salva", () => {
    expect(temAlteracao(MES, {})).toBe(false);
    expect(temAlteracao(MES, { "2026-10-03": { valor: "250", pontos: "5" } })).toBe(false);
    expect(temAlteracao(MES, { "2026-10-03": { valor: "251", pontos: "5" } })).toBe(true);
  });
});

describe("de onde veio cada dia", () => {
  it("já lançado, especial, deste mês ou do modelo", () => {
    expect(MES.map((d) => deOndeVem(d, {}))).toEqual(["já lançado", "especial", "deste mês", "do modelo", "do modelo"]);
    expect(deOndeVem(MES[3], { "2026-10-04": { valor: "5", pontos: "0" } })).toBe("deste mês");
  });
});

describe("navegar entre meses", () => {
  it("vira o ano para frente e para trás", () => {
    expect(somarMes("2026-12", 1)).toBe("2027-01");
    expect(somarMes("2026-01", -1)).toBe("2025-12");
    expect(somarMes("2026-10", -13)).toBe("2025-09");
    expect(nomeDoMes("2026-10")).toBe("outubro de 2026");
  });
});
