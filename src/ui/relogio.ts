// Relógio das telas que mostram "há quanto tempo".
//
// O tempo é contado a partir de um instante do SERVIDOR (quando a tarefa ficou
// disponível), corrigido pela diferença entre o relógio do aparelho e o do
// servidor. Assim dois tablets mostram o mesmo número, mesmo com a hora do
// aparelho errada.
//
// Anda sozinho no navegador; não pede nada ao banco. O passo é de 15 s (o
// mesmo da conferência da fila): como a tela mostra minutos, não há motivo
// para redesenhar a cada segundo.
import { useEffect, useState } from "react";

const PASSO = 15_000;

export function useRelogio() {
  const [, bater] = useState(0);
  useEffect(() => {
    const t = setInterval(() => bater((n) => n + 1), PASSO);
    return () => clearInterval(t);
  }, []);
  return Date.now();
}

/**
 * Minutos entre `desde` (hora do servidor) e agora, corrigindo o relógio do
 * aparelho pela hora que o servidor mandou junto.
 */
export function minutosDesde(desde: string | null, agoraDoServidor: string | null | undefined) {
  if (!desde) return null;
  const inicio = new Date(desde).getTime();
  const servidor = agoraDoServidor ? new Date(agoraDoServidor).getTime() : Date.now();
  // Quanto o relógio deste aparelho está adiantado em relação ao servidor.
  const diferenca = Date.now() - servidor;
  const agora = Date.now() - diferenca;
  return Math.max(0, Math.floor((agora - inicio) / 60_000));
}

/** "há 12 min", "há 2 h 05", "agora". */
export function faz(minutos: number | null) {
  if (minutos === null) return "";
  if (minutos < 1) return "agora";
  if (minutos < 60) return `há ${minutos} min`;
  const h = Math.floor(minutos / 60);
  const m = minutos % 60;
  return `há ${h} h${m > 0 ? ` ${String(m).padStart(2, "0")}` : ""}`;
}
