// A CATRACA do "que dia é hoje" nas telas (27/09/2026).
//
// Quem decide o dia é o banco (hoje_da_conta), e a tela pergunta com
// useHojeDaConta() ou lê o "hoje" que a fila já traz. Este teste procura, no
// código das telas, quem ainda calcula "hoje" com o relógio do aparelho. O
// número só pode DESCER: tela nova que fizer a conta sozinha reprova aqui.
//
// Cada tela sai desta lista junto com a função do banco que ela chama — as
// duas precisam passar para o fuso da conta ao mesmo tempo, senão uma conta
// fora de São Paulo teria tela e banco discordando perto da meia-noite.
import { describe, expect, it } from "bun:test";
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join, relative } from "node:path";

const RAIZ = join(import.meta.dir, "../..");
const SRC = join(RAIZ, "src");

function arquivos(pasta: string, achados: string[] = []): string[] {
  for (const nome of readdirSync(pasta)) {
    const caminho = join(pasta, nome);
    if (statSync(caminho).isDirectory()) arquivos(caminho, achados);
    else if (/\.tsx?$/.test(nome) && !/\.test\.tsx?$/.test(nome)) achados.push(caminho);
  }
  return achados;
}

/** Jeitos de a tela descobrir "hoje" sozinha, pelo relógio do aparelho. */
const HOJE_NO_APARELHO = [
  /new Date\(\)\.toISOString\(\)\.slice\(0,\s*10\)/,
  /DateTimeFormat\("en-CA"[^)]*\)\s*\.format\(new Date\(\)\)/,
  /new Date\(\)\.toLocaleDateString\(/,
  /hojeEmSaoPaulo/,
];

const quemCalcula = () =>
  arquivos(SRC)
    .filter((f) => HOJE_NO_APARELHO.some((r) => r.test(readFileSync(f, "utf8"))))
    .map((f) => relative(RAIZ, f))
    .sort();

describe("catraca: telas que ainda calculam 'hoje' no aparelho", () => {
  it("o que a loja vê (tablet, fila do gestor, celular) já não calcula", () => {
    const lista = quemCalcula();
    for (const f of ["src/routes/tablet.tsx", "src/painel/FilaDoDia.tsx", "src/routes/eu/extrato.tsx"]) {
      expect(lista).not.toContain(f);
    }
  });

  it("o total só pode descer (hoje: 11 — telas do gestor e a agenda do painel da loja)", () => {
    const lista = quemCalcula();
    expect(lista.length, `ainda calculam sozinhas: ${lista.join(", ")}`).toBeLessThanOrEqual(11);
  });
});
