// O leitor de EXIF da foto da entrega.
//
// Por que existe: a decisão de 26/09/2026 é "quando a hora da foto existir,
// exija que seja recente; quando não existir, aceite e marque". Se o leitor
// errasse, ou a entrega honesta seria barrada, ou a marca nunca apareceria.
import { describe, expect, it } from "bun:test";
import { lerHoraExif } from "./foto";

/** Monta um JPEG mínimo com um bloco EXIF contendo DateTimeOriginal. */
function jpegComHora(quando: string | null): DataView {
  const texto = quando ?? "";
  const bytes: number[] = [0xff, 0xd8]; // início do JPEG

  if (quando === null) {
    bytes.push(0xff, 0xda, 0x00, 0x02); // vai direto para a imagem
    return new DataView(new Uint8Array(bytes).buffer);
  }

  // Bloco EXIF (big-endian, "MM"), com IFD0 -> ponteiro EXIF -> DateTimeOriginal.
  const corpo: number[] = [];
  const p16 = (n: number) => corpo.push((n >> 8) & 0xff, n & 0xff);
  const p32 = (n: number) => corpo.push((n >> 24) & 0xff, (n >> 16) & 0xff, (n >> 8) & 0xff, n & 0xff);

  corpo.push(0x45, 0x78, 0x69, 0x66, 0x00, 0x00); // "Exif\0\0"
  const tiff = corpo.length;
  corpo.push(0x4d, 0x4d); // "MM"
  p16(42);
  p32(8); // IFD0 em tiff+8

  // Cada IFD ocupa 2 (quantos) + 12 (um campo) + 4 (proximo) = 18 bytes.
  // Calculado, e nao chutado: foi um numero errado aqui que fez este teste
  // reprovar na primeira vez.
  const IFD = 18;
  const blocoExif = 8 + IFD;          // logo depois do IFD0
  const textoEm = blocoExif + IFD;    // logo depois do bloco EXIF

  // IFD0: um campo, 0x8769 (ponteiro EXIF)
  p16(1);
  p16(0x8769); p16(4); p32(1); p32(blocoExif);
  p32(0); // sem próximo IFD

  // Bloco EXIF: um campo, 0x9003 (DateTimeOriginal)
  p16(1);
  p16(0x9003); p16(2); p32(20); p32(textoEm);
  p32(0);

  for (const c of texto) corpo.push(c.charCodeAt(0));
  corpo.push(0);

  const tamanho = corpo.length + 2;
  bytes.push(0xff, 0xe1, (tamanho >> 8) & 0xff, tamanho & 0xff, ...corpo);
  bytes.push(0xff, 0xda, 0x00, 0x02);
  void tiff;
  return new DataView(new Uint8Array(bytes).buffer);
}

describe("hora em que a foto foi tirada", () => {
  it("lê a hora quando o arquivo traz", () => {
    const d = lerHoraExif(jpegComHora("2026:09:26 14:02:33"));
    expect(d).not.toBeNull();
    expect(d!.getFullYear()).toBe(2026);
    expect(d!.getMonth()).toBe(8); // setembro
    expect(d!.getDate()).toBe(26);
    expect(d!.getHours()).toBe(14);
    expect(d!.getMinutes()).toBe(2);
  });

  it("devolve vazio quando o arquivo não traz a hora", () => {
    expect(lerHoraExif(jpegComHora(null))).toBeNull();
  });

  it("devolve vazio quando não é um JPEG", () => {
    const lixo = new DataView(new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8]).buffer);
    expect(lerHoraExif(lixo)).toBeNull();
  });

  it("devolve vazio quando a data está estragada", () => {
    expect(lerHoraExif(jpegComHora("nao-e-uma-data!!!!!"))).toBeNull();
  });

  it("não quebra com um arquivo cortado no meio", () => {
    const inteiro = jpegComHora("2026:09:26 14:02:33");
    const cortado = new DataView(inteiro.buffer.slice(0, 20));
    expect(() => lerHoraExif(cortado)).not.toThrow();
  });
});
