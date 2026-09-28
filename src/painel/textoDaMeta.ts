// As palavras da meta, UMA vez, para a TV e o Início dizerem o mesmo
// (29/09/2026).

/**
 * "2 dias sem lançamento": dias do mês com meta e sem a venda lançada, até
 * ontem. Esses dias somem da soma do mês, então a falta vai escrita ao lado
 * do número. Zero = nada a dizer.
 */
export function textoDiasSemLancamento(dias: number | null | undefined): string | null {
  if (!dias || dias <= 0) return null;
  return dias === 1 ? "1 dia sem lançamento" : `${dias} dias sem lançamento`;
}
