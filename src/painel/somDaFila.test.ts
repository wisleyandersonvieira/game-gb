// A conta do "chegou tarefa nova" no tablet.
//
// Vale testar porque o erro aqui é barulhento nos dois sentidos: ou o tablet
// nunca avisa, ou fica tocando a cada 15 segundos com a mesma lista — e aí a
// loja desliga o som e o recurso morre.
import { describe, expect, it } from "bun:test";
import { tarefasNovas } from "./somDaFila";

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
