import { describe, expect, it } from "bun:test";
import { resumoDaJornada } from "./resumo";

const d = (diasemana: number, entrada: string, saida: string) => ({ diasemana, entrada: `${entrada}:00`, saida: `${saida}:00` });

describe("resumo da jornada", () => {
  it("dias seguidos iguais ficam juntos", () => {
    const dias = [2, 3, 4, 5, 6].map((n) => d(n, "08:00", "17:00")).concat(d(7, "08:00", "12:00"));
    expect(resumoDaJornada(dias)).toBe("Seg–Sex 08:00–17:00 · Sáb 08:00–12:00");
  });
  it("os sete dias iguais: Seg–Dom", () => {
    expect(resumoDaJornada([1, 2, 3, 4, 5, 6, 7].map((n) => d(n, "08:00", "17:00")))).toBe("Seg–Dom 08:00–17:00");
  });
  it("buraco no meio separa os blocos", () => {
    expect(resumoDaJornada([d(2, "08:00", "17:00"), d(4, "08:00", "17:00")])).toBe("Seg 08:00–17:00 · Qua 08:00–17:00");
  });
  it("turno da noite aparece como está, e o intervalo no fim", () => {
    expect(resumoDaJornada([d(6, "22:00", "06:00")], { inicio: "02:00:00", fim: "02:30:00" })).toBe(
      "Sex 22:00–06:00 · intervalo 02:00–02:30",
    );
  });
  it("sem dia nenhum", () => {
    expect(resumoDaJornada([])).toBe("Sem horário em nenhum dia");
  });
});
