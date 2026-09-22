// Configuracao oficial do Lovable para TanStack Start. Ela ja inclui:
// tanstackStart, react, tailwindcss, tsconfig paths, o alias "@" -> src,
// a injecao das VITE_* e o nitro (so no build). NAO adicione esses plugins
// aqui de novo, ou o app quebra com plugins duplicados.
//
// O nitro e o que empacota o servidor inteiro (com h3, react, supabase...)
// num bundle autossuficiente para a hospedagem do Lovable (Cloudflare).
// Sem ele, o build gera um servidor que depende de node_modules e a
// publicacao da "internal server error" (modulo h3-v2 nao encontrado).
import { loadEnv } from "vite";
import { defineConfig } from "@lovable.dev/vite-tanstack-config";

// O codigo de servidor le variaveis em process.env (STGAME_SERVICE_ROLE_KEY,
// SITE_URL). Em desenvolvimento, o Vite nao repassa o .env para process.env;
// isto faz esse repasse. NAO vaza segredo para o navegador: o pacote do
// cliente nao recebe process.env. Em producao as variaveis vem dos Secrets
// do Lovable, nao daqui, e o build nunca le o .env (assim nenhuma chave
// secreta vai parar no pacote publicado).
export default defineConfig(({ command, mode }) => {
  if (command === "serve") {
    Object.assign(process.env, loadEnv(mode, process.cwd(), ""));
  }

  return {
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
