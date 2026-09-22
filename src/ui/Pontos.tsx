// Selo de pontos da marca: o dourado é SÓ para pontos, medalhas e 1º lugar.
import type { ReactNode } from "react";

export function Pontos({ valor, sinal = false, sufixo = "pontos", grande = false }: { valor: ReactNode; sinal?: boolean; sufixo?: string; grande?: boolean }) {
  const n = typeof valor === "number" && sinal && valor > 0 ? `+${valor}` : valor;
  return (
    <span
      className={`inline-flex items-center gap-1.5 rounded-full bg-ouro-soft font-mono font-medium tabular-nums text-ouro-ink ${
        grande ? "px-3 py-1 text-base" : "px-2 py-0.5 text-xs"
      }`}
    >
      <span className={`shrink-0 rounded-full bg-ouro ${grande ? "h-2.5 w-2.5" : "h-2 w-2"}`} aria-hidden />
      {n}
      {sufixo && <span className="font-sans font-normal">{sufixo}</span>}
    </span>
  );
}
