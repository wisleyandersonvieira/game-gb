import { describe, expect, test } from "bun:test";
import { montarMapa, rotuloDaHora, type PessoaDoMapa } from "./mapa";

const pessoa = (p: Partial<PessoaDoMapa>): PessoaDoMapa => ({
  funcionarioid: 1,
  nome: "Pessoa",
  cargo: null,
  situacao: "trabalha",
  afastadoate: null,
  domingofolga: null,
  entrada: null,
  saida: null,
  intervaloinicio: null,
  intervalofim: null,
  ...p,
});

describe("mapa da jornada", () => {
  test("as horas vão da entrada mais cedo até a saída mais tarde", () => {
    const m = montarMapa([
      pessoa({ entrada: "10:00", saida: "18:00" }),
      pessoa({ entrada: "14:00", saida: "23:00" }),
      pessoa({ situacao: "folga" }),
    ]);
    expect(m.horas.map(rotuloDaHora)).toEqual(
      ["10h", "11h", "12h", "13h", "14h", "15h", "16h", "17h", "18h", "19h", "20h", "21h", "22h"],
    );
    expect(m.totais).toEqual([1, 1, 1, 1, 2, 2, 2, 2, 1, 1, 1, 1, 1]);
    expect(m.linhas[2].celulas).toBeNull();
    expect(m.linhas[2].aviso).toBe("folga");
  });

  test("o intervalo do mapa tira a pessoa do total naquela hora", () => {
    const m = montarMapa([pessoa({ entrada: "10:00", saida: "18:00", intervaloinicio: "14:00", intervalofim: "15:00" })]);
    expect(m.linhas[0].celulas?.[4]).toEqual({ tipo: "intervalo" });
    expect(m.totais[4]).toBe(0);
    expect(m.totais[5]).toBe(1);
  });

  test("a hora parcial mostra o horário; conta quem está pelo menos metade da hora", () => {
    const m = montarMapa([pessoa({ entrada: "10:20", saida: "17:40" })]);
    expect(m.linhas[0].celulas?.[0]).toEqual({ tipo: "parcial", hora: "10:20" });
    expect(m.linhas[0].celulas?.at(-1)).toEqual({ tipo: "parcial", hora: "17:40" });
    expect(m.totais[0]).toBe(1); // 40 minutos nas 10h
    expect(m.totais.at(-1)).toBe(1); // 40 minutos nas 17h
    const pouco = montarMapa([pessoa({ entrada: "10:40", saida: "17:20" })]);
    expect(pouco.totais[0]).toBe(0); // 20 minutos
    expect(pouco.totais.at(-1)).toBe(0);
  });

  test("caso do Wisley 1: a equipe inteira entrando às 10h30 — o total das 10h não é zero", () => {
    const equipe = [1, 2, 3, 4].map((id) => pessoa({ funcionarioid: id, entrada: "10:30", saida: "18:30" }));
    const m = montarMapa(equipe);
    expect(rotuloDaHora(m.horas[0])).toBe("10h");
    expect(m.linhas[0].celulas?.[0]).toEqual({ tipo: "parcial", hora: "10:30" });
    expect(m.totais[0]).toBe(4);
    // Meia hora exata é empate: a primeira metade (sai 18:30) não conta.
    expect(m.totais.at(-1)).toBe(0);
  });

  test("caso do Wisley 2: intervalo das 14h30 às 15h30 tira a pessoa de UMA hora só", () => {
    const m = montarMapa([pessoa({ entrada: "10:00", saida: "18:00", intervaloinicio: "14:30", intervalofim: "15:30" })]);
    const h = m.horas.map(rotuloDaHora);
    expect(m.linhas[0].celulas?.[h.indexOf("14h")]).toEqual({ tipo: "intervalo" });
    expect(m.linhas[0].celulas?.[h.indexOf("15h")]).toEqual({ tipo: "intervalo" });
    expect(m.totais.filter((t) => t === 0).length).toBe(1);
    expect(m.totais[h.indexOf("14h")]).toBe(0);
    expect(m.totais[h.indexOf("15h")]).toBe(1);
  });

  test("intervalo curto não tira da hora; o longo tira", () => {
    const m = montarMapa([pessoa({ entrada: "10:00", saida: "18:00", intervaloinicio: "14:00", intervalofim: "14:20" })]);
    expect(m.totais[4]).toBe(1);
    const longo = montarMapa([pessoa({ entrada: "10:00", saida: "18:00", intervaloinicio: "14:00", intervalofim: "14:40" })]);
    expect(longo.totais[4]).toBe(0);
  });

  test("turno da noite passa da meia-noite, com o intervalo do outro lado", () => {
    const m = montarMapa([
      pessoa({ entrada: "22:00", saida: "06:00", intervaloinicio: "02:00", intervalofim: "03:00" }),
      pessoa({ entrada: "18:00", saida: "23:00" }),
    ]);
    expect(m.horas.map(rotuloDaHora)).toEqual(
      ["18h", "19h", "20h", "21h", "22h", "23h", "00h", "01h", "02h", "03h", "04h", "05h"],
    );
    expect(m.linhas[0].celulas?.[8]).toEqual({ tipo: "intervalo" });
    expect(m.totais).toEqual([1, 1, 1, 1, 2, 1, 1, 1, 0, 1, 1, 1]);
  });

  test("intervalo fora do expediente do dia não marca nada e avisa", () => {
    const m = montarMapa([pessoa({ entrada: "10:00", saida: "14:00", intervaloinicio: "19:00", intervalofim: "20:00" })]);
    expect(m.linhas[0].intervaloFora).toBe(true);
    expect(m.totais).toEqual([1, 1, 1, 1]);
  });

  test("ninguém trabalhando: sem colunas", () => {
    const m = montarMapa([pessoa({ situacao: "sem_jornada" }), pessoa({ situacao: "afastado", afastadoate: "2026-10-05" })]);
    expect(m.horas).toEqual([]);
    expect(m.linhas.map((l) => l.aviso)).toEqual(["sem jornada", "afastado até 05/10/2026"]);
  });
});
