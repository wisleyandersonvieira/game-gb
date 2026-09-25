// A versão deste pacote, gravada pelo build (ver vite.config.ts).
//
// Serve para duas coisas:
//  1. a tela /saude dizer QUAL versão está no ar — o /saude só sabia falar do
//     banco, e por isso dizia "tudo certo" com uma versão antiga publicada;
//  2. a aba aberta perceber que já existe versão mais nova e oferecer atualizar.
declare const __VERSAO__: { commit: string; em: string } | undefined;

export type Versao = { commit: string; em: string };

export const VERSAO: Versao =
  typeof __VERSAO__ !== "undefined" ? __VERSAO__ : { commit: "desenvolvimento", em: "" };

/** "25/09/2026 14:02" — a hora em que o pacote foi montado. */
export function versaoEmTexto(v: Versao): string {
  if (!v.em) return v.commit;
  const quando = new Date(v.em).toLocaleString("pt-BR", {
    day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit",
  });
  return `${v.commit} · ${quando}`;
}
