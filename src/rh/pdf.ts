// PDFs gerados na hora, no navegador (não ficam guardados em lugar nenhum).
// Cabeçalho com o nome da conta (e da loja, quando houver); rodapé com
// "Gerado em dd/mm/aaaa hh:mm por <usuário>". Nenhum PDF leva CPF.
import { jsPDF } from "jspdf";
import { dataHoraBr } from "@/rh/datas";
import { supabase } from "@/integrations/supabase/client";

const FUSO = "America/Sao_Paulo";
const MARGEM = 18;
const LARGURA = 210 - MARGEM * 2;

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

/** Nome da conta de quem está logado. */
export async function nomeDaConta() {
  const { data } = await supabase.from("contas").select("nome").limit(1).maybeSingle();
  return data?.nome ?? "";
}

class Documento {
  doc = new jsPDF({ unit: "mm", format: "a4" });
  y = MARGEM;

  constructor(conta: string, loja: string | null | undefined, titulo: string) {
    this.doc.setFont("helvetica", "bold");
    this.doc.setFontSize(13);
    this.doc.text(conta || " ", MARGEM, this.y);
    if (loja) {
      this.doc.setFont("helvetica", "normal");
      this.doc.setFontSize(10);
      this.doc.text(loja, 210 - MARGEM, this.y, { align: "right" });
    }
    this.y += 4;
    this.doc.setLineWidth(0.3);
    this.doc.line(MARGEM, this.y, 210 - MARGEM, this.y);
    this.y += 10;
    this.doc.setFont("helvetica", "bold");
    this.doc.setFontSize(16);
    this.paragrafo(titulo, { tamanho: 16, negrito: true, alinhar: "center" });
    this.y += 2;
  }

  private cabe(altura: number) {
    if (this.y + altura > 297 - 22) {
      this.doc.addPage();
      this.y = MARGEM;
    }
  }

  paragrafo(texto: string, o: { tamanho?: number; negrito?: boolean; italico?: boolean; alinhar?: "left" | "center" } = {}) {
    const tamanho = o.tamanho ?? 11;
    this.doc.setFont("helvetica", o.negrito ? "bold" : o.italico ? "italic" : "normal");
    this.doc.setFontSize(tamanho);
    const linhas = this.doc.splitTextToSize(texto, LARGURA) as string[];
    const altura = tamanho * 0.45;
    for (const l of linhas) {
      this.cabe(altura);
      if (o.alinhar === "center") this.doc.text(l, 105, this.y, { align: "center" });
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
    const linhas = this.doc.splitTextToSize(valor, LARGURA - 42) as string[];
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
    this.doc.line(MARGEM, this.y, 210 - MARGEM, this.y);
    this.y += 6;
  }

  salvar(nomeArquivo: string, usuario: string) {
    const total = this.doc.getNumberOfPages();
    const agora = dataHoraBr(new Date());
    for (let p = 1; p <= total; p++) {
      this.doc.setPage(p);
      this.doc.setFont("helvetica", "italic");
      this.doc.setFontSize(8);
      this.doc.text(`Gerado em ${agora} por ${usuario}`, MARGEM, 297 - 10);
      this.doc.text(`Página ${p} de ${total}`, 210 - MARGEM, 297 - 10, { align: "right" });
    }
    this.doc.save(nomeArquivo);
  }
}

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
