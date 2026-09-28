import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { SEGUNDOS_SEM_TOQUE_JANELA, textoEspera } from "./QuemPodeAceitar";

const ler = (f: string) => readFileSync(join(import.meta.dir, "..", f), "utf8");

describe("quem pode aceitar (tablet)", () => {
  it("fecha sozinha depois de cerca de 30 segundos sem toque", () => {
    expect(SEGUNDOS_SEM_TOQUE_JANELA).toBe(30);
  });

  it("diz por que a pessoa não consegue pegar agora", () => {
    expect(textoEspera(6)).toBe("pode pegar em 6 min");
  });

  it("não pergunta nada ao banco: a lista vem pronta na fila", () => {
    const janela = ler("painel/QuemPodeAceitar.tsx");
    expect(janela).not.toContain("rpc(");
    expect(janela).not.toContain("useQuery");
    // A regra não é reescrita na tela.
    expect(janela).not.toMatch(/candidatos|diadefolga|funcionarioid/);
  });

  it("a área de toque do ícone tem pelo menos 44 px (h-11 w-11)", () => {
    expect(ler("painel/QuemPodeAceitar.tsx")).toContain("h-11 w-11");
  });
});
