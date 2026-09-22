// Server-side Supabase client with service role key - bypasses RLS.
// Use this for admin operations in server functions and server routes only.
// For user-authenticated queries (with RLS), use the auth middleware instead.
import { createClient } from '@supabase/supabase-js';
import type { Database } from './types';
import { SUPABASE_URL } from './config-publica';

function isNewSupabaseApiKey(value: string): boolean {
  return value.startsWith('sb_publishable_') || value.startsWith('sb_secret_');
}

function createSupabaseFetch(supabaseKey: string): typeof fetch {
  return (input, init) => {
    const headers = new Headers(
      typeof Request !== 'undefined' && input instanceof Request ? input.headers : undefined,
    );

    if (init?.headers) {
      new Headers(init.headers).forEach((value, key) => headers.set(key, value));
    }

    // New Supabase API keys are opaque strings, not bearer JWTs.
    if (isNewSupabaseApiKey(supabaseKey) && headers.get('Authorization') === `Bearer ${supabaseKey}`) {
      headers.delete('Authorization');
    }

    headers.set('apikey', supabaseKey);
    return fetch(input, { ...init, headers });
  };
}

function createSupabaseAdminClient() {
  // STGAME_SERVICE_ROLE_KEY: nome cadastrado nos Secrets do Lovable (ele não
  // aceita nomes começando com SUPABASE_). O endereço é o mesmo do navegador
  // (config-publica.ts), então a chave precisa ser do projeto
  // asgdynxdcdnjglgyyaek. SUPABASE_SERVICE_ROLE_KEY vale só em
  // desenvolvimento (.env antigo): na publicação o Lovable pode preencher
  // esse nome com a chave de outro projeto, então ali ele é ignorado.
  const SUPABASE_SERVICE_ROLE_KEY =
    process.env['STGAME_SERVICE_ROLE_KEY'] ||
    (import.meta.env.DEV ? process.env['SUPABASE_SERVICE_ROLE_KEY'] : undefined);

  if (!SUPABASE_SERVICE_ROLE_KEY) {
    const message =
      'Falta a chave STGAME_SERVICE_ROLE_KEY (Secrets do Lovable; no desenvolvimento, arquivo .env).';
    console.error(`[Supabase] ${message}`);
    throw new Error(message);
  }

  return createClient<Database>(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    global: {
      fetch: createSupabaseFetch(SUPABASE_SERVICE_ROLE_KEY),
    },
    auth: {
      storage: undefined,
      persistSession: false,
      autoRefreshToken: false,
    }
  });
}

let _supabaseAdmin: ReturnType<typeof createSupabaseAdminClient> | undefined;

// Server-side Supabase client with service role - bypasses RLS
// SECURITY: Only use this for trusted server-side operations, never expose to client code
// Load inside server handlers: const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
// Top-level import is safe only in other .server.ts modules - route files and *.functions.ts ship to the client bundle.
export const supabaseAdmin = new Proxy({} as ReturnType<typeof createSupabaseAdminClient>, {
  get(_, prop, receiver) {
    if (!_supabaseAdmin) _supabaseAdmin = createSupabaseAdminClient();
    return Reflect.get(_supabaseAdmin, prop, receiver);
  },
});
