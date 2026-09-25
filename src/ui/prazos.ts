// Por quanto tempo um dado pode ser reaproveitado antes de perguntar de novo.
//
// A regra do Wisley (25/09/2026): dado que muda pouco pode valer minutos;
// dado operacional, 30 segundos; e onde aparece DINHEIRO ou PONTOS, melhor
// esperar meio segundo do que mostrar valor velho.
//
// Onde cada um é usado está no comentário de cada consulta.

/** Cadastro que quase nunca muda: lojas, nome da conta, quem sou eu. */
export const ESTAVEL = 5 * 60_000;

/** Listas de cadastro: equipe, tarefas, prêmios, agenda. Mudam quando você muda. */
export const CADASTRO = 60_000;

/** O dia a dia: fila, quadro, pendências. */
export const OPERACIONAL = 30_000;

/**
 * Dinheiro e pontos: nunca reaproveitar. Além de buscar de novo, o valor
 * antigo é DESCARTADO (gcTime 0), então a tela mostra "carregando" em vez de
 * um número velho por uma fração de segundo.
 */
export const DINHEIRO = { staleTime: 0, gcTime: 0 } as const;
