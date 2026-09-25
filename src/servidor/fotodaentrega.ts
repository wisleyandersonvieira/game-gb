// A prova da foto, feita pelo SERVIDOR.
//
// Antes, a impressão digital da imagem e a hora em que ela foi tirada eram
// calculadas no navegador e mandadas para cá. A revisão adversarial de
// 25/09/2026 mostrou que isso não prova nada: quem abre o DevTools manda a
// digital que quiser e a hora que quiser, e uma foto de ontem entra como se
// fosse de agora — sem nem o aviso "sem hora da foto" no Quadro.
//
// Agora o servidor BAIXA o arquivo que subiu e olha ele mesmo. O navegador não
// tem mais nada a dizer sobre a foto.
//
// O bilhete resolve a outra metade: o caminho que volta na entrega tem de ser
// um que este servidor emitiu, para aquela pessoa e aquela tarefa, há pouco.
// Sem ele, dava para declarar uma foto que nunca subiu — e o Quadro mostrava
// o cartão como se nada houvesse.
import { embaralhar } from "@/servidor/segredos";
import { lerHoraExif } from "@/colaborador/foto";

/** Quanto tempo vale o bilhete: o mesmo prazo do bot para concluir a entrega. */
const VALIDADE = 10 * 60_000;

/** Um bilhete só serve para esta foto, desta pessoa, desta tarefa, agora. */
export async function emitirBilhete(caminho: string, atribuicaoid: number, funcionarioid: number) {
  const emitidoem = Date.now();
  const assinatura = await embaralhar(`foto:${caminho}:${atribuicaoid}:${funcionarioid}:${emitidoem}`);
  return `${emitidoem}.${assinatura}`;
}

/**
 * Recusa quando o bilhete não confere. O prazo é medido pelo relógio do
 * SERVIDOR — o do aparelho não entra na conta.
 */
export async function conferirBilhete(
  bilhete: string,
  caminho: string,
  atribuicaoid: number,
  funcionarioid: number,
) {
  const [quando, assinatura] = bilhete.split(".");
  const emitidoem = Number(quando);
  if (!Number.isFinite(emitidoem) || !assinatura) throw new Error("Envio de foto inválido.");
  if (Date.now() - emitidoem > VALIDADE) {
    throw new Error("Passaram-se mais de 10 minutos. Abra a entrega de novo e tire outra foto.");
  }
  // Data no futuro: quem assinou fomos nós, então isso só aparece se alguém
  // mexeu no bilhete.
  if (emitidoem > Date.now() + 60_000) throw new Error("Envio de foto inválido.");

  const esperada = await embaralhar(`foto:${caminho}:${atribuicaoid}:${funcionarioid}:${emitidoem}`);
  if (!iguais(assinatura, esperada)) throw new Error("Envio de foto inválido.");
}

/** Comparação que não vaza por tempo de resposta. */
function iguais(a: string, b: string) {
  if (a.length !== b.length) return false;
  let diferenca = 0;
  for (let i = 0; i < a.length; i++) diferenca |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diferenca === 0;
}

export type ProvaDaFoto = {
  /** SHA-256 do arquivo: é o que impede a mesma foto de provar duas tarefas. */
  fotoidunico: string;
  /** Quando a foto foi tirada, se o arquivo trouxer. */
  horafoto: Date | null;
};

/**
 * Baixa o arquivo do Storage e tira dele as duas provas. Lança quando o
 * arquivo não existe — é assim que uma entrega "com foto" sem foto nenhuma
 * passa a ser recusada.
 */
export async function provaDaFoto(caminho: string): Promise<ProvaDaFoto> {
  const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
  const { data, error } = await supabaseAdmin.storage.from("entregas").download(caminho);
  if (error || !data) throw new Error("A foto não chegou. Tente enviar de novo.");

  const bytes = await data.arrayBuffer();
  if (bytes.byteLength === 0) throw new Error("A foto não chegou. Tente enviar de novo.");

  const resumo = await crypto.subtle.digest("SHA-256", bytes);
  const fotoidunico = [...new Uint8Array(resumo)].map((b) => b.toString(16).padStart(2, "0")).join("");

  // O cabeçalho EXIF vive no começo do arquivo; 128 KB dão e sobram.
  let horafoto: Date | null = null;
  try {
    horafoto = lerHoraExif(new DataView(bytes.slice(0, 128 * 1024)));
  } catch {
    horafoto = null;
  }

  return { fotoidunico, horafoto };
}

/**
 * A hora da foto tem de ser recente QUANDO ELA EXISTE (decisão do Wisley,
 * 26/09/2026). Quando não existe, a entrega passa e nasce marcada.
 */
export async function conferirHoraDaFoto(contaid: number, horafoto: Date | null) {
  if (!horafoto) return { semhorafoto: true };

  const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
  const { data } = await supabaseAdmin
    .from("configuracoes")
    .select("valor")
    .eq("contaid", contaid)
    .eq("chave", "MAX_DIFERENCA_FOTO_SEGUNDOS")
    .maybeSingle();

  // Valor estragado não pode virar "tolerância infinita": Number("abc") é NaN
  // e toda comparação com NaN é falsa, o que deixaria tudo passar.
  const segundos = Number(data?.valor);
  const tolerancia = (Number.isFinite(segundos) && segundos > 0 ? segundos : 120) * 1000;

  if (Math.abs(Date.now() - horafoto.getTime()) > tolerancia) {
    throw new Error("Esta foto não é de agora. Tire a foto na hora de entregar.");
  }
  return { semhorafoto: false };
}
