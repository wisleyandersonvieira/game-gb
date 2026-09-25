// As marcações de quantidade de Solicitações: o número do menu e os das abas
// saem da MESMA resposta do banco. Estes testes provam que eles nunca se
// contradizem — é exatamente a confusão que a linha "2 nesta loja · 3 em
// outras lojas" existe para desfazer.
import { describe, expect, test } from "bun:test";
import { daLoja, montarContagem } from "./pendencias";

describe("contagem de solicitações", () => {
  test("junta as duas situações da mesma loja numa linha só", () => {
    const c = montarContagem([
      { loja: 10, situacao: "Aberta", quantos: 2 },
      { loja: 10, situacao: "Em andamento", quantos: 1 },
    ]);
    expect(c.lojas).toEqual([{ lojaid: 10, abertas: 2, andamento: 1 }]);
    expect(daLoja(c, 10)).toEqual({ abertas: 2, andamento: 1, aResolver: 3 });
  });

  test("o total do menu é a soma de todas as lojas", () => {
    const c = montarContagem([
      { loja: 10, situacao: "Aberta", quantos: 2 },
      { loja: 11, situacao: "Aberta", quantos: 1 },
      { loja: 11, situacao: "Em andamento", quantos: 4 },
    ]);
    expect(c.total).toBe(7);
    // E a conciliação fecha: o que está nesta loja mais o que está nas outras.
    const aqui = daLoja(c, 10).aResolver;
    expect(aqui).toBe(2);
    expect(c.total - aqui).toBe(5);
  });

  test("loja sem nada esperando devolve zeros, não quebra", () => {
    const c = montarContagem([{ loja: 10, situacao: "Aberta", quantos: 2 }]);
    expect(daLoja(c, 99)).toEqual({ abertas: 0, andamento: 0, aResolver: 0 });
    // Aba com zero não mostra número: quem decide isso é o componente, que
    // some quando o número não é positivo.
    expect(daLoja(c, 10).andamento).toBe(0);
  });

  test("situação que não espera ninguém não entra na conta", () => {
    // O banco já filtra, mas se um dia deixar passar, o total não pode inchar.
    const c = montarContagem([
      { loja: 10, situacao: "Aberta", quantos: 2 },
      { loja: 10, situacao: "Concluída", quantos: 500 },
      { loja: 12, situacao: "Recusada", quantos: 300 },
    ]);
    expect(c.total).toBe(2);
    expect(c.lojas).toEqual([{ lojaid: 10, abertas: 2, andamento: 0 }]);
  });

  test("resposta vazia: nenhum número aparece", () => {
    const c = montarContagem([]);
    expect(c.total).toBe(0);
    expect(c.lojas).toEqual([]);
    expect(daLoja(c, 10).aResolver).toBe(0);
  });
});
