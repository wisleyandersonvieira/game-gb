// Reduzir a foto da entrega NO TABLET, antes de ela subir (26/09/2026).
//
// Medido no tablet da loja: 5,6 dos 7,2 segundos da entrega eram a foto
// atravessando a rede duas vezes — o tablet manda para o Storage e o servidor
// baixa o mesmo arquivo para conferir. A câmera entrega vários MB; o Quadro
// não precisa disso. Reduzida (~1600 px no lado maior, qualidade 80%), ela
// fica com algumas centenas de KB, e as DUAS viagens encolhem juntas.
//
// A HORA DA FOTO. Redesenhar a imagem num canvas apaga o EXIF, e com ele a
// hora em que a foto foi tirada. Por isso o bloco EXIF do arquivo ORIGINAL é
// copiado, byte a byte, para o arquivo reduzido. A tela não escreve hora
// nenhuma: o que vai é o que a câmera gravou, e quem lê e julga continua sendo
// o servidor, no arquivo que chegou. Foto sem hora continua sem hora (e nasce
// marcada no Quadro).
//
// Só um campo do bloco muda: a ROTAÇÃO. O canvas já desenha a imagem em pé;
// se a marca "gire 90°" do original fosse junto, quem abrisse a foto giraria
// de novo e ela apareceria deitada.
//
// Se qualquer coisa falhar no aparelho, vai a foto ORIGINAL: a entrega nunca
// trava por causa da redução.

export const LADO_MAXIMO = 1600;
export const QUALIDADE = 0.8;
/** O alvo é ~400 KB; acima disto, uma segunda passada mais comprimida. */
export const ACIMA_DO_ALVO = 550 * 1024;
export const QUALIDADE_SEGUNDA = 0.65;

export type FotoPreparada = {
  arquivo: Blob;
  reduzida: boolean;
  /** Tamanhos em bytes, para a medição. */
  original: number;
  enviada: number;
};

/** O segmento APP1 "Exif" inteiro (com a marca FFE1 e o tamanho), ou null. */
export function extrairExif(bytes: Uint8Array): Uint8Array | null {
  if (bytes.length < 4 || bytes[0] !== 0xff || bytes[1] !== 0xd8) return null;
  let i = 2;
  while (i + 4 <= bytes.length) {
    if (bytes[i] !== 0xff) return null;
    const marca = bytes[i + 1];
    const tamanho = (bytes[i + 2] << 8) | bytes[i + 3];
    if (marca === 0xda) return null; // começou a imagem: acabou o cabeçalho
    if (
      marca === 0xe1 &&
      i + 10 <= bytes.length &&
      bytes[i + 4] === 0x45 && bytes[i + 5] === 0x78 && bytes[i + 6] === 0x69 && bytes[i + 7] === 0x66
    ) {
      // O pedaço lido pode ter cortado o bloco no meio: aí não serve.
      if (i + 2 + tamanho > bytes.length) return null;
      return bytes.slice(i, i + 2 + tamanho);
    }
    i += 2 + tamanho;
  }
  return null;
}

/** Cópia do bloco EXIF com a rotação em "normal" (1). Não mexe em mais nada. */
export function orientacaoNormal(app1: Uint8Array): Uint8Array {
  const copia = app1.slice();
  try {
    const v = new DataView(copia.buffer, copia.byteOffset, copia.byteLength);
    const tiff = 10; // FFE1 + tamanho (4) + "Exif\0\0" (6)
    const ordem = v.getUint16(tiff);
    const pequeno = ordem === 0x4949;
    if (!pequeno && ordem !== 0x4d4d) return copia;
    const ifd0 = tiff + v.getUint32(tiff + 4, pequeno);
    const n = v.getUint16(ifd0, pequeno);
    for (let k = 0; k < n; k++) {
      const campo = ifd0 + 2 + k * 12;
      if (campo + 12 > copia.length) break;
      if (v.getUint16(campo, pequeno) === 0x0112) v.setUint16(campo + 8, 1, pequeno);
    }
  } catch {
    // Bloco estranho: vai como veio. O pior caso é a foto aparecer girada.
  }
  return copia;
}

