// PDFs gerados na hora, no navegador (não ficam guardados em lugar nenhum).
// Cabeçalho com o nome da conta (e da loja, quando houver); rodapé com
// "Gerado em dd/mm/aaaa hh:mm por <usuário>". Nenhum PDF leva CPF.
import { jsPDF } from "jspdf";
import { dataHoraBr } from "@/rh/datas";
import { supabase } from "@/integrations/supabase/client";
import { AVISO_DA_JORNADA, LEGENDA_DO_MAPA, rotuloDaHora, type Mapa } from "@/jornada/mapa";

const FUSO = "America/Sao_Paulo";
const MARGEM = 18;

// dataHoraBr mora em @/rh/datas: quem só precisa dela não deve baixar o
// gerador de PDF junto. Reexportado aqui para não quebrar quem já usava.
export { dataHoraBr };

const reais = (v: number) => new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(v);

/** Nome de quem está gerando o PDF (o nome do cadastro, ou o e-mail). */
export async function usuarioAtual() {
  const { data } = await supabase.auth.getUser();
  const u = data.user;
  const nome = typeof u?.user_metadata?.nome === "string" ? u.user_metadata.nome.trim() : "";
  return nome || u?.email || "usuário";
}

/** Nome (fantasia) da conta de quem está logado: é o que vai nos PDFs da equipe. */
export async function nomeDaConta() {
  const { data } = await supabase.from("contas").select("nomefantasia").limit(1).maybeSingle();
  return data?.nomefantasia ?? "";
}

class Documento {
  doc: jsPDF;
  y = MARGEM;
  /** Largura e altura da folha (A4 em pé, ou deitada). */
  W: number;
  H: number;
  largura: number;

  constructor(
    conta: string,
    loja: string | null | undefined,
    titulo: string,
    private opcoes: { marca?: boolean; paisagem?: boolean } = {},
  ) {
    this.doc = new jsPDF({ unit: "mm", format: "a4", orientation: opcoes.paisagem ? "landscape" : "portrait" });
    this.W = opcoes.paisagem ? 297 : 210;
    this.H = opcoes.paisagem ? 210 : 297;
    this.largura = this.W - MARGEM * 2;
    this.cabecalho(conta, loja, titulo);
  }

  /** Começa outra página com o mesmo cabeçalho (uma folha por pessoa). */
  novaPagina(conta: string, loja: string | null | undefined, titulo: string) {
    this.doc.addPage();
    this.y = MARGEM;
    this.cabecalho(conta, loja, titulo);
  }

  private cabecalho(conta: string, loja: string | null | undefined, titulo: string) {
    if (this.opcoes.marca) {
      // A marca, nas cores dela (docs/marca): "STGame" em azul, na mesma
      // linha acima do nome da empresa.
      this.doc.setFont("helvetica", "bold");
      this.doc.setFontSize(11);
      this.doc.setTextColor(31, 79, 224);
      this.doc.text("STGame", MARGEM, this.y);
      this.doc.setTextColor(11, 26, 58);
      this.y += 6;
    }
    this.doc.setFont("helvetica", "bold");
    this.doc.setFontSize(13);
    this.doc.text(conta || " ", MARGEM, this.y);
    if (loja) {
      this.doc.setFont("helvetica", "normal");
      this.doc.setFontSize(10);
      this.doc.text(loja, this.W - MARGEM, this.y, { align: "right" });
    }
    this.y += 4;
    this.doc.setLineWidth(0.3);
    this.doc.line(MARGEM, this.y, this.W - MARGEM, this.y);
    this.y += 10;
    this.doc.setFont("helvetica", "bold");
    this.doc.setFontSize(16);
    this.paragrafo(titulo, { tamanho: 16, negrito: true, alinhar: "center" });
    this.y += 2;
  }

  private cabe(altura: number) {
    if (this.y + altura > this.H - 22) {
      this.doc.addPage();
      this.y = MARGEM;
    }
  }

  paragrafo(texto: string, o: { tamanho?: number; negrito?: boolean; italico?: boolean; alinhar?: "left" | "center" } = {}) {
    const tamanho = o.tamanho ?? 11;
    this.doc.setFont("helvetica", o.negrito ? "bold" : o.italico ? "italic" : "normal");
    this.doc.setFontSize(tamanho);
    const linhas = this.doc.splitTextToSize(texto, this.largura) as string[];
    const altura = tamanho * 0.45;
    for (const l of linhas) {
      this.cabe(altura);
      if (o.alinhar === "center") this.doc.text(l, this.W / 2, this.y, { align: "center" });
      else this.doc.text(l, MARGEM, this.y);
      this.y += altura;
    }
    this.y += 2;
  }

