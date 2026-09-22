// Enquadramento único de todas as telas: conteúdo encostado à esquerda,
// ocupando a largura disponível, com o título sempre no mesmo lugar.
// A margem interna fica no <main> do Layout: nenhuma tela põe a sua.
import type { ReactNode } from "react";
import { CabecalhoPagina } from "./CabecalhoPagina";

export function Pagina({
  titulo,
  descricao,
  acoes,
  leitura = false,
  children,
}: {
  titulo?: ReactNode;
  descricao?: ReactNode;
  acoes?: ReactNode;
  /** Texto corrido: limita a linha para leitura, sempre alinhado à esquerda. */
  leitura?: boolean;
  children: ReactNode;
}) {
  return (
    <div className={`w-full min-w-0 space-y-6 ${leitura ? "max-w-3xl" : ""}`}>
      {titulo !== undefined && <CabecalhoPagina titulo={titulo} descricao={descricao} acoes={acoes} />}
      {children}
    </div>
  );
}
