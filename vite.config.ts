// Configuracao oficial do Lovable para TanStack Start. Ela ja inclui:
// tanstackStart, react, tailwindcss, tsconfig paths, o alias "@" -> src,
// a injecao das VITE_* e o nitro (so no build). NAO adicione esses plugins
// aqui de novo, ou o app quebra com plugins duplicados.
//
// O nitro e o que empacota o servidor inteiro (com h3, react, supabase...)
// num bundle autossuficiente para a hospedagem do Lovable (Cloudflare).
// Sem ele, o build gera um servidor que depende de node_modules e a
// publicacao da "internal server error" (modulo h3-v2 nao encontrado).
import { execSync } from "node:child_process";
import { loadEnv } from "vite";
import { defineConfig } from "@lovable.dev/vite-tanstack-config";

// ---------------------------------------------------------------------------
// A VERSAO DESTE BUILD.
//
// Existe porque em 25/09/2026 o /saude dizia "tudo certo" enquanto o que
// estava no ar era uma versao antiga: o /saude falava do BANCO, e ninguem
// media o APP. Agora o proprio pacote carrega o commit e a hora em que foi
// montado, e isso aparece na tela.
//
// A hora do build e a parte que NUNCA falha. O commit depende de o build
// rodar dentro de um checkout do git ou de a hospedagem informar por variavel.
// ---------------------------------------------------------------------------
function versaoDoBuild() {
  const daHospedagem =
    process.env["VITE_VERSAO"] ||
    process.env["CF_PAGES_COMMIT_SHA"] ||
    process.env["VERCEL_GIT_COMMIT_SHA"] ||
    process.env["GITHUB_SHA"] ||
    "";
  let commit = daHospedagem.slice(0, 7);
  if (!commit) {
    try {
      commit = execSync("git rev-parse --short=7 HEAD", { stdio: ["ignore", "pipe", "ignore"] })
        .toString()
        .trim();
    } catch {
      // Build fora de um checkout do git: fica so a hora, que ja resolve.
    }
  }
  return { commit: commit || "desconhecido", em: new Date().toISOString() };
}

const VERSAO = versaoDoBuild();

export default defineConfig(({ command, mode }) => {
  if (command === "serve") {
    Object.assign(process.env, loadEnv(mode, process.cwd(), ""));
  }

  return {
    // Vai para dentro do pacote: cada aba aberta sabe de que versao ela e.
    define: { __VERSAO__: JSON.stringify(VERSAO) },
    plugins: [
      {
        name: "stgame-versao",
        apply: "build" as const,
        generateBundle(this: { emitFile: (f: { type: "asset"; fileName: string; source: string }) => void }) {
          // Arquivo solto ao lado do app: e o que a aba aberta consulta para
          // saber se ja existe versao mais nova publicada. Precisa ficar
          // FORA do pacote, senao ele envelheceria junto com a aba.
          this.emitFile({ type: "asset", fileName: "versao.json", source: JSON.stringify(VERSAO) });
        },
      },
    ],
    server: {
      port: 8080,
      strictPort: true,
      host: true,
      // Endereço público do GitHub Codespaces (ex.: abrir o link de TV no
      // celular). Só vale para o servidor de desenvolvimento.
      allowedHosts: [".app.github.dev"],
    },
  };
});
