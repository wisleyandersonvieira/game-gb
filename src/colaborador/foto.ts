// A foto da entrega, do lado do celular.
//
// Duas coisas saem do arquivo, antes de ele subir:
//
// 1. A IMPRESSÃO DIGITAL (SHA-256). É o que impede a mesma foto de provar
//    duas tarefas, mesmo renomeada. O banco guarda em entregas.fotoidunico,
//    o mesmo campo que o Telegram já usava.
//
// 2. A HORA EM QUE A FOTO FOI TIRADA (EXIF DateTimeOriginal). O navegador não
//    sabe dizer se a foto veio da câmera ou da galeria — isso não existe na
//    web. A hora da foto é o substituto: se a foto é de agora, ela foi tirada
//    agora. Muitos celulares apagam esse dado ao enviar; nesse caso a entrega
//    entra MARCADA e o gestor decide na aprovação (decisão de 26/09/2026).

/** SHA-256 do arquivo, em hexadecimal. */
export async function impressaoDigital(arquivo: Blob): Promise<string> {
  const bytes = await arquivo.arrayBuffer();
  const resumo = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(resumo)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/**
 * Quando a foto foi tirada, lendo o EXIF do JPEG. Devolve null quando o
 * arquivo não traz essa informação — que é o caso comum em muitos celulares.
 *
 * Lê só o começo do arquivo (128 KB bastam para o cabeçalho EXIF).
 */
export async function horaDaFoto(arquivo: Blob): Promise<Date | null> {
  try {
    const inicio = await arquivo.slice(0, 128 * 1024).arrayBuffer();
    return lerHoraExif(new DataView(inicio));
  } catch {
    return null;
  }
}

/** Separado para poder ser testado sem um arquivo de verdade. */
export function lerHoraExif(v: DataView): Date | null {
  if (v.byteLength < 4 || v.getUint16(0) !== 0xffd8) return null; // não é JPEG

  let i = 2;
  while (i + 4 <= v.byteLength) {
    if (v.getUint8(i) !== 0xff) return null;
    const marca = v.getUint8(i + 1);
    const tamanho = v.getUint16(i + 2);
    if (marca === 0xe1) {
      const exif = i + 4;
      // Arquivo cortado no meio: o navegador só nos deu o começo dele.
      if (exif + 12 > v.byteLength) return null;
      // "Exif\0\0"
      if (v.getUint32(exif) !== 0x45786966) return null;
      const tiff = exif + 6;
      const ordem = v.getUint16(tiff);
      const pequeno = ordem === 0x4949; // "II" = menos significativo primeiro
      if (!pequeno && ordem !== 0x4d4d) return null;
      const u16 = (p: number) => v.getUint16(p, pequeno);
      const u32 = (p: number) => v.getUint32(p, pequeno);

      if (tiff + 8 > v.byteLength) return null;
      const ifd0 = tiff + u32(tiff + 4);
      const achar = (base: number, etiqueta: number): number | null => {
        if (base + 2 > v.byteLength) return null;
        const n = u16(base);
        for (let k = 0; k < n; k++) {
          const campo = base + 2 + k * 12;
          if (campo + 12 > v.byteLength) return null;
          if (u16(campo) === etiqueta) return u32(campo + 8);
        }
        return null;
      };

      // 0x8769 = ponteiro para o bloco EXIF; 0x9003 = DateTimeOriginal.
      const bloco = achar(ifd0, 0x8769);
      const alvo = bloco === null ? null : achar(tiff + bloco, 0x9003);
      if (alvo === null) return null;

      const p = tiff + alvo;
      if (p + 19 > v.byteLength) return null;
      let texto = "";
      for (let k = 0; k < 19; k++) texto += String.fromCharCode(v.getUint8(p + k));
      // "2026:09:26 14:02:33"
      const m = texto.match(/^(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})$/);
      if (!m) return null;
      // A hora do EXIF é a do relógio do aparelho, sem fuso: lemos como local.
      const d = new Date(
        Number(m[1]), Number(m[2]) - 1, Number(m[3]),
        Number(m[4]), Number(m[5]), Number(m[6]),
      );
      return Number.isNaN(d.getTime()) ? null : d;
    }
    if (marca === 0xda) return null; // começou a imagem: não há mais cabeçalho
    i += 2 + tamanho;
  }
  return null;
}
