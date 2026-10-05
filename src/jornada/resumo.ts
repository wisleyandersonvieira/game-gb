// O resumo de uma jornada numa linha, para a lista: dias seguidos com o mesmo
// horário ficam juntos ("Seg–Sex 08:00–17:00 · Sáb 08:00–12:00").
//
// Só HORÁRIO DE EXPEDIENTE. Nada de total de horas nem carga semanal (CLAUDE.md: o STGame não
// controla jornada).

/** 1 = domingo ... 7 = sábado (a convenção do banco e de diadefolga). */
export const DIAS = ["Dom", "Seg", "Ter", "Qua", "Qui", "Sex", "Sáb"] as const;

export type DiaDaJornada = { diasemana: number; entrada: string; saida: string };

const hhmm = (h: string) => h.slice(0, 5);

export function resumoDaJornada(dias: DiaDaJornada[]): string {
  if (dias.length === 0) return "Sem horário em nenhum dia";
  // Segunda primeiro, domingo por último: é como a loja fala da semana.
  const ordem = [2, 3, 4, 5, 6, 7, 1];
  const porDia = new Map(dias.map((d) => [d.diasemana, `${hhmm(d.entrada)}–${hhmm(d.saida)}`]));
  const blocos: { de: number; ate: number; horario: string }[] = [];
  for (const dia of ordem) {
    const h = porDia.get(dia);
    if (!h) continue;
    const ultimo = blocos[blocos.length - 1];
    const anterior = ordem[ordem.indexOf(dia) - 1];
    if (ultimo && ultimo.horario === h && ultimo.ate === anterior) ultimo.ate = dia;
    else blocos.push({ de: dia, ate: dia, horario: h });
  }
  const partes = blocos.map((b) =>
    `${b.de === b.ate ? DIAS[b.de - 1] : `${DIAS[b.de - 1]}–${DIAS[b.ate - 1]}`} ${b.horario}`,
  );
  return partes.join(" · ");
}
