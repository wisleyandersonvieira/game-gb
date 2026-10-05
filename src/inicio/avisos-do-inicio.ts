// Os avisos do topo do Início e o X (05/10/2026, decisão do Wisley).
//
// Fechar é por FATO, não por tipo: o X dispensa AQUELE aviso (a loja e o dia
// a que ele se refere). Cada aviso tem a chave do fato; se amanhã faltar a
// venda de outro dia, é outra chave e o aviso volta. Assim dispensar nunca
// esconde um problema novo. O banco guarda as chaves de cada pessoa
// (avisosdispensados); aqui só se monta a lista.
import type { PainelInicio } from "./tipos";

export type Aviso = { texto: string; para: string; grave?: boolean; chaves: string[]; loja?: string };

/** "2026-10-05" - 1 → "2026-10-04" (sem o fuso do aparelho). */
export function diaAnterior(dia: string): string {
  const d = new Date(`${dia}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() - 1);
  return d.toISOString().slice(0, 10);
}

/**
 * "A venda de ontem não foi lançada na Loja X": uma linha por loja; acima de
 * três, uma linha só, resumida. Some sozinho quando a venda é lançada (o
 * banco só manda as lojas que continuam sem lançamento).
 */
export function linhasVendaOntem(lojas: { loja: string }[]): string[] {
  if (lojas.length === 0) return [];
  if (lojas.length <= 3) return lojas.map((l) => `A venda de ontem não foi lançada na ${l.loja}.`);
  const nomes = lojas.slice(0, 3).map((l) => l.loja).join(", ");
  return [`A venda de ontem não foi lançada em ${lojas.length} lojas: ${nomes} e mais ${lojas.length - 3}.`];
}

/** Todos os avisos de agora, cada um com a chave do fato dele. */
export function avisosDoInicio(avisos: PainelInicio["avisos"], hoje: string): Aviso[] {
  if (!avisos) return [];
  const itens: Aviso[] = [];
  const ontem = diaAnterior(hoje);
  // Primeiro: é a equipe que paga pelo esquecimento (a meta não bate e o
  // prêmio não sai), então fica no topo. Uma chave por loja.
  for (const l of avisos.vendaontem ?? []) {
    itens.push({ texto: `A venda de ontem não foi lançada na ${l.loja}.`, para: "/metas", grave: true, chaves: [`vendaontem|${l.lojaid}|${ontem}`], loja: l.loja });
  }
  if (avisos.livro === "diferenca") {
    itens.push({
      texto: "Diferença encontrada entre o saldo e o livro de pontos. Nada foi corrigido: veja os detalhes.",
      para: "/configuracoes",
      grave: true,
      chaves: [`livro|${hoje}`],
    });
  }
  if (avisos.agendamentospassados > 0) {
    const n = avisos.agendamentospassados;
    itens.push({
      texto: `${n} ${n === 1 ? "agendamento já passou e continua" : "agendamentos já passaram e continuam"} como Confirmado.`,
      para: "/agenda",
      chaves: [`agenda|${hoje}|${n}`],
    });
  }
  if (avisos.comunicados24h.comunicados > 0) {
    const c = avisos.comunicados24h;
    itens.push({
      texto: `${c.comunicados} ${c.comunicados === 1 ? "comunicado" : "comunicados"} sem ciência há mais de 24 h (${c.pessoas} ${c.pessoas === 1 ? "pessoa" : "pessoas"}).`,
      para: "/comunicados",
      chaves: [`comunicados|${hoje}|${c.comunicados}|${c.pessoas}`],
    });
  }
  return itens;
}

/**
 * O que aparece e o que foi dispensado. As vendas das lojas que sobraram
 * voltam a virar uma linha só quando passam de três.
 */
export function separarDispensados(itens: Aviso[], dispensados: Set<string>): { visiveis: Aviso[]; dispensados: Aviso[] } {
  const fora = itens.filter((i) => i.chaves.every((c) => dispensados.has(c)));
  const dentro = itens.filter((i) => !i.chaves.every((c) => dispensados.has(c)));
  const vendas = dentro.filter((i) => i.chaves[0].startsWith("vendaontem|"));
  const resto = dentro.filter((i) => !i.chaves[0].startsWith("vendaontem|"));
  let linhasVenda = vendas;
  if (vendas.length > 3) {
    const lojas = vendas.map((v) => ({ loja: v.loja ?? "" }));
    // Uma linha só para todas: o X dela dispensa todas (cada loja é um fato).
    linhasVenda = [{ texto: linhasVendaOntem(lojas)[0], para: "/metas", grave: true, chaves: vendas.flatMap((v) => v.chaves) }];
  }
  return { visiveis: [...linhasVenda, ...resto], dispensados: fora };
}
