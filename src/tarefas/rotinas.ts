// Quais rotinas automáticas usam uma tarefa (28/09/2026).
//
// As 6 tarefas que o sistema cria para cada conta viraram tarefas comuns, mas
// duas delas continuam sendo usadas por rotinas. As rotinas as acham pelo
// CÓDIGO interno (tarefas.sistema), que nunca muda — nunca pelo nome. Por
// isso renomear não quebra nada; desativar, sim, e a tela avisa antes.
//
// Conferido no banco, função por função: só criar_agendamento e
// publicar_comunicado leem essas tarefas. As outras quatro (feedback diário,
// pontos da meta, nota fiscal, guardar mercadoria) não são usadas por rotina
// nenhuma hoje. Se uma rotina nova passar a usar uma tarefa, ela entra aqui.

export type Rotina = {
  /** Quem usa a tarefa. */
  rotina: string;
  /** O que deixa de funcionar se ela for desativada. */
  aoDesativar: string;
  /** O que acontece com os pontos dela. */
  pontos: (pontos: number) => string;
};

export const ROTINAS_POR_CODIGO: Record<string, Rotina> = {
  modelo_agendamento: {
    rotina: "Agenda: cada agendamento novo cria esta tarefa para o responsável, no dia do evento.",
    aoDesativar:
      "Os agendamentos novos deixam de criar a tarefa de atender para o responsável. O agendamento é criado mesmo assim, e um aviso aparece no Início e na Saúde a cada vez.",
    pontos: (p) =>
      `Os ${p} pontos são pagos quando o responsável entrega e a entrega é aprovada, como em qualquer tarefa. Nada é pago sozinho.`,
  },
  leitura: {
    rotina:
      "Comunicados: os pontos desta tarefa são o padrão de pontos por ciência dos comunicados novos (quando o campo de pontos fica em branco).",
    aoDesativar:
      "Os comunicados novos publicados com o campo de pontos em branco passam a valer 0 ponto por ciência, e um aviso aparece no Início e na Saúde a cada vez. Os comunicados já publicados não mudam.",
    pontos: (p) =>
      p > 0
        ? `ATENÇÃO: com ${p} pontos, cada ciência de um comunicado novo publicado com o campo de pontos em branco paga ${p} pontos AUTOMATICAMENTE, sem validação. Os comunicados já publicados não mudam.`
        : "Com 0 ponto, a ciência dos comunicados novos (com o campo em branco) não paga nada.",
  },
};

export const rotinaDaTarefa = (codigo: string | null | undefined) => (codigo ? ROTINAS_POR_CODIGO[codigo] : undefined);
