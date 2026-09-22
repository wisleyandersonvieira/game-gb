// Endereço e chave PÚBLICA do Supabase (projeto asgdynxdcdnjglgyyaek).
// Ficam no código, como no modelo do Lovable, porque a publicação não recebe
// o .env e o Lovable não aceita Secrets com os nomes VITE_ ou SUPABASE_.
// Os dois são públicos por natureza: o navegador de qualquer visitante já os
// vê. Quem protege os dados é a RLS do banco, não o segredo desta chave.
//
// A chave SECRETA (service_role) NUNCA entra aqui nem em nenhum arquivo do
// código: ela fica só no Secret STGAME_SERVICE_ROLE_KEY (veja client.server.ts).
export const SUPABASE_URL = "https://asgdynxdcdnjglgyyaek.supabase.co";
export const SUPABASE_PUBLISHABLE_KEY = "sb_publishable_kFEjH-Q1NmqA5SiMEn3Hrw_4MLq9cX8";
