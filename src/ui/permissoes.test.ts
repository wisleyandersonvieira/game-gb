// Trava (parte 4, 29/09/2026): toda tela da área do gestor tem regra no mapa
// CODIGO_DA_TELA, e o código existe no catálogo de permissões do banco. Tela
// nova sem regra reprova aqui (e, sem regra, só o master a veria).
import { describe, expect, it } from "bun:test";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { CODIGO_DA_TELA, filtrarMenu, podeVerTela } from "./permissoes";
import { MENU_MASTER } from "./menu";

const RAIZ = join(import.meta.dir, "..", "..");
const telas = readdirSync(join(RAIZ, "src/routes/_authenticated"))
  .filter((f) => f.endsWith(".tsx") && f !== "route.tsx")
  .map((f) => "/" + f.replace(/\.tsx$/, "").split(".")[0]);

// Os códigos do catálogo, lidos da migração que o cria.
const base = readFileSync(join(RAIZ, "supabase/migrations/20260929248000_permissoes_base.sql"), "utf8");
const catalogo = new Set([...base.matchAll(/\('([a-z_]+\.[a-z_]+)',/g)].map((m) => m[1]));

describe("permissões das telas", () => {
  it("toda tela da área do gestor tem regra no mapa", () => {
    const semRegra = telas.filter((t) => !(t in CODIGO_DA_TELA));
    expect(semRegra).toEqual([]);
  });

  it("todo item do menu tem regra, e todo código existe no catálogo", () => {
    const itens = MENU_MASTER.flatMap((g) => g.itens.map((i) => i.to));
    expect(itens.filter((t) => !(t in CODIGO_DA_TELA))).toEqual([]);
    const codigos = Object.values(CODIGO_DA_TELA).filter((c) => c !== "master" && c !== "todos");
    expect(codigos.filter((c) => !catalogo.has(c))).toEqual([]);
  });

  it("canal confidencial, documentos pessoais, configurações e estornos: só o master", () => {
    for (const t of ["/canal-confidencial", "/documentos-pessoais", "/configuracoes", "/estornos"]) {
      expect(CODIGO_DA_TELA[t]).toBe("master");
      expect(podeVerTela({ master: false, codigos: [...catalogo] }, t)).toBe(false);
      expect(podeVerTela({ master: true, codigos: [] }, t)).toBe(true);
    }
  });

  it("o gerente vê só o que o cargo deixa; endereço sem regra é negado", () => {
    const p = { master: false, codigos: ["quadro.ver", "metas.ver"] };
    expect(podeVerTela(p, "/painel")).toBe(true);
    expect(podeVerTela(p, "/metas")).toBe(true);
    expect(podeVerTela(p, "/funcionarios")).toBe(false);
    expect(podeVerTela(p, "/tela-que-nao-existe")).toBe(false);
    expect(podeVerTela(undefined, "/painel")).toBe(false);
    const itens = filtrarMenu(MENU_MASTER, p).flatMap((g) => g.itens.map((i) => i.to));
    expect(itens.sort()).toEqual(["/metas", "/painel", "/perfil"]);
  });
});
