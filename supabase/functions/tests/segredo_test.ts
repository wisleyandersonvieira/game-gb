// Rodar: deno test supabase/functions/tests/
// Prova que o webhook e a fila recusam (401) qualquer chamada sem o segredo
// certo, antes de abrir o banco ou tratar a mensagem.
import { criarWebhook } from "../telegram-webhook/index.ts";
import { criarFila } from "../telegram-fila/index.ts";
import { segredoConfere } from "../_shared/seguranca.ts";

const SEGREDO = "segredo_de_teste_0123456789_abcdef";

function igual(a: unknown, b: unknown, msg: string) {
  if (a !== b) throw new Error(`${msg}: esperado ${b}, veio ${a}`);
}

function montar() {
  const chamadas = { registrar: 0, processar: 0 };
  const h = criarWebhook({
    segredo: SEGREDO,
    registrar: (id) => {
      chamadas.registrar++;
      return Promise.resolve(id !== 99);
    },
    processar: () => {
      chamadas.processar++;
      return Promise.resolve();
    },
    emSegundoPlano: () => {},
  });
  return { h, chamadas };
}

const update = JSON.stringify({ update_id: 1, message: { chat: { id: 1, type: "private" }, text: "/start" } });
const pedido = (cab?: string, corpo = update) =>
  new Request("http://x/telegram-webhook", {
    method: "POST",
    headers: cab === undefined ? {} : { "X-Telegram-Bot-Api-Secret-Token": cab },
    body: corpo,
  });

Deno.test("webhook sem o cabeçalho: 401 e nada acontece", async () => {
  const { h, chamadas } = montar();
  igual((await h(pedido())).status, 401, "status");
  igual(chamadas.registrar + chamadas.processar, 0, "chamadas");
});

Deno.test("webhook com segredo errado ou vazio: 401 e nada acontece", async () => {
  const { h, chamadas } = montar();
  for (const s of ["", "errado", SEGREDO + "x", SEGREDO.slice(0, -1), SEGREDO.toUpperCase()]) {
    igual((await h(pedido(s))).status, 401, `status (${s.length})`);
  }
  igual(chamadas.registrar + chamadas.processar, 0, "chamadas");
});

Deno.test("webhook sem segredo configurado no servidor: recusa tudo", async () => {
  const h = criarWebhook({ segredo: undefined, registrar: () => Promise.resolve(true), processar: () => Promise.resolve(), emSegundoPlano: () => {} });
  igual((await h(pedido(""))).status, 401, "vazio");
  igual((await h(pedido("qualquer"))).status, 401, "qualquer");
});

Deno.test("webhook com segredo certo: responde 200 e trata uma vez", async () => {
  const { h, chamadas } = montar();
  igual((await h(pedido(SEGREDO))).status, 200, "status");
  igual(chamadas.registrar, 1, "registrou");
  igual(chamadas.processar, 1, "tratou");
  // update repetido (o registrar diz que já viu): não trata de novo
  igual((await h(pedido(SEGREDO, JSON.stringify({ update_id: 99 })))).status, 200, "repetido");
  igual(chamadas.processar, 1, "não tratou o repetido");
});

Deno.test("fila sem o segredo certo: 401 e nada é enviado", async () => {
  let rodadas = 0;
  const f = criarFila({ segredo: SEGREDO, rodada: () => Promise.resolve(++rodadas) });
  for (const cab of [undefined, "", "errado", SEGREDO + "x"]) {
    const r = await f(new Request("http://x/telegram-fila", { method: "POST", headers: cab === undefined ? {} : { "x-fila-segredo": cab } }));
    igual(r.status, 401, "status");
  }
  igual(rodadas, 0, "rodadas");
  const r = await f(new Request("http://x/telegram-fila", { method: "POST", headers: { "x-fila-segredo": SEGREDO } }));
  igual(r.status, 200, "com segredo");
  igual(rodadas, 1, "uma rodada");
});

Deno.test("segredo curto demais no servidor nunca vale", async () => {
  igual(await segredoConfere("curto", "curto"), false, "curto");
  igual(await segredoConfere(SEGREDO, SEGREDO), true, "certo");
});