  campo(rotulo: string, valor: string) {
    this.cabe(7);
    this.doc.setFont("helvetica", "bold");
    this.doc.setFontSize(11);
    this.doc.text(`${rotulo}:`, MARGEM, this.y);
    this.doc.setFont("helvetica", "normal");
    const linhas = this.doc.splitTextToSize(valor, this.largura - 42) as string[];
    linhas.forEach((l, i) => this.doc.text(l, MARGEM + 42, this.y + i * 5));
    this.y += Math.max(1, linhas.length) * 5 + 1.5;
  }

  secao(titulo: string) {
    this.y += 3;
    this.cabe(12);
    this.doc.setFont("helvetica", "bold");
    this.doc.setFontSize(12);
    this.doc.text(titulo, MARGEM, this.y);
    this.y += 2;
    this.doc.line(MARGEM, this.y, this.W - MARGEM, this.y);
    this.y += 6;
  }

  /** Um bloco em destaque: rótulo pequeno em cima, valor grande embaixo. */
  destaque(rotulo: string, valor: string, o: { mono?: boolean; tamanho?: number } = {}) {
    const tamanho = o.tamanho ?? 22;
    const altura = tamanho * 0.45 + 12;
    this.cabe(altura);
    this.doc.setDrawColor(31, 79, 224);
    this.doc.setLineWidth(0.6);
    this.doc.roundedRect(MARGEM, this.y, this.largura, altura, 2, 2);
    this.doc.setFont("helvetica", "normal");
    this.doc.setFontSize(9);
    this.doc.text(rotulo, MARGEM + 4, this.y + 5.5);
    this.doc.setFont(o.mono ? "courier" : "helvetica", "bold");
    this.doc.setFontSize(tamanho);
    this.doc.text(valor, this.W / 2, this.y + 7 + tamanho * 0.42, { align: "center" });
    this.doc.setDrawColor(0, 0, 0);
    this.doc.setLineWidth(0.3);
    this.y += altura + 4;
  }

  /** Uma imagem (o QR code), centralizada. */
  imagem(dataUrl: string, lado: number) {
    this.cabe(lado + 2);
    this.doc.addImage(dataUrl, "PNG", this.W / 2 - lado / 2, this.y, lado, lado);
    this.y += lado + 2;
  }

  /**
   * Uma tabela, com a linha de títulos repetida a cada página. A primeira
   * coluna é alinhada à esquerda; as outras, ao centro. Uma célula pode
   * ocupar várias colunas (span), ter fundo e cor de texto.
   */
  tabela(colunas: { titulo: string; largura: number }[], linhas: CelulaPdf[][], alturaLinha = 6.5) {
    const cinza = 205;
    const desenhar = (celulas: CelulaPdf[], titulos = false) => {
      let x = MARGEM;
      let c = 0;
      for (const cel of celulas) {
        const span = cel.span ?? 1;
        const w = colunas.slice(c, c + span).reduce((t, k) => t + k.largura, 0);
        const fundo = titulos ? ([11, 26, 58] as Cor) : cel.fundo;
        if (fundo) {
          this.doc.setFillColor(...fundo);
          this.doc.rect(x, this.y, w, alturaLinha, "F");
        }
        this.doc.setDrawColor(cinza, cinza, cinza);
        this.doc.rect(x, this.y, w, alturaLinha, "S");
        this.doc.setFont("helvetica", titulos || cel.negrito ? "bold" : cel.italico ? "italic" : "normal");
        this.doc.setFontSize(titulos ? 8 : (cel.tamanho ?? 8.5));
        this.doc.setTextColor(...(titulos ? ([255, 255, 255] as Cor) : (cel.cor ?? [11, 26, 58])));
        const texto = (this.doc.splitTextToSize(cel.texto, w - 2.5) as string[])[0] ?? "";
        const base = this.y + alturaLinha / 2 + 1.2;
        if (c === 0) this.doc.text(texto, x + 1.5, base);
        else this.doc.text(texto, x + w / 2, base, { align: "center" });
        x += w;
        c += span;
      }
      this.doc.setTextColor(11, 26, 58);
      this.doc.setDrawColor(0, 0, 0);
      this.y += alturaLinha;
    };
    const titulos = colunas.map((k) => ({ texto: k.titulo }));
    this.cabe(alturaLinha * 2);
    desenhar(titulos, true);
    for (const linha of linhas) {
      if (this.y + alturaLinha > this.H - 22) {
        this.doc.addPage();
        this.y = MARGEM;
        desenhar(titulos, true);
      }
      desenhar(linha);
    }
    this.y += 4;
  }

