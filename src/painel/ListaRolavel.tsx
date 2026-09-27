import { useLayoutEffect, useRef, useState } from "react";

/**
 * No máximo 4 cartões à vista; o resto rola DENTRO da coluna. A altura é
 * medida no 4º cartão (os cartões não têm todos a mesma altura). A rolagem de
 * dentro não segura a da página: chegando ao fim da coluna, o dedo continua
 * rolando a página (o comportamento padrão do navegador, que não é travado
 * aqui). Enquanto houver cartão escondido, a coluna diz quantos faltam.
 */
export function ListaRolavel({ quantos, children }: { quantos: number; children: React.ReactNode }) {
  const lista = useRef<HTMLUListElement>(null);
  const [altura, setAltura] = useState<number | undefined>(undefined);
  const [escondidos, setEscondidos] = useState(0);

  useLayoutEffect(() => {
    const ul = lista.current;
    if (!ul) return;
    const quarto = ul.children[3] as HTMLElement | undefined;
    setAltura(quantos > 4 && quarto ? quarto.offsetTop + quarto.offsetHeight : undefined);
  }, [quantos, children]);

  function contarEscondidos() {
    const ul = lista.current;
    if (!ul || altura === undefined) return setEscondidos(0);
    const fundo = ul.scrollTop + ul.clientHeight;
    const abaixo = [...ul.children].filter((c) => (c as HTMLElement).offsetTop + 8 >= fundo).length;
    setEscondidos(abaixo);
  }
  useLayoutEffect(contarEscondidos, [altura, quantos]);

  return (
    <>
      <ul
        ref={lista}
        onScroll={contarEscondidos}
        // A posição fica no próprio elemento (e não numa classe de estilo): as
        // medidas dos cartões são relativas a esta lista.
        style={{ position: "relative", ...(altura !== undefined ? { maxHeight: altura, overflowY: "auto" } : {}) }}
        className={`space-y-2 ${altura !== undefined ? "pr-1" : ""}`}
      >
        {children}
      </ul>
      {escondidos > 0 && (
        <p className="text-center text-xs font-medium text-muted-foreground">
          ↓ mais {escondidos} abaixo — role a coluna
        </p>
      )}
    </>
  );
}
