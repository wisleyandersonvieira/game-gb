import { createStart } from "@tanstack/react-start";
import { getRouter } from "./router";
import { attachSupabaseAuth } from "@/integrations/supabase/auth-attacher";

export const startInstance = createStart(() => ({
  requestMiddleware: [],
  functionMiddleware: [attachSupabaseAuth],
  router: getRouter(),
}));
