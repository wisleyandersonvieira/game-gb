// A medição do aceite e da entrega no tablet (26/09/2026).
//
// A /medir não serve aqui: ela é do gestor e mede o que o NAVEGADOR pergunta
// ao banco. O tablet não fala com o banco: fala com o servidor, que fala com o
// banco. Então o tempo é medido nas duas pontas — o tablet cronometra o que ele
// vê (do 6º dígito até o cartão mudar), o servidor devolve quanto cada etapa
// levou lá dentro, e a conta das duas dá a rede.
//
// Como ligar: abra o tablet com `/tablet?medir=1`. Para comparar com o caminho
// antigo no mesmo aparelho e na mesma rede: `/tablet?medir=antigo`. Para
// desligar: `/tablet?medir=0`. Vale só nesta aba.
//
// Nada disso sai do aparelho, e o PIN não entra em conta nenhuma.

export type CaminhoMedido = "novo" | "antigo";

export type Medida = {
  quando: number;
  acao: "aceite" | "entrega";
  caminho: CaminhoMedido;
  /** Do 6º dígito até o cartão mudar na tela. */
  total: number;
  etapas: [string, number][];
  /** O que não é tempo: tamanho da foto, onde o servidor rodou. */
  detalhes: string[];
};

/** O que o tablet cronometrou do lado dele, em ms. */
export type TemposDoTablet = {
  /** A chamada principal (aceitar ou entregar), do envio à resposta. */
  chamada: number;
  /** Quanto se ESPEROU pela redução da foto (ela começa quando a foto é escolhida). */
  fotoReducao?: number;
  fotoOriginalKb?: number;
  fotoEnviadaKb?: number;
  /** Quanto se ESPEROU pela autorização (ela é pedida quando a janela abre). */
  fotoAutorizacao?: number;
  fotoEnvio?: number;
  /** Só no caminho antigo: a recarga da fila depois da ação. */
  recarga?: number;
  recargaServidor?: number;
  /** Da resposta até a tela redesenhada. */
  desenho: number;
};

const CHAVE = "stgame.medir-tablet";

/** Lê `?medir=` e guarda na aba. Devolve o caminho medido, ou null (desligada). */
export function modoDeMedicao(busca: string = typeof location === "undefined" ? "" : location.search): CaminhoMedido | null {
  const pedido = new URLSearchParams(busca).get("medir");
  try {
    if (pedido === "0") sessionStorage.removeItem(CHAVE);
    else if (pedido === "antigo") sessionStorage.setItem(CHAVE, "antigo");
    else if (pedido !== null) sessionStorage.setItem(CHAVE, "novo");
    const guardado = sessionStorage.getItem(CHAVE);
    return guardado === "antigo" ? "antigo" : guardado === "novo" ? "novo" : null;
  } catch {
    // Navegador que não deixa guardar: vale só o que veio no endereço.
    if (pedido === "antigo") return "antigo";
    if (pedido !== null && pedido !== "0") return "novo";
    return null;
  }
}

const ROTULOS: Record<string, string> = {
  token: "Servidor: conferir o login do tablet",
  tablet: "Servidor → banco: que tablet é este (1 ida)",
  tablet_meuacesso: "Servidor → banco: meu_acesso (1 ida)",
  tablet_vinculo: "Servidor → banco: vínculo do tablet (1 ida)",
  trava_abrir: "Servidor → banco: abrir a trava (1 ida)",
  pin: "Servidor → banco: conferir o PIN (1 ida)",
  trava_fechar: "Servidor → banco: fechar a trava (1 ida)",
  aceite: "Servidor → banco: rodízio + gravar o aceite (1 ida)",
  entrega: "Servidor → banco: gravar a entrega (1 ida)",
  foto_baixar_e_conferir: "Foto: servidor baixa e confere hash + EXIF",
  foto_hora: "Foto: tolerância da hora (1 ida)",
};

const arred = (n: number) => Math.max(0, Math.round(n));

