import confetti from "canvas-confetti";

/** Mesmos fogos do painel antigo: 5 segundos, dos dois lados da tela. */
export function dispararFogos() {
  const duracao = 5000;
  const fim = Date.now() + duracao;
  const padrao = { startVelocity: 30, spread: 360, ticks: 60, zIndex: 9999 };
  // Cores da marca (ouro, azul, sucesso), lidas do tema; o confete precisa de hex.
  const tema = getComputedStyle(document.documentElement);
  const cores = ["--stg-ouro", "--stg-azul", "--stg-azul-strong", "--stg-sucesso", "--stg-on-noite"]
    .map((v) => tema.getPropertyValue(v).trim())
    .filter((c) => c.startsWith("#"));
  const entre = (min: number, max: number) => Math.random() * (max - min) + min;

  const intervalo = window.setInterval(() => {
    const falta = fim - Date.now();
    if (falta <= 0) {
      window.clearInterval(intervalo);
      return;
    }
    const particleCount = 50 * (falta / duracao);
    confetti({ ...padrao, particleCount, shapes: ["star"], colors: cores, origin: { x: entre(0.1, 0.3), y: Math.random() - 0.2 } });
    confetti({ ...padrao, particleCount, shapes: ["star"], colors: cores, origin: { x: entre(0.7, 0.9), y: Math.random() - 0.2 } });
  }, 250);
}

/**
 * Solta os fogos uma vez por dia em cada tela, para cada loja.
 * Se o navegador não guardar nada (aba anônima), solta mesmo assim, uma vez
 * por carregamento de página.
 */
const jaSoltouNestaPagina = new Set<string>();

export function soltarFogosUmaVezPorDia(chaveDaLoja: string, dia: string) {
  const chave = `gamegb.fogos.${chaveDaLoja}.${dia}`;
  if (jaSoltouNestaPagina.has(chave)) return;
  jaSoltouNestaPagina.add(chave);
  try {
    if (localStorage.getItem(chave)) return;
    localStorage.setItem(chave, "1");
  } catch {
    /* sem memória: a trava da página já basta */
  }
  dispararFogos();
}