  salvar(nomeArquivo: string, usuario: string, extra: { emitidoEm?: string | Date; aviso?: string } = {}) {
    const total = this.doc.getNumberOfPages();
    const agora = dataHoraBr(extra.emitidoEm ?? new Date());
    for (let p = 1; p <= total; p++) {
      this.doc.setPage(p);
      this.doc.setFont("helvetica", "italic");
      this.doc.setFontSize(8);
      if (extra.aviso) {
        this.doc.setFont("helvetica", "bold");
        this.doc.text(extra.aviso, this.W / 2, this.H - 15, { align: "center" });
        this.doc.setFont("helvetica", "italic");
      }
      this.doc.text(`Gerado em ${agora} por ${usuario}`, MARGEM, this.H - 10);
      this.doc.text(`Página ${p} de ${total}`, this.W - MARGEM, this.H - 10, { align: "right" });
    }
    this.doc.save(nomeArquivo);
  }
}

type Cor = [number, number, number];
type CelulaPdf = {
  texto: string;
  span?: number;
  fundo?: Cor;
  cor?: Cor;
  negrito?: boolean;
  italico?: boolean;
  tamanho?: number;
};

const arquivo = (prefixo: string, texto: string) =>
  `${prefixo}-${texto.normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/[^\w-]+/g, "-").replace(/-+/g, "-").slice(0, 40)}.pdf`;

/** O comunicado, para imprimir ou afixar. */
export async function pdfComunicado(c: { titulo: string; conteudo: string; publicadoem: string; para: string }) {
  const [conta, usuario] = await Promise.all([nomeDaConta(), usuarioAtual()]);
  const d = new Documento(conta, null, "Comunicado interno");
  d.campo("Assunto", c.titulo);
  d.campo("Publicado em", dataHoraBr(c.publicadoem));
  d.campo("Para", c.para);
  d.secao("Texto");
  d.paragrafo(c.conteudo);
  d.salvar(arquivo("comunicado", c.titulo), usuario);
}

type ReciboCiencia = {
  conta: string;
  pessoa: string;
  titulo: string;
  conteudo: string;
  publicadoem: string;
  ciencia: string;
  origem: string | null;
  protocolo: string;
  pontos: number;
};

/** Recibo de ciência de um comunicado. */
export async function pdfReciboCiencia(r: ReciboCiencia) {
  const usuario = await usuarioAtual();
  const d = new Documento(r.conta, null, "Recibo de ciência de comunicado interno");
  d.campo("Funcionário", r.pessoa);
  d.campo("Comunicado", r.titulo);
  d.campo("Publicado em", dataHoraBr(r.publicadoem));
  d.secao("Texto do comunicado");
  d.paragrafo(r.conteudo);
  d.secao("Confirmação de ciência");
  d.paragrafo(`${r.pessoa} recebeu, leu e está ciente do conteúdo do comunicado acima.`, { italico: true });
  d.campo("Data e hora", dataHoraBr(r.ciencia));
  d.campo("Registro", r.origem === "funcionario" ? "Confirmado pelo próprio funcionário" : "Registrado pelo gestor");
  d.campo("Protocolo", r.protocolo);
  if (r.pontos > 0) d.campo("Pontos", `${r.pontos} pontos pela ciência`);
  d.salvar(arquivo("recibo-ciencia", `${r.pessoa}-${r.protocolo}`), usuario);
}

type ReciboResgate = {
  conta: string;
  loja: string | null;
  pessoa: string;
  premio: string;
  pontos: number;
  situacao: string;
  solicitadoem: string;
  entregueem: string | null;
  protocolo: string;
  movimentos: { data: string; tipo: string; pontos: number; descricao: string; saldoantes: number; saldodepois: number }[];
};

const TIPO: Record<string, string> = {
  resgate: "Resgate",
  cancelamento_resgate: "Cancelamento",
  estorno_resgate: "Estorno",
};

