// Quando o botão "Concluir" do primeiro acesso pode ser apertado. É só o
// básico, para o botão não ficar aceso à toa; as regras completas (nada de
// pedaço do CPF, sequência ou número repetido) são conferidas no servidor, e o
// motivo aparece na tela.

export type SenhaEPin = { senha: string; senha2: string; pin: string; pin2: string };

/** O que ainda falta, em palavras, ou null quando pode concluir. */
export function faltaParaConcluir(v: SenhaEPin, precisa: { senha: boolean; pin: boolean } = { senha: true, pin: true }) {
  if (precisa.senha) {
    if (v.senha.length < 8) return "A senha precisa ter pelo menos 8 caracteres.";
    if (v.senha !== v.senha2) return "As duas senhas precisam ser iguais.";
  }
  if (precisa.pin) {
    if (!/^\d{6}$/.test(v.pin)) return "O PIN tem 6 números.";
    if (v.pin !== v.pin2) return "Os dois PINs precisam ser iguais.";
  }
  return null;
}
