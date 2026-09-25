// O som de tarefa nova, no tablet da loja.
//
// SÓ no tablet. O celular da pessoa nunca recebe aviso — a política de uso diz
// que o sistema não manda notificação para o aparelho pessoal, e o Wisley não
// quer chegar perto disso.
//
// Três cuidados que a loja exige:
//
// 1. O navegador NÃO deixa tocar som antes de alguém tocar na tela. Por isso o
//    tablet mostra "Ativar som" enquanto estiver bloqueado, e um toque libera.
// 2. Depois de liberado, tem de continuar tocando com o tablet horas ligado
//    sem ninguém encostar. Por isso guardamos UM AudioContext vivo e o
//    religamos quando o navegador o suspende sozinho.
// 3. Chegando várias tarefas juntas, toca uma vez só; e no máximo uma vez a
//    cada 10 segundos.

/** No máximo um toque a cada 10 segundos, por mais tarefas que cheguem. */
const INTERVALO_MINIMO = 10_000;

const ARQUIVO = "/som/tarefa-nova.wav";

let contexto: AudioContext | null = null;
let amostra: AudioBuffer | null = null;
let ultimoToque = 0;

function AudioCtx(): typeof AudioContext | undefined {
  const w = window as unknown as { AudioContext?: typeof AudioContext; webkitAudioContext?: typeof AudioContext };
  return w.AudioContext ?? w.webkitAudioContext;
}

/** O som está liberado para tocar agora? */
export function somLiberado(): boolean {
  return contexto !== null && contexto.state === "running";
}

/**
 * Prepara o som. Chamada no primeiro toque da tela: é o que o navegador exige.
 * Devolve true quando ficou liberado.
 */
export async function liberarSom(): Promise<boolean> {
  const Ctx = AudioCtx();
  if (!Ctx) return false;
  try {
    if (!contexto) contexto = new Ctx();
    if (contexto.state === "suspended") await contexto.resume();
    if (!amostra) {
      const r = await fetch(ARQUIVO);
      amostra = await contexto.decodeAudioData(await r.arrayBuffer());
    }
    return contexto.state === "running";
  } catch {
    // Navegador de tablet sem suporte: o aviso fica só visual.
    return false;
  }
}

/**
 * Toca, respeitando o intervalo mínimo. Volume de 0 a 100.
 *
 * Religa o contexto quando o navegador o suspendeu sozinho — é o que faz o
 * som continuar funcionando depois de horas de tablet parado.
 */
export async function tocar(volume: number): Promise<void> {
  if (!contexto || !amostra) return;
  const agora = Date.now();
  if (agora - ultimoToque < INTERVALO_MINIMO) return;
  ultimoToque = agora;

  try {
    if (contexto.state === "suspended") await contexto.resume();
    const fonte = contexto.createBufferSource();
    fonte.buffer = amostra;
    const ganho = contexto.createGain();
    ganho.gain.value = Math.max(0, Math.min(100, volume)) / 100;
    fonte.connect(ganho);
    ganho.connect(contexto.destination);
    fonte.start();
  } catch {
    /* se não tocar, o aviso visual do cartão continua valendo */
  }
}

/**
 * Quais tarefas são NOVAS na fila.
 *
 * Compara o que já estava na tela com o que chegou. Na primeira carga não há
 * "antes", e aí nada é novo — senão o tablet tocaria ao ligar.
 */
export function tarefasNovas(antes: number[] | null, agora: number[]): number[] {
  if (antes === null) return [];
  const tinha = new Set(antes);
  return agora.filter((id) => !tinha.has(id));
}
