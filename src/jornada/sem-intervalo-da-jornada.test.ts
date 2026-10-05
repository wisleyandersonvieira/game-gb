// O intervalo da JORNADA saiu (05/10/2026, decisão do Wisley): sem o bot ele
// não fazia nada, e campo que não faz nada é pior que campo nenhum, porque
// alguém preenche achando que funciona. Esta trava reprova se ele voltar à
// tela de Jornada ou ao que a tela manda ao banco. (No banco, a seção 120 do
// teste de isolamento confere que as colunas e os parâmetros não existem.)
//
// O intervalo do MAPA (intervalosdomapa) é outra coisa e FICA: é só para
// enxergar e imprimir a escala.
import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const RAIZ = join(import.meta.dir, "..", "..");
const ler = (f: string) => readFileSync(join(RAIZ, f), "utf8");

describe("o intervalo da jornada não volta", () => {
  it("a tela de Jornada não tem o campo nem manda o intervalo", () => {
    const tela = ler("src/routes/_authenticated/jornada.tsx");
    expect(tela).not.toMatch(/pausainicio|pausafim|temPausa|p_pausa|não envia nada/);
  });
  it("o banco, como o site o enxerga, não aceita nem devolve o intervalo da jornada", () => {
    const tipos = ler("src/integrations/supabase/types.ts");
    expect(tipos).not.toMatch(/pausainicio|pausafim|p_pausainicio|p_pausafim/);
  });
  it("a trava olha o lugar certo (a tela de Jornada salva pelo salvar_jornada)", () => {
    expect(ler("src/routes/_authenticated/jornada.tsx")).toContain('rpc("salvar_jornada"');
  });
});
