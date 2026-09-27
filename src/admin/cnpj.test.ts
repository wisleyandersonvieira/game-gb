import { describe, expect, it } from "bun:test";
import { cnpjValido, codigoNoFormato, formatarCnpj } from "./cnpj";

describe("CNPJ na tela do admin", () => {
  it("aceita CNPJ com dígitos certos, com ou sem pontuação", () => {
    expect(cnpjValido("11.222.333/0001-81")).toBe(true);
    expect(cnpjValido("11222333000181")).toBe(true);
  });
  it("recusa dígito verificador errado, tamanho errado e número repetido", () => {
    expect(cnpjValido("11.222.333/0001-82")).toBe(false);
    expect(cnpjValido("1122233300018")).toBe(false);
    expect(cnpjValido("11111111111111")).toBe(false);
  });
  it("formata enquanto a pessoa digita", () => {
    expect(formatarCnpj("11222333000181")).toBe("11.222.333/0001-81");
    expect(formatarCnpj("11222")).toBe("11.222");
  });
});

describe("formato do código da empresa", () => {
  it("só minúsculas e números, de 4 a 20", () => {
    expect(codigoNoFormato("premier")).toBe(true);
    expect(codigoNoFormato("acai2")).toBe(true);
    expect(codigoNoFormato("pre")).toBe(false);
    expect(codigoNoFormato("Premier")).toBe(false);
    expect(codigoNoFormato("premier-lojas")).toBe(false);
    expect(codigoNoFormato("a".repeat(21))).toBe(false);
  });
});
