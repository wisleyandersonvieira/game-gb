// Trava (30/09/2026, erro no ar "column e.fotoaguardaremocaoem does not exist").
//
// A causa: a migração 20260929231000 foi EDITADA 20 minutos depois de
// publicada ("ainda não aplicada", achou-se), e o banco do Wisley ficou com a
// primeira versão, sem a coluna. Daqui em diante:
// 1. Migração publicada não se edita: a impressão (sha256) de cada uma fica em
//    supabase/migracoes-publicadas.txt, que só cresce. Mudou o arquivo: reprova.
// 2. A conferência item a item (no conferidor e no diagnóstico) não fica para
//    trás: toda migração da pasta está nela. Faltou: rode o gerador.
import { describe, expect, it } from "bun:test";
import { createHash } from "node:crypto";
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

const SUPA = join(import.meta.dir, "../../supabase");
const migracoes = readdirSync(join(SUPA, "migrations")).filter((f) => f.endsWith(".sql")).map((f) => f.slice(0, -4)).sort();
const sha = (nome: string) => createHash("sha256").update(readFileSync(join(SUPA, "migrations", `${nome}.sql`))).digest("hex");

const publicadas = new Map(
  readFileSync(join(SUPA, "migracoes-publicadas.txt"), "utf8")
    .split("\n").filter((l) => l.trim() && !l.startsWith("#"))
    .map((l) => { const [h, nome] = l.split(/\s+/); return [nome, h] as const; }),
);

/** As migrações que a conferência item a item conhece (a lista imp_migracoes). */
function naImpressao(arquivo: string): string[] {
  const t = readFileSync(join(SUPA, arquivo), "utf8");
  const i = t.indexOf("imp_migracoes(migracao) AS (VALUES");
  if (i < 0) return [];
  return [...t.slice(i, t.indexOf("\n),", i)).matchAll(/\('([^']+)'\)/g)].map((m) => m[1]).sort();
}

describe("migração publicada não se edita", () => {
  it("toda migração já publicada tem a mesma impressão de quando entrou na lista", () => {
    const mudaram = migracoes.filter((m) => publicadas.has(m) && publicadas.get(m) !== sha(m));
    expect(mudaram).toEqual([]);
  });
  it("nenhuma migração da lista sumiu da pasta", () => {
    expect([...publicadas.keys()].filter((m) => !migracoes.includes(m))).toEqual([]);
  });
  it("toda migração da pasta está na lista (senão: python3 scripts/gerar-diagnostico.py)", () => {
    expect(migracoes.filter((m) => !publicadas.has(m))).toEqual([]);
  });
});

describe("a conferência item a item conhece todas as migrações", () => {
  it("o conferidor confere todas", () => {
    expect(naImpressao("conferir-o-banco.sql")).toEqual(migracoes);
  });
  it("o diagnóstico confere todas", () => {
    expect(naImpressao("diagnostico-das-migracoes.sql")).toEqual(migracoes);
  });
});
