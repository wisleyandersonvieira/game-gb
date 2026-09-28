// As medidas da entrega pelo celular (`/eu?medir=1`, 29/09/2026). Ficam aqui,
// fora das telas, porque quem mede é a janela de entrega (em Minhas tarefas) e
// quem mostra é o quadro embaixo de todas as telas do celular. Nada disso
// sai do aparelho.
import { useSyncExternalStore } from "react";
import type { Medida } from "@/painel/medicaoDoTablet";

let medidas: Medida[] = [];
const ouvintes = new Set<() => void>();

export function registrarMedidaDoCelular(m: Medida) {
  medidas = [m, ...medidas].slice(0, 6);
  for (const f of ouvintes) f();
}

export function useMedidasDoCelular(): Medida[] {
  return useSyncExternalStore(
    (f) => {
      ouvintes.add(f);
      return () => ouvintes.delete(f);
    },
    () => medidas,
    () => medidas,
  );
}
