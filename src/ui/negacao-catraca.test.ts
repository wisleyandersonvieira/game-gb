// TESTE DE NEGAÇÃO CONFERE O RESULTADO, NUNCA O ERRO (regra do Wisley,
// 29/09/2026).
//
// Três sabotagens em dois dias passaram ou reprovaram pelo motivo errado
// porque o teste só olhava SE DEU ERRO. O banco respondia "nada alterado", sem
// erro, e o teste ficava satisfeito (ou reprovava sem porta aberta). Em
// 29/09/2026 as 382 negações da suíte de isolamento passaram a conferir o
// resultado: guardar_foto()/nada_mudou() para gravação, guardar_resultado()/
// nada_voltou() para leitura.
//
// Esta catraca lê o arquivo de isolamento e reprova se voltar a existir uma
// negação que prova só com "deu erro": uma variável marcada no EXCEPTION e
// passada sozinha para exigir().
import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const ISOLAMENTO = readFileSync(join(import.meta.dir, "../../supabase/tests/isolamento.sql"), "utf8");

/**
 * Negações que provam só com o erro: toda variável marcada no EXCEPTION
 * ("THEN var := true") que depois aparece num exigir(var ...) — em qualquer
 * lugar do arquivo, mesmo com outra linha no meio (um RESET ROLE, por exemplo).
 * "exigir(NOT var" é o contrário (a operação TEM de funcionar) e não conta.
 */
export function negacoesSoPeloErro(sql: string): string[] {
  const marcadas = new Set([...sql.matchAll(/THEN\s+([a-z_]+)\s*:=\s*true\s*;/gi)].map((m) => m[1].toLowerCase()));
  const achadas: string[] = [];
  for (const m of sql.matchAll(/PERFORM\s+public\.exigir\(\s*([a-z_]+)\b/gi)) {
    if (!marcadas.has(m[1].toLowerCase())) continue;
    const linha = sql.slice(0, m.index).split("\n").length;
    achadas.push(`linha ${linha}: exigir(${m[1]} ...`);
  }
  return achadas;
}

describe("negação confere o resultado, nunca o erro", () => {
  it("nenhuma negação da suíte de isolamento prova só com 'deu erro'", () => {
    expect(negacoesSoPeloErro(ISOLAMENTO)).toEqual([]);
  });

  it("as negações usam a foto do banco (gravação) ou o que voltou (leitura)", () => {
    const gravacao = ISOLAMENTO.match(/exigir\(public\.nada_mudou\(\)/g)?.length ?? 0;
    const leitura = ISOLAMENTO.match(/exigir\(public\.nada_voltou\(\)/g)?.length ?? 0;
    // O número só pode SUBIR: 343 de gravação e 39 de leitura em 29/09/2026.
    expect(gravacao).toBeGreaterThanOrEqual(343);
    expect(leitura).toBeGreaterThanOrEqual(39);
  });

  it("a catraca reconhece o jeito antigo (prova de que ela olha o lugar certo)", () => {
    const antigo = `BEGIN UPDATE public.x SET a = 1; deu_erro := false;
  EXCEPTION WHEN insufficient_privilege THEN deu_erro := true; END;
  PERFORM public.exigir(deu_erro, 'B nao altera');`;
    expect(negacoesSoPeloErro(antigo)).toHaveLength(1);
    const novo = `PERFORM public.guardar_foto();
  BEGIN UPDATE public.x SET a = 1; deu_erro := false;
  EXCEPTION WHEN insufficient_privilege THEN deu_erro := true; END;
  PERFORM public.exigir(public.nada_mudou(), 'B nao altera');`;
    expect(negacoesSoPeloErro(novo)).toHaveLength(0);
  });
});
