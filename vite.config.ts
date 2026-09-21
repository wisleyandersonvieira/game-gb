import path from "node:path";
import { defineConfig, loadEnv } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";
import { tanstackStart } from "@tanstack/react-start/plugin/vite";

export default defineConfig(({ mode }) => {
  // O codigo de servidor le variaveis sem o prefixo VITE_ (SUPABASE_URL,
  // SUPABASE_SERVICE_ROLE_KEY, SITE_URL) em process.env. O Vite, sozinho, so
  // expoe as VITE_ para o navegador e nao mexe em process.env — e o
  // `bun run dev` tambem nao repassa o .env para o processo do Vite.
  // Sem isto, as funcoes de servidor nao enxergam a chave em desenvolvimento.
  //
  // Isto NAO vaza segredo para o navegador: o pacote do cliente so recebe o
  // que for import.meta.env.VITE_*; process.env fica so no servidor.
  // Em producao as variaveis vem do ambiente de verdade, nao daqui.
  Object.assign(process.env, loadEnv(mode, process.cwd(), ""));

  return {
    server: {
      port: 8080,
      strictPort: true,
      host: true,
    },
    resolve: {
      alias: {
        "@": path.resolve(__dirname, "./src"),
      },
    },
    plugins: [
      tanstackStart(),
      react(),
      tailwindcss(),
    ],
  };
});
