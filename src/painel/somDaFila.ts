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

// O arquivo é gravado NORMALIZADO perto do máximo (pico em 0,95 da escala).
// Amplificar no código distorceria: o ganho aqui embaixo só abaixa, nunca
// passa de 1. Em 25/09/2026 o pico saiu de 0,237 para 0,95 — 4,0046 vezes
// mais alto — e os três níveis foram escolhidos para o "médio" ficar uns 50%
// acima do que a loja ouvia antes.
const ARQUIVO = "/som/tarefa-nova.wav";

/** Os três níveis da janela de configuração, no ganho de 0 a 100. */
export const NIVEIS = { baixo: 10, medio: 19, alto: 45 } as const;

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

// ---------------------------------------------------------------------------
// A REPETIÇÃO do aviso, enquanto ninguém aceita a tarefa.
//
// Por que existe: o som toca uma vez quando a tarefa chega. Se a loja estava
// no movimento, ninguém ouviu, e a tarefa fica parada até alguém olhar o
// tablet. A repetição é um empurrão — não um alarme.
//
// As regras, todas decididas aqui para poderem ser testadas sem navegador:
//
// 1. Conta a partir do momento em que a tarefa ficou DISPONÍVEL, que já é a
//    hora programada de liberação quando existe uma (`disponiveldesde`).
// 2. Para na hora em que alguém aceita: a tarefa sai da lista de parados e sai
//    daqui junto.
// 3. No máximo 3 repetições por tarefa. Depois disso, silêncio — fica só o
//    aviso visual que já existe (cartão destacado e cronômetro vermelho).
// 4. Com várias tarefas paradas, toca UMA vez por rodada, nunca um som por
//    tarefa.
// 5. Intervalo mínimo de 5 minutos, mesmo que alguém grave menos no banco.
// ---------------------------------------------------------------------------

/** No máximo três empurrões por tarefa. Depois, só o aviso visual. */
export const MAX_REPETICOES = 3;

/** Nunca menos de 5 minutos entre avisos, por mais que o banco diga. */
export const MINIMO_MINUTOS = 5;

export type TarefaParada = {
  atribuicaoid: number;
  /** Desde quando está disponível. Sem isto, não há de onde contar. */
  disponiveldesde: string | null;
};

export type EstadoRepeticao = {
  /** Quantas repetições já tocaram por tarefa. */
  tocadas: Record<number, number>;
  /** Quando foi o último aviso repetido (ms). 0 = nenhum ainda. */
  ultimo: number;
};

export const SEM_REPETICAO: EstadoRepeticao = { tocadas: {}, ultimo: 0 };

/**
 * Decide se o tablet toca AGORA, e devolve o estado novo.
 *
 * `marcarSemTocar` é a primeira carga da tela: a tarefa pode estar parada há
 * meia hora, e o tablet não pode dar três toques de uma vez só porque alguém
 * abriu a página. Nessa passada a gente só anota onde cada tarefa está.
 */
export function decidirRepeticao(p: {
  agora: number;
  paradas: TarefaParada[];
  /** Minutos escolhidos na loja. 0 = repetição desligada. */
  intervaloMinutos: number;
  estado: EstadoRepeticao;
  marcarSemTocar?: boolean;
}): { tocar: boolean; estado: EstadoRepeticao } {
  const tocadas: Record<number, number> = {};
  // Tarefa que saiu da lista (foi aceita) sai daqui: se um dia voltar, começa
  // de novo. É o que faz a repetição PARAR no aceite.
  for (const t of p.paradas) {
    const antes = p.estado.tocadas[t.atribuicaoid];
    if (antes !== undefined) tocadas[t.atribuicaoid] = antes;
  }
  const estado = { tocadas, ultimo: p.estado.ultimo };

  if (p.intervaloMinutos <= 0) return { tocar: false, estado };

  const intervalo = Math.max(MINIMO_MINUTOS, p.intervaloMinutos) * 60_000;

  // Quantas repetições cada tarefa já merecia ter ouvido.
  const devidas = new Map<number, number>();
  for (const t of p.paradas) {
    if (!t.disponiveldesde) continue;
    const desde = Date.parse(t.disponiveldesde);
    if (!Number.isFinite(desde)) continue;
    const quantas = Math.min(MAX_REPETICOES, Math.floor((p.agora - desde) / intervalo));
    if (quantas > (tocadas[t.atribuicaoid] ?? 0)) devidas.set(t.atribuicaoid, quantas);
  }

  if (devidas.size === 0) return { tocar: false, estado };

  // Na primeira carga, e quando o último aviso foi há pouco, a gente anota sem
  // tocar. Anotar é o que impede o tablet de acumular atraso e despejar vários
  // toques seguidos depois.
  if (p.marcarSemTocar) {
    for (const [id, quantas] of devidas) tocadas[id] = quantas;
    return { tocar: false, estado };
  }
  if (estado.ultimo > 0 && p.agora - estado.ultimo < intervalo) {
    return { tocar: false, estado };
  }

  // UM som, por mais tarefas que estejam paradas: todas as devidas ficam
  // marcadas nesta mesma rodada.
  for (const [id, quantas] of devidas) tocadas[id] = quantas;
  return { tocar: true, estado: { tocadas, ultimo: p.agora } };
}
