// A prova da foto, feita pelo SERVIDOR.
//
// Estas provas existem porque o jeito antigo — o navegador dizer qual era a
// impressão digital da foto e a que horas ela foi tirada — não provava nada:
// quem abre o DevTools manda o número que quiser. Cada teste aqui é uma
// fraude concreta que o servidor tem de recusar.
import { beforeAll, describe, expect, it } from "bun:test";
import {
  conferirBilhete,
  emitirBilhete,
  julgarHoraDaFoto,
  provaDosBytes,
  relogioDeSaoPaulo,
  TOLERANCIA_PADRAO,
} from "./fotodaentrega";
import { bytesDeJpeg } from "@/colaborador/jpeg-de-teste";

// embaralhar() assina com a chave do servidor: sem ela não há bilhete.
beforeAll(() => {
  process.env["STGAME_PIN_PEPPER"] = "chave-de-teste-bem-comprida-1234567890";
});

const CAMINHO = "1/10/abc-123.jpg";
const TAREFA = 7001;
const PESSOA = 9803;

async function bilheteBom() {
  return await emitirBilhete(CAMINHO, TAREFA, PESSOA);
}

describe("foto adulterada: o bilhete amarra arquivo, tarefa e pessoa", () => {
  it("o bilhete certo passa", async () => {
    await conferirBilhete(await bilheteBom(), CAMINHO, TAREFA, PESSOA);
  });

  it("trocar o ARQUIVO depois de assinado é recusado", async () => {
    const b = await bilheteBom();
    // A fraude: subo uma foto, e na entrega aponto para outro arquivo —
    // o de uma entrega que já foi aprovada, por exemplo.
    expect(conferirBilhete(b, "1/10/outra-foto.jpg", TAREFA, PESSOA)).rejects.toThrow(/inválido/i);
  });

  it("usar o bilhete de uma tarefa em OUTRA tarefa é recusado", async () => {
    const b = await bilheteBom();
    expect(conferirBilhete(b, CAMINHO, TAREFA + 1, PESSOA)).rejects.toThrow(/inválido/i);
  });

  it("usar o bilhete de um colega é recusado", async () => {
    const b = await bilheteBom();
    expect(conferirBilhete(b, CAMINHO, TAREFA, PESSOA + 1)).rejects.toThrow(/inválido/i);
  });

  it("mexer na assinatura é recusado", async () => {
    const b = await bilheteBom();
    const [quando, assinatura] = b.split(".");
    const trocado = assinatura[0] === "a" ? "b" : "a";
    expect(conferirBilhete(`${quando}.${trocado}${assinatura.slice(1)}`, CAMINHO, TAREFA, PESSOA))
      .rejects.toThrow(/inválido/i);
  });

  it("esticar o prazo mexendo na hora do bilhete é recusado", async () => {
    const b = await bilheteBom();
    const assinatura = b.split(".")[1];
    // A fraude: o bilhete venceu, então eu reescrevo a hora dele para agora.
    // A assinatura não bate mais, porque a hora faz parte do que foi assinado.
    // (Cinco minutos à frente, e não Date.now(), senão cairia no MESMO
    // milissegundo do bilhete bom e o teste passaria por acidente — foi o que
    // aconteceu na primeira vez que escrevi isto.)
    expect(conferirBilhete(`${Date.now() + 5 * 60_000}.${assinatura}`, CAMINHO, TAREFA, PESSOA))
      .rejects.toThrow(/inválido/i);
  });

  it("bilhete vencido é recusado", async () => {
    const onzeMinutos = Date.now() - 11 * 60_000;
    const { embaralhar } = await import("./segredos");
    const assinatura = await embaralhar(`foto:${CAMINHO}:${TAREFA}:${PESSOA}:${onzeMinutos}`);
    expect(conferirBilhete(`${onzeMinutos}.${assinatura}`, CAMINHO, TAREFA, PESSOA))
      .rejects.toThrow(/10 minutos/i);
  });

  it("bilhete vazio ou sem formato é recusado", async () => {
    expect(conferirBilhete("", CAMINHO, TAREFA, PESSOA)).rejects.toThrow(/inválido/i);
    expect(conferirBilhete("xxxxx", CAMINHO, TAREFA, PESSOA)).rejects.toThrow(/inválido/i);
    expect(conferirBilhete("abc.def", CAMINHO, TAREFA, PESSOA)).rejects.toThrow(/inválido/i);
  });
});

describe("foto repetida: a mesma imagem não prova duas tarefas", () => {
  it("o mesmo arquivo dá sempre a mesma impressão digital", async () => {
    const bytes = bytesDeJpeg("2026:09:25 14:02:33", "conteudo");
    const a = await provaDosBytes(bytes.buffer as ArrayBuffer);
    const b = await provaDosBytes(bytes.slice().buffer as ArrayBuffer);
    // É isto que faz o banco recusar a segunda entrega: o número é o mesmo,
    // e ele é único por conta. Renomear o arquivo não muda nada.
    expect(a.fotoidunico).toBe(b.fotoidunico);
    expect(a.fotoidunico).toHaveLength(64);
  });

  it("arquivos diferentes dão impressões diferentes", async () => {
    const a = await provaDosBytes(bytesDeJpeg("2026:09:25 14:02:33", "um").buffer as ArrayBuffer);
    const b = await provaDosBytes(bytesDeJpeg("2026:09:25 14:02:33", "dois").buffer as ArrayBuffer);
    expect(a.fotoidunico).not.toBe(b.fotoidunico);
  });
});

