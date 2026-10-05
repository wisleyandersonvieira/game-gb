// O X dos avisos do Início (05/10/2026): fechar é por FATO (a loja e o dia),
// nunca por tipo. Dispensar nunca esconde um problema novo.
import { describe, expect, it } from "bun:test";
import { avisosDoInicio, diaAnterior, separarDispensados } from "./avisos-do-inicio";
import type { PainelInicio } from "./tipos";

const avisos = (vendaontem: { lojaid: number; loja: string }[], extra: Partial<NonNullable<PainelInicio["avisos"]>> = {}) =>
  ({
    vendaontem,
    livro: "ok",
    agendamentospassados: 0,
    comunicados24h: { comunicados: 0, pessoas: 0 },
    ...extra,
  }) as unknown as PainelInicio["avisos"];

const CAMPO = { lojaid: 1, loja: "Campo Grande" };
const CENTRO = { lojaid: 2, loja: "Centro" };

describe("o X é por fato", () => {
  it("dispensar a venda de uma loja: a da OUTRA loja continua aparecendo", () => {
    const itens = avisosDoInicio(avisos([CAMPO, CENTRO]), "2026-10-04");
    const fechado = new Set(itens.filter((i) => i.texto.includes("Campo Grande")).flatMap((i) => i.chaves));
    const { visiveis, dispensados } = separarDispensados(itens, fechado);
    expect(visiveis.map((v) => v.texto)).toEqual(["A venda de ontem não foi lançada na Centro."]);
    expect(dispensados).toHaveLength(1);
  });
  it("dispensada a de 03/10, a de 04/10 da mesma loja volta (é outro fato)", () => {
    const hoje = avisosDoInicio(avisos([CAMPO]), "2026-10-04");
    const fechado = new Set(hoje.flatMap((i) => i.chaves));
    expect(separarDispensados(hoje, fechado).visiveis).toEqual([]);
    const amanha = avisosDoInicio(avisos([CAMPO]), "2026-10-05");
    expect(separarDispensados(amanha, fechado).visiveis.map((v) => v.texto)).toEqual(["A venda de ontem não foi lançada na Campo Grande."]);
  });
  it("a chave diz a loja e o dia da venda (ontem), não o dia de hoje", () => {
    expect(avisosDoInicio(avisos([CAMPO]), "2026-10-04")[0].chaves).toEqual(["vendaontem|1|2026-10-03"]);
    expect(diaAnterior("2026-03-01")).toBe("2026-02-28");
  });
  it("aviso de contagem que muda volta: 2 agendamentos dispensados, 3 aparecem", () => {
    const dois = avisosDoInicio(avisos([], { agendamentospassados: 2 }), "2026-10-04");
    const fechado = new Set(dois.flatMap((i) => i.chaves));
    const tres = avisosDoInicio(avisos([], { agendamentospassados: 3 }), "2026-10-04");
    expect(separarDispensados(tres, fechado).visiveis).toHaveLength(1);
  });
  it("mais de três lojas: as que sobram viram uma linha só, e o X dela dispensa todas", () => {
    const lojas = [1, 2, 3, 4, 5].map((n) => ({ lojaid: n, loja: `L${n}` }));
    const itens = avisosDoInicio(avisos(lojas), "2026-10-04");
    const { visiveis } = separarDispensados(itens, new Set(["vendaontem|1|2026-10-03"]));
    expect(visiveis).toHaveLength(1);
    expect(visiveis[0].texto).toContain("4 lojas");
    expect(visiveis[0].chaves).toHaveLength(4);
  });
  it("a linha 'N avisos dispensados' conta os fatos de agora que estão fechados", () => {
    const itens = avisosDoInicio(avisos([CAMPO, CENTRO], { livro: "diferenca" }), "2026-10-04");
    const { dispensados } = separarDispensados(itens, new Set(["vendaontem|1|2026-10-03", "livro|2026-10-04", "livro|2026-10-01"]));
    expect(dispensados).toHaveLength(2);
  });
});
