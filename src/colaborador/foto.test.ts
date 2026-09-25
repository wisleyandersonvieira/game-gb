// O leitor de EXIF da foto da entrega.
//
// Por que existe: a decisão de 26/09/2026 é "quando a hora da foto existir,
// exija que seja recente; quando não existir, aceite e marque". Se o leitor
// errasse, ou a entrega honesta seria barrada, ou a marca nunca apareceria.
import { describe, expect, it } from "bun:test";
import { lerHoraExif } from "./foto";
import { jpegComHora } from "./jpeg-de-teste";

describe("hora em que a foto foi tirada", () => {
  it("monta a hora sempre no MESMO relógio, não no de quem está lendo", () => {
    // O EXIF não traz fuso. Se montássemos como hora "local", o mesmo arquivo
    // daria instantes diferentes no celular (São Paulo) e no servidor (UTC) —
    // e o servidor recusava toda foto que trouxesse a hora. Quem compara é
    // relogioDeSaoPaulo(), do lado do servidor.
    const d = lerHoraExif(jpegComHora("2026:09:25 14:02:33"));
    expect(d!.toISOString()).toBe("2026-09-25T14:02:33.000Z");
  });

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
