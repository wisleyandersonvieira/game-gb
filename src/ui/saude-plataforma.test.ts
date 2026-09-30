// A faixa do /admin e a conferência dos buckets (01/10/2026).
// 1. Bucket público vira o PRIMEIRO problema da plataforma; o que falta também.
// 2. Trava: todo bucket usado pelo código ou criado por migração está na lista
//    conferida (BUCKETS_ESPERADOS). Bucket novo fora da lista reprova: ele não
//    seria conferido na /saude.
import { describe, expect, it } from "bun:test";
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";
import { BUCKETS_ESPERADOS, situacaoDosBuckets } from "@/servidor/acesso";
import { problemasDaPlataforma, type DiagnosticoDaPlataforma } from "./saude-plataforma";

const RAIZ = join(import.meta.dir, "..", "..");
const TODOS_PRIVADOS = BUCKETS_ESPERADOS.map((b) => ({ id: b.id, public: false }));

function diag(buckets: { id: string; public: boolean }[]): DiagnosticoDaPlataforma {
  return { temChave: true, temPepper: true, temSite: true, contaDeSenha: true, banco: "ok", rotinas: null,
           buckets: situacaoDosBuckets(buckets) };
}

describe("buckets na /saude e na faixa do /admin", () => {
  it("tudo privado e presente: nenhum problema", () => {
    expect(problemasDaPlataforma(diag(TODOS_PRIVADOS))).toEqual([]);
  });
  it("bucket público é o primeiro problema, e diz PÚBLICO", () => {
    const p = problemasDaPlataforma(diag(TODOS_PRIVADOS.map((b) => (b.id === "entregas" ? { ...b, public: true } : b))));
    expect(p[0]).toContain('"entregas"');
    expect(p[0]).toContain("PÚBLICO");
  });
  it("bucket que falta aparece", () => {
    expect(problemasDaPlataforma(diag(TODOS_PRIVADOS.filter((b) => b.id !== "documentos-rh"))).join(" ")).toContain('"documentos-rh"');
  });
  it("bucket que não é do sistema, se for público, também aparece", () => {
    expect(problemasDaPlataforma(diag([...TODOS_PRIVADOS, { id: "avatars", public: true }])).join(" ")).toContain('"avatars"');
  });
});

function arquivos(pasta: string): string[] {
  const saida: string[] = [];
  for (const nome of readdirSync(join(RAIZ, pasta))) {
    const c = `${pasta}/${nome}`;
    if (statSync(join(RAIZ, c)).isDirectory()) saida.push(...arquivos(c));
    else if (/\.(ts|tsx)$/.test(nome) && !nome.endsWith(".test.ts")) saida.push(c);
  }
  return saida;
}

describe("trava: todo bucket do sistema é conferido", () => {
  const esperados = new Set(BUCKETS_ESPERADOS.map((b) => b.id));
  it("os buckets usados no código estão na lista", () => {
    const usados = new Set<string>();
    for (const f of [...arquivos("src"), ...arquivos("supabase/functions")]) {
      const t = readFileSync(join(RAIZ, f), "utf8");
      for (const m of t.matchAll(/storage\s*\.from\(\s*"([a-z0-9-]+)"/g)) usados.add(m[1]);
      for (const m of t.matchAll(/const BUCKET\w*\s*=\s*"([a-z0-9-]+)"/g)) usados.add(m[1]);
    }
    expect(usados.size).toBeGreaterThan(3);
    expect([...usados].filter((b) => !esperados.has(b))).toEqual([]);
  });
  it("os buckets criados pelas migrações estão na lista", () => {
    const criados = new Set<string>();
    for (const f of readdirSync(join(RAIZ, "supabase/migrations"))) {
      const t = readFileSync(join(RAIZ, "supabase/migrations", f), "utf8");
      for (const m of t.matchAll(/INSERT INTO storage\.buckets[^;]*/g))
        for (const x of m[0].matchAll(/\('([a-z0-9-]+)',\s*'[a-z0-9-]+',\s*(true|false)\)/g)) criados.add(x[1]);
    }
    expect(criados.size).toBeGreaterThan(3);
    expect([...criados].filter((b) => !esperados.has(b))).toEqual([]);
  });
});
