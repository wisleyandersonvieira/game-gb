// Rodar: deno test supabase/functions/tests/
// O segredo das funções do servidor (hoje, a expurgo-fotos): segredo curto
// demais nunca vale, e o certo vale. (Os testes do webhook e da fila do
// Telegram saíram com o Telegram, em 04/10/2026.)
import { segredoConfere } from "../_shared/seguranca.ts";

const SEGREDO = "segredo_de_teste_0123456789_abcdef";

function igual(a: unknown, b: unknown, msg: string) {
  if (a !== b) throw new Error(`${msg}: esperado ${b}, veio ${a}`);
}

Deno.test("segredo curto demais no servidor nunca vale", async () => {
  igual(await segredoConfere("curto", "curto"), false, "curto");
  igual(await segredoConfere(SEGREDO, SEGREDO), true, "certo");
});
