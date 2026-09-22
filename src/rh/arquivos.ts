// Confere o tipo REAL do arquivo pelos primeiros bytes (a "assinatura" do
// formato), sem confiar na extensão nem no tipo que o navegador informa.
export const TIPOS_PERMITIDOS = ["application/pdf", "image/jpeg", "image/png"] as const;
export const LIMITE_ARQUIVO = 10 * 1024 * 1024;

export async function tipoReal(arquivo: File): Promise<(typeof TIPOS_PERMITIDOS)[number] | null> {
  const b = new Uint8Array(await arquivo.slice(0, 8).arrayBuffer());
  if (b[0] === 0x25 && b[1] === 0x50 && b[2] === 0x44 && b[3] === 0x46) return "application/pdf"; // %PDF
  if (b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return "image/jpeg";
  if (b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47) return "image/png";
  return null;
}

/** Valida tamanho e tipo real; devolve o tipo a gravar ou lança o erro. */
export async function validarArquivo(arquivo: File) {
  if (arquivo.size <= 0) throw new Error("O arquivo está vazio.");
  if (arquivo.size > LIMITE_ARQUIVO) throw new Error("O arquivo passa de 10 MB.");
  const tipo = await tipoReal(arquivo);
  if (!tipo) throw new Error("Só PDF, JPG ou PNG (o conteúdo do arquivo não é de nenhum desses).");
  return tipo;
}
