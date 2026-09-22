// Comparação de segredos em tempo constante: o tempo da resposta não revela
// quantos caracteres do segredo estavam certos. Os dois lados passam por
// SHA-256 antes, para terem sempre o mesmo tamanho.
const codificador = new TextEncoder();

async function resumo(texto: string): Promise<Uint8Array> {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", codificador.encode(texto)));
}

export async function segredoConfere(recebido: string | null, esperado: string | undefined): Promise<boolean> {
  if (!esperado || esperado.length < 16 || recebido === null) {
    // Sem segredo configurado, nada passa. Ainda assim calcula o resumo,
    // para o tempo não denunciar esse caso.
    await resumo(recebido ?? "");
    return false;
  }
  const [a, b] = await Promise.all([resumo(recebido), resumo(esperado)]);
  let diferenca = 0;
  for (let i = 0; i < a.length; i++) diferenca |= a[i] ^ b[i];
  return diferenca === 0;
}