/**
 * Monta a lista de etapas de uma medida, na ordem em que acontecem.
 *
 * A rede é o que sobra: o tablet viu a chamada levar X, o servidor diz que
 * trabalhou Y, então X − Y foi ida e volta entre tablet e servidor. O mesmo
 * dentro da ida única ao banco: ela levou B, o banco trabalhou P + A + F, e
 * B − (P + A + F) foi a rede entre servidor e banco. Nunca negativo: os dois
 * relógios são diferentes, e arredondar não pode inventar tempo.
 */
export function montarEtapas(
  acao: Medida["acao"],
  t: TemposDoTablet,
  servidor: Record<string, number>,
): [string, number][] {
  const etapas: [string, number][] = [];
  const add = (rotulo: string, ms: number | undefined) => {
    if (ms !== undefined && Number.isFinite(ms)) etapas.push([rotulo, arred(ms)]);
  };

  add("Foto: esperar a redução no tablet", t.fotoReducao);
  add("Foto: esperar a autorização de envio", t.fotoAutorizacao);
  add("Foto: envio do arquivo (tablet → Storage)", t.fotoEnvio);

  const trabalhoServidor = servidor.servidor ?? 0;
  add("Rede: tablet ↔ servidor", t.chamada - trabalhoServidor);

  for (const [k, v] of Object.entries(servidor)) {
    if (k === "servidor" || k === "banco" || k.startsWith("banco_")) continue;
    add(ROTULOS[k] ?? k, v);
  }

  // A ida única ao banco (caminho novo), aberta em rede + o que o banco fez.
  if (servidor.banco !== undefined) {
    const pin = servidor.banco_pin ?? 0;
    const feito = servidor.banco_acao ?? 0;
    const fila = servidor.banco_fila ?? 0;
    add("Rede: servidor ↔ banco (a ida única)", servidor.banco - pin - feito - fila);
    add("No banco: trava + conferir o PIN", pin);
    add(acao === "aceite" ? "No banco: rodízio + gravar o aceite" : "No banco: gravar a entrega", feito);
    add("No banco: montar a fila já atualizada", fila);
  }

  if (t.recarga !== undefined) {
    add("Recarga da fila (outra chamada inteira)", t.recarga);
  }
  add("Desenho da tela", t.desenho);
  return etapas;
}

/**
 * O que ajuda a ler os tempos sem ser tempo. A foto: quantos KB a câmera deu e
 * quantos subiram (o envio e o download dependem disso). O servidor: em que
 * cidade do Cloudflare rodou e se partiu a frio — uma partida a frio carrega o
 * programa antes de atender e aparece como "rede", sem ser rede.
 */
export function montarDetalhes(
  t: Pick<TemposDoTablet, "fotoOriginalKb" | "fotoEnviadaKb" | "fotoEnvio">,
  onde?: { colo: string; frio: boolean; fotokb?: number },
): string[] {
  const d: string[] = [];
  if (t.fotoOriginalKb !== undefined && t.fotoEnviadaKb !== undefined) {
    d.push(
      t.fotoEnviadaKb < t.fotoOriginalKb
        ? `Foto: ${t.fotoOriginalKb} KB da câmera, ${t.fotoEnviadaKb} KB enviados`
        : `Foto: ${t.fotoOriginalKb} KB, enviada sem redução`,
    );
    if (t.fotoEnvio && t.fotoEnvio > 0) {
      d.push(`Envio do tablet: ${Math.round(t.fotoEnviadaKb / (t.fotoEnvio / 1000))} KB/s`);
    }
  }
  if (onde?.fotokb !== undefined) d.push(`O servidor recebeu ${onde.fotokb} KB para conferir`);
  if (onde) {
    d.push(`Servidor rodou em ${onde.colo || "?"}${onde.frio ? " — PARTIDA A FRIO (1º pedido desta instância)" : ""}`);
  }
  return d;
}
