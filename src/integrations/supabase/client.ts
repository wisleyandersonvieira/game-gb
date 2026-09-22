import { createClient } from '@supabase/supabase-js';
import type { Database } from './types';
import { brokeredPreviewStorage } from './previewAuthStorage';
import { SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY } from './config-publica';

// URL e chave pública ficam em config-publica.ts. A service_role nunca entra
// aqui: fica só em variável de servidor (STGAME_SERVICE_ROLE_KEY).
// Import the supabase client like this:
// import { supabase } from "@/integrations/supabase/client";

export const supabase = createClient<Database>(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
  auth: {
    storage: brokeredPreviewStorage(),
    persistSession: true,
    autoRefreshToken: true,
  }
});