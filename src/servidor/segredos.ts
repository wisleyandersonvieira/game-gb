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

export type TipoDeTrava = "senha" | "pin" | "tablet" | "pintablet" | "lojamanual";

/**
 * Abre a tentativa e, quando o tipo usa ATRASO em vez de bloqueio, espera o
 * tempo que o banco mandou antes de devolver. O calculo e feito la dentro, sob
 * a mesma tranca que conta as tentativas: uma rajada simultanea nao escapa.
 *
 * O atraso existe para o login da loja com senha DIGITADA. Bloquear ali
 * devolveria o problema que fez a trava ser desligada na parte A: um
 * engracadinho errando de proposito deixaria o balcao sem sistema.
 */
export async function abrirTentativa(
  contaid: number | null,
  tipo: TipoDeTrava,
  chave: string,
  origem: string,
) {
  const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
  const { data: bruto, error } = await supabaseAdmin.rpc("tentativa_abrir_ex", {
    p_contaid: contaid as unknown as number, p_tipo: tipo, p_chave: chave, p_origem: origem,
  });
  const resposta = bruto as { tentativaid: number | null; esperar: number } | null;
  const data = resposta?.tentativaid ?? null;
  if (resposta && resposta.esperar > 0) {
    await new Promise((r) => setTimeout(r, Math.min(resposta.esperar, 10_000)));
  }
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

/**
 * Regras da senha digitada do tablet. Mínimo de 10 e nada de óbvio: sequência,
 * repetição, palavras comuns, o nome da loja, o nome ou o código da empresa.
 */
export function conferirSenhaDoTablet(valor: string, proibidas: (string | null | undefined)[]) {
  const v = (valor ?? "").trim();
  if (v.length < 10) throw new Error("A senha do tablet precisa ter pelo menos 10 caracteres.");
  if (v.length > 72) throw new Error("A senha do tablet é longa demais (máximo 72 caracteres).");
  if (/^(.)\1+$/.test(v)) throw new Error("Não repita o mesmo caractere.");

  const baixo = v.toLowerCase();
  const sequencias = ["0123456789", "abcdefghijklmnopqrstuvwxyz", "qwertyuiop", "9876543210"];
  for (const seq of sequencias) {
    for (let i = 0; i + 4 <= seq.length; i++) {
      if (baixo.includes(seq.slice(i, i + 5))) {
        throw new Error("Essa senha é fácil demais: evite sequências como 12345 ou abcde.");
      }
    }
  }
  const comuns = ["senha", "password", "stgame", "tablet", "12345", "admin", "loja"];
  if (comuns.some((c) => baixo.includes(c))) {
    throw new Error("Essa senha é fácil demais. Evite palavras como 'senha', 'tablet' ou 'loja'.");
  }
  // Compara tambem sem espacos e sem pontuacao: "Gela Boca" tem de barrar
  // "zzgelabocazz". (Achado pelo proprio teste desta regra.)
  const soLetras = (x: string) => x.toLowerCase().replace(/[^a-z0-9]/g, "");
  const cru = soLetras(v);
  for (const p of proibidas) {
    const alvo = (p ?? "").trim().toLowerCase();
    const alvoCru = soLetras(alvo);
    if ((alvo.length >= 3 && baixo.includes(alvo)) || (alvoCru.length >= 3 && cru.includes(alvoCru))) {
      throw new Error("A senha não pode conter o nome da loja nem o nome ou o código da empresa.");
    }
  }
  return v;
}
