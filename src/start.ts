import { createStart, createCsrfMiddleware } from "@tanstack/react-start";
import { getRouter } from "./router";
import { attachSupabaseAuth } from "@/integrations/supabase/auth-attacher";

// As funcoes de servidor (criar cliente, convidar, reenviar) sao endpoints RPC
// de mesma origem. Sem isto, outro site poderia disparar uma chamada usando o
// navegador de quem esta logado. O token Bearer ja dificulta o ataque, mas a
// checagem de origem e a defesa que o proprio framework recomenda.
const csrfMiddleware = createCsrfMiddleware({
  filter: (ctx) => ctx.handlerType === "serverFn",
});

export const startInstance = createStart(() => ({
  requestMiddleware: [csrfMiddleware],
  functionMiddleware: [attachSupabaseAuth],
  router: getRouter(),
}));