/**
 * Põe o bloco EXIF no JPEG novo, logo depois do início (e do cabeçalho JFIF,
 * quando houver). Qualquer EXIF que o JPEG novo já tivesse sai.
 */
export function enxertarExif(jpeg: Uint8Array, app1: Uint8Array): Uint8Array {
  if (jpeg.length < 4 || jpeg[0] !== 0xff || jpeg[1] !== 0xd8) return jpeg;
  const partes: Uint8Array[] = [jpeg.slice(0, 2)];
  let i = 2;
  let enxertado = false;
  while (i + 4 <= jpeg.length && jpeg[i] === 0xff) {
    const marca = jpeg[i + 1];
    if (marca === 0xda) break;
    const tamanho = (jpeg[i + 2] << 8) | jpeg[i + 3];
    const segmento = jpeg.slice(i, i + 2 + tamanho);
    const ehExif = marca === 0xe1 && segmento[4] === 0x45 && segmento[5] === 0x78;
    if (marca !== 0xe0 && !enxertado) {
      partes.push(app1);
      enxertado = true;
    }
    if (!ehExif) partes.push(segmento);
    i += 2 + tamanho;
  }
  if (!enxertado) partes.push(app1);
  partes.push(jpeg.slice(i));

  const total = partes.reduce((s, p) => s + p.length, 0);
  const saida = new Uint8Array(total);
  let pos = 0;
  for (const p of partes) {
    saida.set(p, pos);
    pos += p.length;
  }
  return saida;
}

/** Reduz no navegador. Qualquer falha devolve a original. */
export async function reduzirFoto(arquivo: File): Promise<FotoPreparada> {
  const original: FotoPreparada = { arquivo, reduzida: false, original: arquivo.size, enviada: arquivo.size };
  if (typeof document === "undefined") return original;
  const url = URL.createObjectURL(arquivo);
  try {
    // A <img> já desenha a foto em pé, lendo a rotação do EXIF (todos os
    // navegadores atuais).
    const img = new Image();
    img.src = url;
    await img.decode();
    const escala = Math.min(1, LADO_MAXIMO / Math.max(img.naturalWidth, img.naturalHeight));
    const largura = Math.max(1, Math.round(img.naturalWidth * escala));
    const altura = Math.max(1, Math.round(img.naturalHeight * escala));

    const canvas = document.createElement("canvas");
    canvas.width = largura;
    canvas.height = altura;
    const ctx = canvas.getContext("2d");
    if (!ctx) return original;
    ctx.drawImage(img, 0, 0, largura, altura);
    const gerar = (q: number) => new Promise<Blob | null>((r) => canvas.toBlob(r, "image/jpeg", q));
    let blob = await gerar(QUALIDADE);
    if (!blob) return original;
    // Foto com muito detalhe (grama, cascalho, prateleira cheia) passa do alvo
    // a 80%: uma segunda tentativa, um pouco mais comprimida, e para aí.
    if (blob.size > ACIMA_DO_ALVO) blob = (await gerar(QUALIDADE_SEGUNDA)) ?? blob;

    let bytes: Uint8Array = new Uint8Array(await blob.arrayBuffer());
    const exif = extrairExif(new Uint8Array(await arquivo.slice(0, 256 * 1024).arrayBuffer()));
    if (exif) bytes = enxertarExif(bytes, orientacaoNormal(exif));

    // Reduzir que não reduz não vale: vai a original.
    if (bytes.length >= arquivo.size) return original;
    return {
      arquivo: new Blob([bytes as BlobPart], { type: "image/jpeg" }),
      reduzida: true,
      original: arquivo.size,
      enviada: bytes.length,
    };
  } catch {
    return original;
  } finally {
    URL.revokeObjectURL(url);
  }
}
