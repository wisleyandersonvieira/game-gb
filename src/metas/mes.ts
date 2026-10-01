// A meta do mês, dia a dia (30/09/2026): as contas da tela, sem React, para
// o teste provar cada regra (bun test src/metas).
//
// De onde vem a meta de um dia (quem decide é o banco, meta_do_dia):
//   1º a meta especial daquela data; 2º a meta daquele dia naquele mês;
//   3º o modelo do dia da semana.
// Dia já lançado guarda a meta que tinha: nunca se edita. Dia com meta
// especial: só na aba Metas especiais.

export type Origem = "especial" | "mes" | "semana";

/** Um dia do mês, como o banco manda (metas_do_mes_por_dia). */
export type DiaDoMes = {
  dia: string; // aaaa-mm-dd
  lancado: boolean;
  origem: Origem | null;
  meta: number | null;
  pontos: number | null;
  descricao: string | null;
  modelo: number | null;
  modelopontos: number | null;
};

/** O que a pessoa digitou (ainda não salvo), por dia. */
export type Campos = { valor: string; pontos: string };
export type Rascunho = Record<string, Campos>;

/** Os sete campos do Replicar, de domingo (0) a sábado (6). */
export type Semana = Campos[];

export const DIAS_DA_SEMANA = ["Domingo", "Segunda", "Terça", "Quarta", "Quinta", "Sexta", "Sábado"];

/** 0 = domingo ... 6 = sábado, sem depender do fuso do aparelho. */
export const diaDaSemana = (iso: string) => new Date(`${iso}T12:00:00Z`).getUTCDay();

/** "1.234,56" → 1234.56; vazio → NaN. */
export function numero(t: string): number {
  const s = t.trim();
  if (s === "") return Number.NaN;
  return Number(s.replace(/\./g, "").replace(",", "."));
}

/** 1234.5 → "1234,5" (o jeito de escrever no campo). */
export const noCampo = (v: number | null | undefined) => (v === null || v === undefined ? "" : String(v).replace(".", ","));

/** Só dia não lançado e sem meta especial se edita aqui. */
export const editavel = (d: DiaDoMes) => !d.lancado && d.origem !== "especial";

/** O que está salvo para o dia nesta tabela: só a meta "deste mês" (o resto é de outro lugar). */
export function salvo(d: DiaDoMes): Campos {
  return d.origem === "mes" && !d.lancado ? { valor: noCampo(d.meta), pontos: noCampo(d.pontos) } : { valor: "", pontos: "" };
}

/** O que o campo mostra: o que foi digitado, senão o que está salvo. */
export const naTela = (d: DiaDoMes, r: Rascunho): Campos => r[d.dia] ?? salvo(d);

/** De onde vem o valor que a tabela mostra, em palavras. */
export function deOndeVem(d: DiaDoMes, r: Rascunho): "já lançado" | "especial" | "deste mês" | "do modelo" {
  if (d.lancado) return "já lançado";
  if (d.origem === "especial") return "especial";
  return naTela(d, r).valor.trim() !== "" ? "deste mês" : "do modelo";
}

/**
 * O botão Replicar: preenche cada dia com o valor do dia da semana dele.
 * Por padrão SÓ os dias em branco (que seguem o modelo); com "substituir",
 * também os que já têm valor deste mês. NUNCA dia lançado nem com especial.
 * Dia da semana com o campo vazio não mexe em nada.
 */
export function replicar(dias: DiaDoMes[], r: Rascunho, semana: Semana, substituir: boolean): { rascunho: Rascunho; mudou: number } {
  const novo: Rascunho = { ...r };
  let mudou = 0;
  for (const d of dias) {
    if (!editavel(d)) continue;
    const s = semana[diaDaSemana(d.dia)];
    if (!s || s.valor.trim() === "") continue;
    const atual = naTela(d, novo);
    if (atual.valor.trim() !== "" && !substituir) continue;
    const pontos = s.pontos.trim() === "" ? "0" : s.pontos.trim();
    if (atual.valor === s.valor.trim() && atual.pontos === pontos) continue;
    novo[d.dia] = { valor: s.valor.trim(), pontos };
    mudou++;
  }
  return { rascunho: novo, mudou };
}

export type Linha = { dia: string; valormeta: number | null; pontospremio: number | null };

/**
 * O que vai para o banco: só os dias que mudaram. Valor vazio = o dia volta
 * ao modelo. Devolve também os erros, por dia, para a tela mostrar sem
 * perder nada do que foi digitado.
 */
export function mudancas(dias: DiaDoMes[], r: Rascunho): { linhas: Linha[]; erros: Record<string, string> } {
  const linhas: Linha[] = [];
  const erros: Record<string, string> = {};
  for (const d of dias) {
    const c = r[d.dia];
    if (!c || !editavel(d)) continue;
    const antes = salvo(d);
    if (c.valor.trim() === antes.valor.trim() && c.pontos.trim() === antes.pontos.trim()) continue;
    if (c.valor.trim() === "") {
      if (antes.valor.trim() !== "") linhas.push({ dia: d.dia, valormeta: null, pontospremio: null });
      continue;
    }
    const v = numero(c.valor);
    const p = c.pontos.trim() === "" ? Number.NaN : Number(c.pontos.trim());
    if (!(v >= 0) || v >= 1e9) erros[d.dia] = "meta inválida";
    else if (!Number.isInteger(p) || p < 0 || p > 10000) erros[d.dia] = "pontos: um número inteiro de 0 a 10.000";
    else linhas.push({ dia: d.dia, valormeta: v, pontospremio: p });
  }
  return { linhas, erros };
}

/** Tem alguma coisa digitada que ainda não foi salva? */
export const temAlteracao = (dias: DiaDoMes[], r: Rascunho) => {
  const { linhas, erros } = mudancas(dias, r);
  return linhas.length > 0 || Object.keys(erros).length > 0;
};

/** "2026-10" + 1 → "2026-11". */
export function somarMes(mes: string, n: number): string {
  const [a, m] = mes.split("-").map(Number);
  const t = a * 12 + (m - 1) + n;
  return `${Math.floor(t / 12)}-${String((t % 12) + 1).padStart(2, "0")}`;
}

/** "2026-10" → "outubro de 2026". */
export function nomeDoMes(mes: string): string {
  return new Intl.DateTimeFormat("pt-BR", { month: "long", year: "numeric", timeZone: "UTC" }).format(
    new Date(`${mes}-15T12:00:00Z`),
  );
}
