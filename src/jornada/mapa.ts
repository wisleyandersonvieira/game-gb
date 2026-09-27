// A grade do Mapa da jornada: de hora em hora, quem está em expediente.
//
// É PLANEJAMENTO, montado só com o cadastro (jornada, folga e o intervalo do
// mapa). Não olha a hora de agora nem marca nada: o STGame não controla
// jornada (CLAUDE.md).
//
// Regras de cada célula (a hora "14h" vai de 14:00 a 14:59):
//   * vazia      — fora do expediente;
//   * intervalo  — o intervalo do mapa pega parte dessa hora;
//   * expediente — a hora inteira dentro do expediente, fora do intervalo;
//   * parcial    — entra ou sai no meio da hora (mostra a hora de entrada ou
//                  de saída).
// O TOTAL (29/09/2026, duas regras do Wisley, uma frase cada — as mesmas da
// legenda e do rodapé do PDF, em REGRAS_DO_TOTAL):
//   * Presença: a pessoa conta na hora em que estiver presente pelo menos 30
//     minutos, contando os 30 exatos. (Entra 10h30: conta nas 10h. Sai
//     17h30: conta nas 17h.)
//   * Intervalo: o intervalo tira a pessoa da hora em que ele começa, e só
//     dela. (Intervalo 14h30–15h30: sai só das 14h.)
// As células não mudam; muda só a conta.
//
// O turno é do dia em que começa: saída menor que a entrada vai até o dia
// seguinte, e as colunas passam da meia-noite (00h, 01h...).

export type Situacao = "trabalha" | "folga" | "afastado" | "sem_jornada" | "sem_horario";

export type PessoaDoMapa = {
  funcionarioid: number;
  nome: string;
  cargo: string | null;
  situacao: Situacao;
  afastadoate: string | null;
  domingofolga: number | null;
  entrada: string | null;
  saida: string | null;
  intervaloinicio: string | null;
  intervalofim: string | null;
};

export type Celula =
  | { tipo: "vazio" }
  | { tipo: "expediente" }
  | { tipo: "parcial"; hora: string }
  | { tipo: "intervalo" };

export type LinhaDoMapa = {
  pessoa: PessoaDoMapa;
  /** null = sem expediente neste dia (folga, afastado, sem horário). */
  celulas: Celula[] | null;
  /** O que aparece na linha no lugar das horas ("folga"...), ou um lembrete. */
  aviso: string | null;
  /** Em quais horas a pessoa entra no total (vazio sem expediente). */
  contaEm: boolean[];
  /** O intervalo do mapa não cai no expediente deste dia. */
  intervaloFora: boolean;
};

export type Mapa = { horas: number[]; linhas: LinhaDoMapa[]; totais: number[] };

/** Minutos de presença na hora que começa em h0 (expediente menos intervalo). */
function contaNaHora(e: [number, number], int: [number, number] | null, h0: number) {
  // Intervalo: só a hora em que ele COMEÇA (o começo já cortado ao expediente).
  if (int && Math.floor(int[0] / 60) * 60 === h0) return false;
  // Presença: 30 minutos ou mais do expediente nesta hora.
  return sobreposicao(e[0], e[1], h0, h0 + 60) >= 30;
}

/** O aviso da tela Jornada, palavra por palavra. */
export const AVISO_DA_JORNADA =
  "Estes horários servem para o sistema saber quando enviar tarefas e avisos. O STGame não registra ponto nem controla jornada.";

/** As duas regras do total, uma frase cada: na legenda e no rodapé do PDF. */
export const REGRAS_DO_TOTAL = [
  "Presença: a pessoa conta na hora em que estiver presente pelo menos 30 minutos, contando os 30 exatos.",
  "Intervalo: o intervalo tira a pessoa da hora em que ele começa, e só dela.",
];

export const LEGENDA_DO_MAPA = [
  "X = em expediente a hora inteira.",
  "••• = Intervalo (planejamento, não afeta o sistema).",
  "10:30 = entra ou sai no meio da hora.",
  ...REGRAS_DO_TOTAL,
  "O turno da noite fica no dia em que começa.",
];

const DIA = 24 * 60;

export function minutos(hhmm: string) {
  const [h, m] = hhmm.split(":").map(Number);
  return h * 60 + m;
}

