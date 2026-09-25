// A conta do "chegou tarefa nova" no tablet.
//
// Vale testar porque o erro aqui é barulhento nos dois sentidos: ou o tablet
// nunca avisa, ou fica tocando a cada 15 segundos com a mesma lista — e aí a
// loja desliga o som e o recurso morre.
import { describe, expect, it } from "bun:test";
import { decidirRepeticao, MAX_REPETICOES, NIVEIS, SEM_REPETICAO, tarefasNovas, type EstadoRepeticao } from "./somDaFila";

describe("quais tarefas são novas na fila", () => {
  it("na primeira carga, nada é novo (o tablet não toca ao ligar)", () => {
    expect(tarefasNovas(null, [1, 2, 3])).toEqual([]);
  });

  it("a mesma lista de novo não é nova", () => {
    expect(tarefasNovas([1, 2, 3], [1, 2, 3])).toEqual([]);
  });

  it("a mesma lista fora de ordem também não é nova", () => {
    expect(tarefasNovas([1, 2, 3], [3, 1, 2])).toEqual([]);
  });

  it("acha a que chegou", () => {
    expect(tarefasNovas([1, 2], [1, 2, 7])).toEqual([7]);
  });

  it("tarefa que SAIU da fila não conta como nova", () => {
    expect(tarefasNovas([1, 2, 3], [1, 3])).toEqual([]);
  });

  it("várias juntas: devolve todas, e quem toca decide tocar uma vez só", () => {
    expect(tarefasNovas([1], [1, 8, 9])).toEqual([8, 9]);
  });

  it("a fila que esvaziou e voltou conta como nova", () => {
    // É o caso do horário de liberação: a tarefa some da lista de pegar
    // enquanto não liberou, e entra quando chega a hora.
    expect(tarefasNovas([], [5])).toEqual([5]);
  });
});

// ---------------------------------------------------------------------------
// A REPETIÇÃO do aviso enquanto ninguém aceita.
//
// Aqui o erro custa caro nos dois sentidos: ou a tarefa fica parada sem
// ninguém ser avisado, ou o tablet vira alarme e a loja desliga o som — e aí
// o recurso morre inteiro. Por isso as três regras que o Wisley pediu por
// escrito têm teste próprio: para no aceite, no máximo 3 por tarefa, e cinco
// tarefas paradas não geram cinco sons.
// ---------------------------------------------------------------------------

const MIN = 60_000;
/** Tarefa que ficou disponível há tantos minutos. */
function parada(id: number, minutosAtras: number, agora: number) {
  return { atribuicaoid: id, disponiveldesde: new Date(agora - minutosAtras * MIN).toISOString() };
}

/** Roda a decisão e devolve o estado, como o tablet faz a cada resposta. */
function rodada(
  estado: EstadoRepeticao,
  agora: number,
  paradas: { atribuicaoid: number; disponiveldesde: string | null }[],
  intervaloMinutos = 5,
  marcarSemTocar = false,
) {
  return decidirRepeticao({ agora, paradas, intervaloMinutos, estado, marcarSemTocar });
}

