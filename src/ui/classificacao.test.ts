// Trava (regra do Wisley, 29/09/2026): todo arquivo de aplicar diz se a
// migração ACRESCENTA (aplica antes de publicar) ou TIRA (aplica e publica
// juntos, com as lojas fechadas). Vale para todo arquivo que leve migração a
// partir da parte 4 (20260929270000); os mais velhos já foram aplicados.
import { describe, expect, it } from "bun:test";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

const PASTA = join(import.meta.dir, "..", "..", "supabase");
const DESDE = "20260929270000";

function migracoesDoArquivo(texto: string): string[] {
  return [...texto.matchAll(/\b(\d{14})_[a-z0-9_]+\.sql/g)].map((m) => m[1]);
}

describe("classificação dos arquivos de aplicar", () => {
  const arquivos = readdirSync(PASTA).filter((f) => f.startsWith("aplicar-") && f.endsWith(".sql"));
  const novos = arquivos.filter((f) => migracoesDoArquivo(readFileSync(join(PASTA, f), "utf8")).some((v) => v >= DESDE));

  it("há arquivos novos para conferir (a trava olha o lugar certo)", () => {
    expect(novos.length).toBeGreaterThan(0);
  });

  it("todo arquivo novo diz ACRESCENTA ou TIRA no cabeçalho", () => {
    const sem = novos.filter((f) => !/^-- CLASSIFICAÇÃO: (ACRESCENTA|TIRA)\b/m.test(readFileSync(join(PASTA, f), "utf8")));
    expect(sem).toEqual([]);
  });
});
