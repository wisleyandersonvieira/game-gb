// Formato do JSON devolvido por painel_inicio (banco).
export type Meta = { meta: number; vendido: number; percentual: number; lojas: number; lancadas?: number } | null;

export type PainelInicio = {
  hoje: string;
  atualizadoem: string;
  cartoes: {
    tarefas: { total: number; feitas: number; aprovadas: number; emvalidacao: number };
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
