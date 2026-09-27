// A trava de "tentativa que falha não deixa nada para trás" (29/09/2026).
import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { descartarFotoSemEntrega } from "./fotoSemEntrega";

function falso(temEntrega: boolean) {
  const apagados: string[] = [];
  return { apagados, deps: { temEntrega: async () => temEntrega, apagar: async (c: string) => void apagados.push(c) } };
}

describe("foto de tentativa que falhou", () => {
  it("sem entrega usando o arquivo: sai do armazenamento", async () => {
    const f = falso(false);
    expect(await descartarFotoSemEntrega("1/10/a.jpg", f.deps)).toBe(true);
    expect(f.apagados).toEqual(["1/10/a.jpg"]);
  });

  it("com entrega usando o arquivo: fica (nunca se apaga a prova de uma entrega)", async () => {
    const f = falso(true);
    expect(await descartarFotoSemEntrega("1/10/a.jpg", f.deps)).toBe(false);
    expect(f.apagados).toEqual([]);
  });

  it("o tablet e o celular descartam a foto quando a entrega falha", () => {
    const tablet = readFileSync(join(import.meta.dir, "tablet.ts"), "utf8");
    const celular = readFileSync(join(import.meta.dir, "colaborador.ts"), "utf8");
    expect(tablet).toContain("descartarFotoDaTentativa(");
    expect(celular).toContain("descartarFotoDaTentativa(");
  });
});
