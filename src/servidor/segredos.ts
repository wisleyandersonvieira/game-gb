// Ajudantes de servidor usados pelo acesso (parte A) e pela visao do tablet
// (parte B1b). Ficam num arquivo so para NAO existirem duas versoes da mesma
// regra: o resumo do PIN e a trava de tentativas precisam ser identicos nos
// dois caminhos, senao um PIN valido no login nao seria valido no tablet.
//
// Nada aqui e chamado pelo navegador: so por handlers de servidor.
import { getRequest } from "@tanstack/react-start/server";

export const ERRO_TRAVADO = "Muitas tentativas. Espere um pouco e tente de novo.";

export function chaveDoServidor() {
  const chave = process.env["STGAME_PIN_PEPPER"];
  if (!chave || chave.length < 16) {
    throw new Error("Falta a chave STGAME_PIN_PEPPER no servidor (Secrets do Lovable).");
  }
  return chave;
}

export const hex = (b: ArrayBuffer) =>
  [...new Uint8Array(b)].map((x) => x.toString(16).padStart(2, "0")).join("");
export const deHex = (s: string) => Uint8Array.from((s.match(/../g) ?? []).map((h) => parseInt(h, 16)));

/**
 * Embaralha com a chave do servidor (HMAC-SHA256). O resultado e sempre o mesmo
 * para a mesma entrada, e so por isso o banco acha a pessoa pelo PIN direto no
 * indice — sem comparar uma a uma, que ficaria lento com 20+ pessoas.
 */
export async function embaralhar(valor: string) {
  const material = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(chaveDoServidor()),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return hex(await crypto.subtle.sign("HMAC", material, new TextEncoder().encode(valor)));
}

/** O resumo do PIN, do jeito que o banco guarda. Um lugar só, para os dois caminhos. */
export const resumoDoPin = (contaid: number, pin: string) => embaralhar(`pin:${contaid}:${pin}`);

/**
 * De onde veio a tentativa. Definido pelo SERVIDOR (o navegador nao escolhe),
 * senao bastaria mandar um valor novo a cada tentativa para zerar a trava.
 */
export function origemDaChamada() {
  try {
    // Só o cabeçalho que a hospedagem (Cloudflare) escreve por cima do que o
    // navegador manda. x-forwarded-for e x-real-ip são escolhidos pelo cliente
    // quando não há um intermediário confiável, e por isso não servem.
    const ip = getRequest()?.headers.get("cf-connecting-ip");
    return (ip || "sem-ip").slice(0, 40);
  } catch {
    return "sem-ip";
  }
}

export async function abrirTentativa(
  contaid: number | null,
  tipo: "senha" | "pin" | "tablet",
  chave: string,
  origem: string,
) {
  const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
  const { data, error } = await supabaseAdmin.rpc("tentativa_abrir", {
    p_contaid: contaid as unknown as number, p_tipo: tipo, p_chave: chave, p_origem: origem,
  });
  if (error) {
    // Função ausente = o banco não recebeu as migrações desta versão. Dizer
    // isso na tela evita ficar horas procurando onde está o erro.
    if (error.code === "PGRST202" || error.message.includes("Could not find")) {
      throw new Error(
        "O banco de dados ainda não recebeu as atualizações desta versão. Abra /saude para ver o que falta.",
      );
    }
    throw new Error("Não foi possível conferir o acesso agora.");
  }
  if (data === null || data === undefined) throw new Error(ERRO_TRAVADO);
  return data as number;
}

export async function fecharTentativa(tentativaid: number, sucesso: boolean) {
  const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
  await supabaseAdmin.rpc("tentativa_fechar", { p_tentativaid: tentativaid, p_sucesso: sucesso });
}
