// Formato do JSON devolvido por painel_inicio (banco).
export type Meta = { meta: number; vendido: number; percentual: number; lojas: number; lancadas?: number } | null;

export type PainelInicio = {
  hoje: string;
  atualizadoem: string;
  cartoes: {
    /**
     * A MESMA conta da barra da TV (progresso_da_fila). "Concluídas" = só as
     * aprovadas; o que espera o gestor fica à parte. O percentual vem pronto.
     */
    tarefas: {
      total: number;
      aprovadas: number;
      emvalidacao: number;
      emandamento: number;
      parafazer: number;
      aindanaoliberadas: number;
      percentual: number;
    };
    metadia: Meta;
    metames: Meta;
    validar: number;
    agendahoje: number;
    comunicados: { comunicados: number; pessoas: number };
    onboarding: number;
    solicitacoes: number;
    justificativas: number;
  };
  vendas: { dia: string; vendido: number | null; meta: number | null }[];
  pontos: { semana: string; entraram: number; sairam: number }[];
  entregas: { semana: string; aprovadas: number; recusadas: number }[];
  ranking: { nome: string; pontos: number; entregas: number }[];
  agenda: { quando: string; tipo: string; responsavel: string | null; loja: string }[];
  validar: { titulo: string; pessoa: string; pontos: number; enviadaem: string; loja: string }[];
  guia: { loja: boolean; equipe: boolean; tarefas: boolean; meta: boolean; tv: boolean };
  avisos?: {
    agendamentospassados: number;
    comunicados24h: { comunicados: number; pessoas: number };
    livro: "ok" | "diferenca" | "erro" | null;
    /** Lojas que tinham meta ontem e ficaram sem a venda lançada. */
    vendaontem?: { lojaid: number; loja: string }[];
  };
  rotina?: { quando: string; resultado: "ok" | "erro"; origem: string } | null;
};

export const FUSO = "America/Sao_Paulo";

export const reais = (v: number) => new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(v);
export const reaisCurto = (v: number) =>
  new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL", notation: "compact", maximumFractionDigits: 1 }).format(v);
export const diaMes = (iso: string) => `${iso.slice(8, 10)}/${iso.slice(5, 7)}`;
export const pct = (v: number) => `${v.toLocaleString("pt-BR", { maximumFractionDigits: 1 })}%`;

export function quando(iso: string, hoje: string) {
  const d = new Date(iso);
  const dia = new Intl.DateTimeFormat("en-CA", { timeZone: FUSO }).format(d);
  const hora = d.toLocaleTimeString("pt-BR", { timeZone: FUSO, hour: "2-digit", minute: "2-digit" });
  if (dia === hoje) return `Hoje, ${hora}`;
  return `${diaMes(dia)}, ${hora}`;
}

/**
 * Meta do dia sem a venda lançada (em nenhuma loja, ou só em parte delas):
 * o texto que substitui o percentual. null = pode mostrar o número.
 */
export function textoSemLancamento(meta: NonNullable<Meta>): string | null {
  if (meta.lancadas === undefined) return null; // a meta do mês não tem lançamento por dia
  if (meta.lancadas === 0) return "venda de hoje ainda não lançada";
  if (meta.lancadas < meta.lojas) return `venda de hoje lançada em ${meta.lancadas} de ${meta.lojas} lojas`;
  return null;
}