/** 870 -> "14:30"; passa da meia-noite sem mudar o jeito de escrever. */
export function horaEscrita(min: number) {
  const m = ((min % DIA) + DIA) % DIA;
  return `${String(Math.floor(m / 60)).padStart(2, "0")}:${String(m % 60).padStart(2, "0")}`;
}

/** 25 -> "01h". */
export const rotuloDaHora = (h: number) => `${String(h % 24).padStart(2, "0")}h`;

const sobreposicao = (a0: number, a1: number, b0: number, b1: number) => Math.max(0, Math.min(a1, b1) - Math.max(a0, b0));

/** O expediente em minutos desde a meia-noite do dia em que começa. */
function expediente(p: PessoaDoMapa): [number, number] | null {
  if (p.situacao !== "trabalha" || !p.entrada || !p.saida) return null;
  const e0 = minutos(p.entrada);
  let e1 = minutos(p.saida);
  if (e1 <= e0) e1 += DIA;
  return [e0, e1];
}

/**
 * O intervalo do mapa dentro do expediente (ou null). Como na jornada: um
 * intervalo antes da entrada é do dia seguinte (turno da noite, 02h).
 */
function intervalo(p: PessoaDoMapa, e: [number, number]): [number, number] | null {
  if (!p.intervaloinicio || !p.intervalofim) return null;
  const desloca = minutos(p.intervaloinicio) < e[0] ? DIA : 0;
  const i0 = minutos(p.intervaloinicio) + desloca;
  let i1 = minutos(p.intervalofim) + desloca;
  if (i1 <= i0) i1 += DIA;
  const c0 = Math.max(i0, e[0]);
  const c1 = Math.min(i1, e[1]);
  return c1 > c0 ? [c0, c1] : null;
}

const DIAS_ORDINAIS = ["", "1º", "2º", "3º", "4º", "5º"];

function avisoSemHoras(p: PessoaDoMapa): string {
  switch (p.situacao) {
    case "folga":
      return "folga";
    case "afastado":
      return p.afastadoate
        ? `afastado até ${p.afastadoate.slice(8, 10)}/${p.afastadoate.slice(5, 7)}/${p.afastadoate.slice(0, 4)}`
        : "afastado";
    case "sem_jornada":
      return "sem jornada";
    default:
      return "sem horário neste dia";
  }
}

export function montarMapa(pessoas: PessoaDoMapa[]): Mapa {
  const expedientes = pessoas.map(expediente);
  const comHorario = expedientes.filter((e): e is [number, number] => e !== null);
  const horas: number[] = [];
  if (comHorario.length > 0) {
    const primeira = Math.floor(Math.min(...comHorario.map((e) => e[0])) / 60);
    const ultima = Math.ceil(Math.max(...comHorario.map((e) => e[1])) / 60);
    for (let h = primeira; h < ultima; h++) horas.push(h);
  }

  const linhas: LinhaDoMapa[] = pessoas.map((p, i) => {
    const e = expedientes[i];
    if (!e) return { pessoa: p, celulas: null, contaEm: [], aviso: avisoSemHoras(p), intervaloFora: false };
    const int = intervalo(p, e);
    const celulas = horas.map<Celula>((h) => {
      const h0 = h * 60;
      const h1 = h0 + 60;
      const dentro = sobreposicao(e[0], e[1], h0, h1);
      if (dentro === 0) return { tipo: "vazio" };
      if (int && sobreposicao(int[0], int[1], h0, h1) > 0) return { tipo: "intervalo" };
      if (dentro === 60) return { tipo: "expediente" };
      return { tipo: "parcial", hora: horaEscrita(e[0] > h0 ? e[0] : e[1]) };
    });
    const domingo = p.domingofolga ? `folga no ${DIAS_ORDINAIS[p.domingofolga] ?? `${p.domingofolga}º`} domingo do mês` : null;
    return {
      pessoa: p,
      celulas,
      contaEm: horas.map((h) => contaNaHora(e, int, h * 60)),
      aviso: domingo,
      intervaloFora: !!p.intervaloinicio && !int,
    };
  });

  const totais = horas.map((_, c) => linhas.filter((l) => l.contaEm[c]).length);
  return { horas, linhas, totais };
}