describe("repetição do aviso no tablet", () => {
  const T0 = Date.parse("2026-09-25T12:00:00.000Z");

  it("na primeira carga não toca, só anota onde a tarefa está", () => {
    // O tablet abriu com uma tarefa parada há meia hora: não pode despejar
    // três toques porque alguém acordou a tela.
    const r = rodada(SEM_REPETICAO, T0, [parada(1, 30, T0)], 5, true);
    expect(r.tocar).toBe(false);
    expect(r.estado.tocadas[1]).toBe(MAX_REPETICOES);
  });

  it("toca quando vence o primeiro intervalo", () => {
    let e = rodada(SEM_REPETICAO, T0, [parada(1, 0, T0)], 5, true).estado;
    // 4 minutos: ainda não.
    let r = rodada(e, T0 + 4 * MIN, [parada(1, 4, T0 + 4 * MIN)]);
    expect(r.tocar).toBe(false);
    e = r.estado;
    // 5 minutos: toca.
    r = rodada(e, T0 + 5 * MIN, [parada(1, 5, T0 + 5 * MIN)]);
    expect(r.tocar).toBe(true);
    expect(r.estado.tocadas[1]).toBe(1);
  });

  it("PARA quando a tarefa é aceita", () => {
    let e = rodada(SEM_REPETICAO, T0, [parada(1, 0, T0)], 5, true).estado;
    e = rodada(e, T0 + 5 * MIN, [parada(1, 5, T0 + 5 * MIN)]).estado;
    // Alguém aceitou: a tarefa sai da lista de paradas.
    const r = rodada(e, T0 + 10 * MIN, []);
    expect(r.tocar).toBe(false);
    expect(r.estado.tocadas).toEqual({});
    // E na rodada seguinte, com a lista ainda vazia, continua em silêncio.
    expect(rodada(r.estado, T0 + 60 * MIN, []).tocar).toBe(false);
  });

  it("no máximo 3 repetições por tarefa, depois silêncio", () => {
    let e = rodada(SEM_REPETICAO, T0, [parada(1, 0, T0)], 5, true).estado;
    const tocou: number[] = [];
    // Duas horas de tablet aberto, olhando a cada 5 minutos.
    for (let m = 5; m <= 120; m += 5) {
      const agora = T0 + m * MIN;
      const r = rodada(e, agora, [parada(1, m, agora)]);
      if (r.tocar) tocou.push(m);
      e = r.estado;
    }
    expect(tocou).toEqual([5, 10, 15]);
    expect(e.tocadas[1]).toBe(MAX_REPETICOES);
  });

  it("cinco tarefas paradas geram UM som, não cinco", () => {
    const cinco = (agora: number, m: number) => [1, 2, 3, 4, 5].map((i) => parada(i, m, agora));
    let e = rodada(SEM_REPETICAO, T0, cinco(T0, 0), 5, true).estado;
    const agora = T0 + 5 * MIN;
    const r = rodada(e, agora, cinco(agora, 5));
    expect(r.tocar).toBe(true);
    // Todas as cinco ficaram marcadas na MESMA rodada: a próxima olhada não
    // arranca outro som por causa das que "faltaram".
    expect(r.estado.tocadas).toEqual({ 1: 1, 2: 1, 3: 1, 4: 1, 5: 1 });
    e = r.estado;
    // Olhando de novo 15 segundos depois — é o ritmo real da fila — silêncio.
    expect(rodada(e, agora + 15_000, cinco(agora + 15_000, 5)).tocar).toBe(false);
    // Total de sons nas duas horas seguintes: 3, e não 15.
    let sons = 1;
    for (let m = 10; m <= 120; m += 5) {
      const t = T0 + m * MIN;
      const r2 = rodada(e, t, cinco(t, m));
      if (r2.tocar) sons++;
      e = r2.estado;
    }
    expect(sons).toBe(MAX_REPETICOES);
  });

  it("tarefas que vencem em momentos diferentes respeitam o intervalo", () => {
    // A tarefa 1 entrou às 12h00 e a 2 às 12h03. Sem o intervalo mínimo
    // global, daria som às 12h05 e outro às 12h08.
    let e = rodada(SEM_REPETICAO, T0, [parada(1, 0, T0)], 5, true).estado;
    const lista = [
      { atribuicaoid: 1, disponiveldesde: new Date(T0).toISOString() },
      { atribuicaoid: 2, disponiveldesde: new Date(T0 + 3 * MIN).toISOString() },
    ];
    let r = rodada(e, T0 + 5 * MIN, lista);
    expect(r.tocar).toBe(true);
    e = r.estado;
    r = rodada(e, T0 + 8 * MIN, lista);
    expect(r.tocar).toBe(false);
  });

  it("repetição desligada: nunca toca", () => {
    let e = SEM_REPETICAO;
    for (let m = 0; m <= 120; m += 5) {
      const agora = T0 + m * MIN;
      const r = rodada(e, agora, [parada(1, m, agora)], 0);
      expect(r.tocar).toBe(false);
      e = r.estado;
    }
  });

  it("intervalo menor que 5 minutos é tratado como 5", () => {
    // O banco não aceita menos que 5, mas se algum dia aceitar, a tela não
    // vira alarme.
    let e = rodada(SEM_REPETICAO, T0, [parada(1, 0, T0)], 1, true).estado;
    expect(rodada(e, T0 + 2 * MIN, [parada(1, 2, T0 + 2 * MIN)], 1).tocar).toBe(false);
    expect(rodada(e, T0 + 5 * MIN, [parada(1, 5, T0 + 5 * MIN)], 1).tocar).toBe(true);
  });

  it("tarefa sem hora de disponibilidade não conta", () => {
    const r = rodada(SEM_REPETICAO, T0, [{ atribuicaoid: 1, disponiveldesde: null }]);
    expect(r.tocar).toBe(false);
  });
});

describe("os três níveis de volume", () => {
  it("nunca passam de 100: o ganho só abaixa, nunca amplifica", () => {
    for (const v of Object.values(NIVEIS)) {
      expect(v).toBeGreaterThan(0);
      expect(v).toBeLessThanOrEqual(100);
    }
  });

  it("estão em ordem, e o médio é o que a migração grava", () => {
    expect(NIVEIS.baixo).toBeLessThan(NIVEIS.medio);
    expect(NIVEIS.medio).toBeLessThan(NIVEIS.alto);
    // 50 (o padrão antigo) x 1,5 / 4,0046 = 18,7, que arredonda para 19.
    expect(NIVEIS.medio).toBe(Math.round((50 * 1.5) / 4.0046));
  });
});