describe("foto sem os dados esperados", () => {
  it("arquivo vazio é recusado", async () => {
    expect(provaDosBytes(new ArrayBuffer(0))).rejects.toThrow(/não chegou/i);
  });

  it("arquivo que não é JPEG não tem hora: passa e nasce MARCADA", async () => {
    const naoEhJpeg = new TextEncoder().encode("isto aqui nao e uma imagem");
    const p = await provaDosBytes(naoEhJpeg.buffer as ArrayBuffer);
    expect(p.horafoto).toBeNull();
    expect(p.fotoidunico).toHaveLength(64);
  });

  it("JPEG sem o bloco EXIF também nasce MARCADA", async () => {
    const p = await provaDosBytes(bytesDeJpeg(null).buffer as ArrayBuffer);
    expect(p.horafoto).toBeNull();
  });

  it("cabeçalho EXIF estragado não derruba nada: fica sem hora", async () => {
    const b = bytesDeJpeg("2026:09:25 14:02:33");
    // Estraga a marca "Exif" (logo depois de 0xFFD8 0xFFE1 e do tamanho).
    b[6] = 0x00;
    b[7] = 0x00;
    const p = await provaDosBytes(b.buffer as ArrayBuffer);
    expect(p.horafoto).toBeNull();
    // E a impressão digital continua saindo: a entrega passa, marcada.
    expect(p.fotoidunico).toHaveLength(64);
  });
});

describe("data e hora fora do razoável", () => {
  // 25/09/2026, 14h02m40 no relógio de parede de São Paulo (UTC−3).
  const AGORA = Date.parse("2026-09-25T17:02:40Z");

  /** A hora como o servidor a lê do arquivo — o caminho de verdade. */
  async function horaDoArquivo(exif: string) {
    const p = await provaDosBytes(bytesDeJpeg(exif).buffer as ArrayBuffer);
    expect(p.horafoto).not.toBeNull();
    return p.horafoto!;
  }

  // ATENÇÃO: estas provas passam a hora como TEXTO de EXIF, e não como um
  // Date montado aqui. Antes elas montavam os dois lados no fuso de quem
  // rodava o teste, os erros se cancelavam, e a suíte passava mesmo com o
  // servidor recusando toda foto em produção. Rode também com TZ=UTC.

  it("foto de agora passa (o servidor em UTC, a loja em São Paulo)", async () => {
    julgarHoraDaFoto(await horaDoArquivo("2026:09:25 14:02:33"), "120", AGORA);
  });

  it("foto de ontem é recusada", async () => {
    expect(() => julgarHoraDaFoto(new Date(Date.UTC(2026, 8, 24, 14, 2, 33)), "120", AGORA))
      .toThrow(/não é de agora/i);
  });

  it("foto com data no FUTURO é recusada (relógio mexido)", async () => {
    const futuro = await horaDoArquivo("2026:09:25 15:02:33");
    expect(() => julgarHoraDaFoto(futuro, "120", AGORA)).toThrow(/não é de agora/i);
  });

  it("uma foto de 3 horas atrás NÃO passa por causa do fuso", async () => {
    // Esta é a prova do defeito achado na revisão: lendo o EXIF no fuso do
    // servidor, 11h02 de São Paulo virava "14h02" e entrava como se fosse de
    // agora, e 14h02 (a foto honesta) era recusada.
    const tresHorasAtras = await horaDoArquivo("2026:09:25 11:02:33");
    expect(() => julgarHoraDaFoto(tresHorasAtras, "120", AGORA)).toThrow(/não é de agora/i);
  });

  it("o relógio de São Paulo é o de parede, não o do servidor", () => {
    // 17:02:40 UTC = 14:02:40 em São Paulo.
    expect(new Date(relogioDeSaoPaulo(AGORA)).toISOString()).toBe("2026-09-25T14:02:40.000Z");
  });

  it("configuração estragada não vira tolerância infinita", async () => {
    const ontem = new Date(Date.UTC(2026, 8, 24, 14, 2, 33));
    for (const estragado of ["abc", "", "0", "-5", null]) {
      expect(() => julgarHoraDaFoto(ontem, estragado, AGORA)).toThrow(/não é de agora/i);
    }
  });

  it("a tolerância da conta é respeitada quando vale", async () => {
    // 10 minutos configurados: foto de 5 minutos atrás passa, de 20 não.
    julgarHoraDaFoto(await horaDoArquivo("2026:09:25 13:57:33"), "600", AGORA);
    const vinteMinutos = await horaDoArquivo("2026:09:25 13:42:33");
    expect(() => julgarHoraDaFoto(vinteMinutos, "600", AGORA)).toThrow(/não é de agora/i);
    expect(TOLERANCIA_PADRAO).toBe(120);
  });
});
