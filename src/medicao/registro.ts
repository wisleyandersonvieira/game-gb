// Medição de desempenho (24/09/2026). Grava quanto cada chamada ao Supabase
// demorou, direto no navegador de quem está usando — é o único lugar onde o
// número é real: depende da distância até o servidor e da conexão do momento.
//
// Não muda comportamento nenhum: só observa. Fica tudo na memória da aba e
// some ao recarregar. Nada é enviado para lugar nenhum.
export type Chamada = {
  /** Em que tela a chamada aconteceu. */
  tela: string;
  /** "banco" (PostgREST), "login" (Auth) ou "servidor" (funções de servidor). */
  tipo: "banco" | "login" | "servidor" | "arquivo";
  /** Nome curto: a função ou a tabela. */
  nome: string;
  /** Milissegundos desde o carregamento da página. */
  inicio: number;
  fim: number;
};

const LIMITE = 500;
export const chamadas: Chamada[] = [];

function nomeDaChamada(url: string): { tipo: Chamada["tipo"]; nome: string } {
  try {
    const u = new URL(url, window.location.origin);
    if (u.pathname.includes("/auth/v1/")) {
      return { tipo: "login", nome: u.pathname.split("/auth/v1/")[1] ?? "auth" };
    }
    if (u.pathname.includes("/rest/v1/rpc/")) {
      return { tipo: "banco", nome: u.pathname.split("/rpc/")[1] ?? "rpc" };
    }
    if (u.pathname.includes("/rest/v1/")) {
      return { tipo: "banco", nome: u.pathname.split("/rest/v1/")[1] ?? "tabela" };
    }
    if (u.pathname.includes("/storage/v1/")) {
      return { tipo: "arquivo", nome: u.pathname.split("/storage/v1/")[1] ?? "arquivo" };
    }
    if (u.pathname.startsWith("/_serverFn/")) {
      return { tipo: "servidor", nome: u.pathname.replace("/_serverFn/", "") };
    }
    return { tipo: "banco", nome: u.pathname };
  } catch {
    return { tipo: "banco", nome: url.slice(0, 60) };
  }
}

/** Envolve o fetch para cronometrar. Fora do navegador, devolve o original. */
export function fetchMedido(original: typeof fetch = fetch): typeof fetch {
  if (typeof window === "undefined") return original;
  return async (entrada: Parameters<typeof fetch>[0], init?: Parameters<typeof fetch>[1]) => {
    const url =
      typeof entrada === "string" ? entrada : entrada instanceof URL ? entrada.href : entrada.url;
    const inicio = performance.now();
    try {
      return await original(entrada, init);
    } finally {
      const { tipo, nome } = nomeDaChamada(url);
      chamadas.push({ tela: window.location.pathname, tipo, nome, inicio, fim: performance.now() });
      if (chamadas.length > LIMITE) chamadas.splice(0, chamadas.length - LIMITE);
    }
  };
}

export function limparMedicao() {
  chamadas.length = 0;
}

export type ResumoDaTela = {
  tela: string;
  chamadas: number;
  /** Do começo da primeira até o fim da última: o que a pessoa esperou. */
  parede: number;
  /** Somando cada chamada: se for bem maior que a parede, foram em paralelo. */
  somado: number;
  /** Quantas começaram só depois de outra terminar (efeito cascata). */
  emCascata: number;
  maisLenta: { nome: string; ms: number } | null;
  porTipo: Record<Chamada["tipo"], number>;
};

/** Junta as chamadas por tela e diz se foram em sequência ou ao mesmo tempo. */
export function resumir(lista: Chamada[] = chamadas): ResumoDaTela[] {
  const porTela = new Map<string, Chamada[]>();
  for (const c of lista) {
    const atual = porTela.get(c.tela) ?? [];
    atual.push(c);
    porTela.set(c.tela, atual);
  }

  return [...porTela.entries()].map(([tela, cs]) => {
    const ordenadas = [...cs].sort((a, b) => a.inicio - b.inicio);
    const parede = Math.max(...cs.map((c) => c.fim)) - Math.min(...cs.map((c) => c.inicio));
    const somado = cs.reduce((t, c) => t + (c.fim - c.inicio), 0);

    // Cascata: a chamada começou DEPOIS que todas as anteriores terminaram.
    let emCascata = 0;
    for (let i = 1; i < ordenadas.length; i++) {
      const anteriorTerminou = Math.max(...ordenadas.slice(0, i).map((c) => c.fim));
      if (ordenadas[i].inicio >= anteriorTerminou - 5) emCascata++;
    }

    const maior = cs.reduce((a, b) => (b.fim - b.inicio > a.fim - a.inicio ? b : a));
    const porTipo: Record<Chamada["tipo"], number> = { banco: 0, login: 0, servidor: 0, arquivo: 0 };
    for (const c of cs) porTipo[c.tipo] += 1;

    return {
      tela,
      chamadas: cs.length,
      parede: Math.round(parede),
      somado: Math.round(somado),
      emCascata,
      maisLenta: { nome: maior.nome, ms: Math.round(maior.fim - maior.inicio) },
      porTipo,
    };
  });
}
