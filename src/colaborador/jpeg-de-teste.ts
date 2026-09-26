// Um JPEG de mentira, com (ou sem) a hora em que a foto foi tirada.
//
// Vive fora do arquivo de teste porque duas provas diferentes precisam dele:
// a do leitor de EXIF (src/colaborador/foto.test.ts) e a da prova da foto
// feita pelo servidor (src/servidor/fotodaentrega.test.ts).

/** Bytes de um JPEG com um bloco EXIF contendo DateTimeOriginal. */
export function bytesDeJpeg(quando: string | null, recheio = "", orientacao?: number): Uint8Array {
  const bytes: number[] = [0xff, 0xd8]; // início do JPEG

  if (quando !== null) {
    // Bloco EXIF (big-endian, "MM"), com IFD0 -> ponteiro EXIF -> DateTimeOriginal.
    const corpo: number[] = [];
    const p16 = (n: number) => corpo.push((n >> 8) & 0xff, n & 0xff);
    const p32 = (n: number) => corpo.push((n >> 24) & 0xff, (n >> 16) & 0xff, (n >> 8) & 0xff, n & 0xff);

    corpo.push(0x45, 0x78, 0x69, 0x66, 0x00, 0x00); // "Exif\0\0"
    corpo.push(0x4d, 0x4d); // "MM"
    p16(42);
    p32(8); // IFD0 em tiff+8

    // Cada IFD ocupa 2 (quantos) + 12 por campo + 4 (proximo). O IFD0 ganha
    // um campo a mais quando a foto traz a marca de rotacao (0x0112).
    const IFD = 18;
    const ifd0 = orientacao === undefined ? IFD : IFD + 12;
    const blocoExif = 8 + ifd0;
    const textoEm = blocoExif + IFD;

    p16(orientacao === undefined ? 1 : 2);
    if (orientacao !== undefined) {
      p16(0x0112); p16(3); p32(1); p16(orientacao); p16(0); // rotacao (SHORT)
    }
    p16(0x8769); p16(4); p32(1); p32(blocoExif); // ponteiro EXIF
    p32(0);

    p16(1);
    p16(0x9003); p16(2); p32(20); p32(textoEm); // DateTimeOriginal
    p32(0);

    for (const c of quando) corpo.push(c.charCodeAt(0));
    corpo.push(0);

    const tamanho = corpo.length + 2;
    bytes.push(0xff, 0xe1, (tamanho >> 8) & 0xff, tamanho & 0xff, ...corpo);
  }

  bytes.push(0xff, 0xda, 0x00, 0x02); // começa a imagem
  for (const c of recheio) bytes.push(c.charCodeAt(0));
  return new Uint8Array(bytes);
}

/** O mesmo, no formato que o leitor de EXIF recebe. */
export function jpegComHora(quando: string | null): DataView {
  const b = bytesDeJpeg(quando);
  return new DataView(b.buffer, b.byteOffset, b.byteLength);
}
