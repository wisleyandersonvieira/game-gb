// A foto reduzida no tablet precisa continuar dizendo QUANDO foi tirada.
//
// Por que existe: redesenhar a foto num canvas apaga o EXIF. Sem o enxerto,
// toda entrega com foto reduzida nasceria "sem hora da foto" — e a regra
// "esta foto é de agora" deixaria de valer em silêncio.
import { describe, expect, it } from "bun:test";
import { lerHoraExif } from "@/colaborador/foto";
import { bytesDeJpeg } from "@/colaborador/jpeg-de-teste";
import { enxertarExif, extrairExif, orientacaoNormal } from "./reduzirFoto";

const vista = (b: Uint8Array) => new DataView(b.buffer, b.byteOffset, b.byteLength);

/** Um JPEG "saído do canvas": início, cabeçalho JFIF, tabela, imagem. Sem EXIF. */
function jpegDoCanvas(): Uint8Array {
  return new Uint8Array([
    0xff, 0xd8,
    0xff, 0xe0, 0x00, 0x06, 0x4a, 0x46, 0x49, 0x46, // APP0 "JFIF"
    0xff, 0xdb, 0x00, 0x04, 0x00, 0x00, // uma tabela qualquer
    0xff, 0xda, 0x00, 0x02, 0x11, 0x22, 0x33, // imagem
  ]);
}

/** A rotação gravada no bloco EXIF, ou null. */
function rotacao(jpeg: Uint8Array): number | null {
  const app1 = extrairExif(jpeg);
  if (!app1) return null;
  const v = vista(app1);
  const ifd0 = 10 + v.getUint32(14);
  for (let k = 0; k < v.getUint16(ifd0); k++) {
    const campo = ifd0 + 2 + k * 12;
    if (v.getUint16(campo) === 0x0112) return v.getUint16(campo + 8);
  }
  return null;
}

describe("a hora da foto sobrevive à redução", () => {
  it("o JPEG do canvas sai sem hora nenhuma (é por isso que o enxerto existe)", () => {
    expect(lerHoraExif(vista(jpegDoCanvas()))).toBeNull();
  });

  it("com o bloco do original enxertado, o servidor lê a MESMA hora", () => {
    const original = bytesDeJpeg("2026:09:26 14:02:33", "", 6);
    const reduzida = enxertarExif(jpegDoCanvas(), orientacaoNormal(extrairExif(original)!));
    expect(lerHoraExif(vista(reduzida))!.toISOString()).toBe(lerHoraExif(vista(original))!.toISOString());
  });

  it("a rotação vira 'normal', porque o canvas já desenhou a foto em pé", () => {
    const original = bytesDeJpeg("2026:09:26 14:02:33", "", 6);
    expect(rotacao(original)).toBe(6);
    const reduzida = enxertarExif(jpegDoCanvas(), orientacaoNormal(extrairExif(original)!));
    expect(rotacao(reduzida)).toBe(1);
  });

  it("nada além da rotação muda no bloco copiado", () => {
    const bloco = extrairExif(bytesDeJpeg("2026:09:26 14:02:33", "", 6))!;
    const acertado = orientacaoNormal(bloco);
    const diferentes = [...bloco].filter((b, i) => b !== acertado[i]).length;
    expect(acertado.length).toBe(bloco.length);
    expect(diferentes).toBe(1); // só o byte da rotação (6 -> 1)
  });

  it("foto original sem hora continua sem hora (e nasce marcada)", () => {
    expect(extrairExif(bytesDeJpeg(null))).toBeNull();
  });

  it("a imagem e o cabeçalho JFIF do canvas continuam lá, na ordem certa", () => {
    const app1 = extrairExif(bytesDeJpeg("2026:09:26 14:02:33"))!;
    const r = enxertarExif(jpegDoCanvas(), app1);
    expect([r[2], r[3]]).toEqual([0xff, 0xe0]); // JFIF primeiro
    expect([...r.slice(r.length - 7)]).toEqual([0xff, 0xda, 0x00, 0x02, 0x11, 0x22, 0x33]);
    expect(r.length).toBe(jpegDoCanvas().length + app1.length);
  });

  it("um EXIF que o JPEG novo já tivesse é trocado, não duplicado", () => {
    const app1 = extrairExif(bytesDeJpeg("2026:09:26 14:02:33"))!;
    const duas = enxertarExif(enxertarExif(jpegDoCanvas(), app1), app1);
    expect(duas.length).toBe(jpegDoCanvas().length + app1.length);
  });

  it("bloco cortado no meio (arquivo lido pela metade) não é copiado", () => {
    const inteiro = bytesDeJpeg("2026:09:26 14:02:33");
    expect(extrairExif(inteiro.slice(0, 20))).toBeNull();
  });
});