/** Recibo de resgate de prêmio, montado a partir do livro de pontos. */
export async function pdfReciboResgate(r: ReciboResgate) {
  const usuario = await usuarioAtual();
  const d = new Documento(r.conta, r.loja, "Recibo de resgate de prêmio");
  d.campo("Funcionário", r.pessoa);
  d.campo("Prêmio", r.premio);
  d.campo("Pontos", `${r.pontos} pontos`);
  d.campo("Situação", r.situacao);
  d.campo("Solicitado em", dataHoraBr(r.solicitadoem));
  if (r.entregueem) d.campo("Entregue em", dataHoraBr(r.entregueem));
  d.campo("Protocolo", r.protocolo);
  d.secao("Livro de pontos");
  for (const m of r.movimentos) {
    d.paragrafo(
      `${dataHoraBr(m.data)} · ${TIPO[m.tipo] ?? m.tipo}: ${m.pontos > 0 ? "+" : ""}${m.pontos} pontos · saldo antes ${m.saldoantes}, depois ${m.saldodepois}`,
      { tamanho: 10 },
    );
  }
  d.y += 8;
  d.paragrafo("_________________________________________", { alinhar: "center" });
  d.paragrafo(`${r.pessoa}`, { alinhar: "center", tamanho: 10 });
  d.salvar(arquivo("recibo-resgate", `${r.pessoa}-${r.protocolo}`), usuario);
}

export { reais };

// ---------------------------------------------------------------------------
// Folha de instruções de acesso (27/09/2026)
// ---------------------------------------------------------------------------

/** O que o servidor manda para montar uma folha (ver emitirFolhasDeAcesso). */
export type DadosDaFolha = {
  nome: string;
  cargo: string | null;
  lojas: string[];
  cpfmascarado: string | null;
  conta: string;
  codigoempresa: string;
  codigo: string;
  expiraem: string;
  redefinido: boolean;
  emitidaem: string;
};

/** O endereço da equipe da empresa. O MESMO de "Lojas e links da TV". */
export const enderecoDaEquipe = (codigoempresa: string, origem = window.location.origin) =>
  `${origem}/e/${codigoempresa}`;

const dataBr = (iso: string) =>
  new Intl.DateTimeFormat("pt-BR", { timeZone: FUSO, day: "2-digit", month: "2-digit", year: "numeric" }).format(
    new Date(iso),
  );

/**
 * Uma folha por pessoa, no mesmo arquivo. O QR leva SÓ ao endereço da
 * empresa — nunca ao código de acesso: uma folha esquecida no balcão não pode
 * virar entrada de um toque, lida de longe.
 */
export async function pdfFolhasDeAcesso(folhas: DadosDaFolha[], nomeArquivo: string) {
  if (folhas.length === 0) return;
  const [{ default: QRCode }, usuario] = await Promise.all([import("qrcode"), usuarioAtual()]);
  const TITULO = "Instruções de acesso ao STGame";
  let d: Documento | null = null;

  for (const f of folhas) {
    const loja = f.lojas.join(" · ") || null;
    if (!d) d = new Documento(f.conta, loja, TITULO, { marca: true });
    else d.novaPagina(f.conta, loja, TITULO);

    d.campo("Nome", f.nome);
    d.campo("Cargo", f.cargo || "—");
    d.campo("Loja", loja || "—");
    if (f.cpfmascarado) d.campo("CPF", f.cpfmascarado);

    const endereco = enderecoDaEquipe(f.codigoempresa);
    const qr = await QRCode.toDataURL(endereco, { margin: 1, width: 360, errorCorrectionLevel: "M" });
    d.y += 2;
    d.imagem(qr, 42);
    d.paragrafo(endereco, { alinhar: "center", negrito: true, tamanho: 11 });
    d.campo("Código da empresa", f.codigoempresa);
    d.y += 2;
    d.destaque("Seu código de acesso (primeiro acesso)", f.codigo, { mono: true, tamanho: 26 });

    d.secao("Como entrar");
    d.paragrafo(`1. Abra o endereço acima no celular, ou leia o QR code com a câmera.`);
    d.paragrafo(`2. Digite o seu CPF.`);
    d.paragrafo(
      `3. Digite o código de acesso desta folha. Em seguida, crie a sua senha e o seu PIN de 6 dígitos — o PIN é o que você digita no tablet da loja para aceitar e entregar tarefas.`,
    );

    d.secao("Importante");
    d.paragrafo(`• O código vale até ${dataBr(f.expiraem)} e serve UMA vez só.`);
    d.paragrafo(`• A senha e o PIN são pessoais: não conte para ninguém, nem para o gestor.`);
    if (f.redefinido) {
      d.paragrafo(
        `• O seu acesso foi redefinido em ${dataHoraBr(f.emitidaem)}: a senha e o PIN que você tinha deixaram de valer. Crie novos com este código.`,
        { negrito: true },
      );
    }
  }

  d!.salvar(nomeArquivo, usuario, {
    emitidoEm: folhas[0].emitidaem,
    aviso: "Este documento dá acesso ao sistema — não deixe à vista.",
  });
}

