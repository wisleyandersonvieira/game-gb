import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";
import { tanstackStart } from "@tanstack/react-start/plugin/vite";

export default defineConfig({
  server: {
    port: 8080,
    strictPort: true,
    host: true,
  },
  plugins: [
    tanstackStart(),
    react(),
    tailwindcss(),
  ],
});
