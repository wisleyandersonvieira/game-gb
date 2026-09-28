// O que o tablet diz quando o PIN não passa (29/09/2026, pedido do Wisley).
//
// Desde a trava por pessoa, o tablet sabe QUEM está tentando antes do PIN: o
// dono da tarefa, quem aceitou (na entrega) ou o nome que a pessoa tocou. O
// nome já está na tela, então a mensagem pode dizer a verdade ("Ana S. está de
// folga hoje nesta loja") sem revelar nada que o PIN contaria.
//
// Bloqueado: diz que está bloqueado e quanto falta. Nunca "confira o número",
// que mandava a pessoa digitar de novo o PIN certo.
import type { QuemPode } from "@/painel/QuemPodeAceitar";

export type RespostaDoPin = {
  funcionarioid?: number;
  nome?: string;
  naoeloja?: boolean;
  folga?: boolean;
  sempin?: boolean;
  bloqueado?: boolean;
  pinerrado?: boolean;
  minutos?: number | null;
  erro?: string;
};

const minutos = (m?: number | null) => {
  const n = Math.max(1, Math.round(m ?? 1));
  return `${n} ${n === 1 ? "minuto" : "minutos"}`;
};

/** A frase da recusa, ou null quando o PIN passou. */
export function mensagemDoPin(r: RespostaDoPin): string | null {
  const nome = r.nome || "Esta pessoa";
  if (r.naoeloja) return "Esta pessoa não trabalha nesta loja. Toque no seu nome de novo.";
  if (r.folga) return `${nome} está de folga hoje nesta loja.`;
  if (r.pinerrado && r.bloqueado)
    return `PIN errado. O PIN de ${nome} ficou bloqueado por ${minutos(r.minutos)} (ou peça ao gestor para liberar).`;
  if (r.bloqueado)
    return `O PIN de ${nome} está bloqueado por muitas tentativas. Tente de novo em ${minutos(r.minutos)} (ou peça ao gestor para liberar).`;
  if (r.pinerrado) return `PIN errado para ${nome}${nome.endsWith(".") ? "" : "."} Tente de novo.`;
  if (r.sempin) return `${nome} ainda não tem PIN. Peça ao gestor para cadastrar.`;
  return r.erro ?? null;
}

export type PessoaDaEquipe = { funcionarioid: number; nome: string };

/**
 * Quem aparece na lista "toque no seu nome" de uma tarefa sem dono.
 *
 * A equipe é quem trabalha hoje nesta loja (o banco já tirou quem está de
 * folga). Na compartilhada, só quem a regra do aceite deixa pegar — o mesmo
 * "quem pode aceitar" do ícone do cartão. Na missão da equipe, todos.
 */
export function quemPodeTocar(equipe: PessoaDaEquipe[], podem?: QuemPode): PessoaDaEquipe[] {
  if (!podem || podem.todos) return equipe;
  const nomes = new Set([...podem.pessoas, ...podem.esperando].map((p) => p.nome));
  return equipe.filter((p) => nomes.has(p.nome));
}