/** acesso-<primeiro nome>-<data>.pdf, ou acessos-<loja>-<data>.pdf em lote. */
export function nomeDaFolha(folhas: { nome: string; lojas: string[] }[], hoje: string) {
  const limpar = (t: string) =>
    t.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
  if (folhas.length === 1) return `acesso-${limpar(folhas[0].nome.split(/\s+/)[0] ?? "pessoa")}-${hoje}.pdf`;
  const lojas = new Set(folhas.flatMap((f) => f.lojas));
  const loja = lojas.size === 1 ? [...lojas][0] : "equipe";
  return `acessos-${limpar(loja)}-${hoje}.pdf`;
}

// ---------------------------------------------------------------------------
// Mapa da jornada (27/09/2026)
// ---------------------------------------------------------------------------

const VERDE: Cor = [220, 243, 228];
const VERDE_TEXTO: Cor = [21, 110, 60];
const ROSA: Cor = [252, 226, 230];
const VERMELHO: Cor = [200, 40, 60];
const CINZA_TEXTO: Cor = [110, 118, 135];
const AZUL_CLARO: Cor = [226, 234, 252];

/**
 * O mapa, deitado, igual ao da tela: uma linha por pessoa (cargo e nome, e
 * nada além — sem CPF), o total de cada hora e a legenda. No rodapé, o mesmo
 * aviso da tela: parece documento de escala, então o aviso vai junto.
 */
export async function pdfMapaDaJornada(m: { loja: string; dia: string; mapa: Mapa }) {
  const [conta, usuario] = await Promise.all([nomeDaConta(), usuarioAtual()]);
  const d = new Documento(conta, m.loja, `Mapa da jornada — ${m.dia}`, { marca: true, paisagem: true });
  const { horas, linhas, totais } = m.mapa;

  const primeira = 64;
  const cada = horas.length > 0 ? Math.min(16, (d.largura - primeira) / horas.length) : d.largura - primeira;
  const colunas = [
    { titulo: "Cargo | Nome", largura: primeira },
    ...(horas.length > 0 ? horas.map((h) => ({ titulo: rotuloDaHora(h), largura: cada })) : [{ titulo: "", largura: cada }]),
  ];
  const nome = (l: (typeof linhas)[number]) =>
    l.pessoa.cargo ? `${l.pessoa.cargo.toUpperCase()} | ${l.pessoa.nome}` : l.pessoa.nome;

  const corpo: CelulaPdf[][] = linhas.map((l) => {
    if (!l.celulas) {
      return [{ texto: nome(l) }, { texto: l.aviso ?? "", span: Math.max(1, horas.length), italico: true, cor: CINZA_TEXTO }];
    }
    return [
      { texto: nome(l) },
      ...l.celulas.map<CelulaPdf>((c) =>
        c.tipo === "expediente"
          ? { texto: "X", fundo: VERDE, cor: VERDE_TEXTO, negrito: true }
          : c.tipo === "intervalo"
            ? { texto: "•••", fundo: ROSA, cor: VERMELHO, negrito: true }
            : c.tipo === "parcial"
              ? { texto: c.hora, cor: VERDE_TEXTO, tamanho: 6.5 }
              : { texto: "" },
      ),
    ];
  });
  if (horas.length > 0) {
    corpo.push([
      { texto: "TOTAL DE COLABORADORES", negrito: true, fundo: AZUL_CLARO },
      ...totais.map<CelulaPdf>((t) => ({ texto: String(t), negrito: true, fundo: AZUL_CLARO, cor: t === 0 ? VERMELHO : undefined })),
    ]);
  }
  d.tabela(colunas, corpo);

  if (horas.length === 0) d.paragrafo("Ninguém desta loja tem expediente neste dia.", { italico: true });
  d.paragrafo("Legenda", { negrito: true, tamanho: 9 });
  for (const l of LEGENDA_DO_MAPA) d.paragrafo(l, { tamanho: 8.5 });

  d.salvar(arquivo("mapa", `${m.loja}-${m.dia}`), usuario, { aviso: AVISO_DA_JORNADA });
}
