// Título da página, com descrição curta e ações à direita (embaixo no celular).
import type { ReactNode } from "react";

export function CabecalhoPagina({ titulo, descricao, acoes }: { titulo: ReactNode; descricao?: ReactNode; acoes?: ReactNode }) {
  return (
    <header className="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
      <div className="min-w-0 space-y-1">
        <h1 className="font-display text-2xl font-semibold tracking-tight sm:text-3xl">{titulo}</h1>
        {descricao && <p className="max-w-3xl text-sm text-muted-foreground">{descricao}</p>}
      </div>
      {acoes && <div className="flex flex-wrap gap-2">{acoes}</div>}
    </header>
  );
}
