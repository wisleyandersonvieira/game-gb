// A conta do "apareceu versão nova". Vale a pena testar porque o erro aqui é
// silencioso nos dois sentidos: ou ninguém nunca vê o aviso, ou todo mundo vê
// para sempre.
import { expect, test } from "bun:test";
import { temVersaoNova } from "./VersaoNova";
import { versaoEmTexto } from "./versao";

const antiga = { commit: "a30d6e0", em: "2026-09-25T14:00:00.000Z" };
const nova = { commit: "b111111", em: "2026-09-25T15:00:00.000Z" };

test("publicaram uma versão mais nova: avisa", () => {
  expect(temVersaoNova(antiga, nova)).toBe(true);
});

test("mesma versão: não avisa", () => {
  expect(temVersaoNova(antiga, antiga)).toBe(false);
});

test("voltaram para uma versão antiga: não manda ninguém atualizar para trás", () => {
  expect(temVersaoNova(nova, antiga)).toBe(false);
});

test("em desenvolvimento (sem build) não há o que comparar", () => {
  expect(temVersaoNova({ commit: "desenvolvimento", em: "" }, nova)).toBe(false);
});

test("hospedagem sem o commit: a hora ainda decide", () => {
  expect(temVersaoNova({ commit: "desconhecido", em: antiga.em }, { commit: "desconhecido", em: nova.em })).toBe(true);
});

test("o texto da versão mostra commit e data", () => {
  expect(versaoEmTexto(antiga)).toContain("a30d6e0");
  expect(versaoEmTexto(antiga)).toContain("25/09/2026");
});
