// As palavras da fila, UMA vez, para o tablet e o Quadro dizerem o mesmo
// (27/09/2026): o Quadro mostrava "Para pegar (6)" enquanto o tablet mostrava
// "Para pegar (1)" e 5 ainda não liberadas. As duas telas falam da mesma
// coisa, então usam as mesmas funções.
import { quandoFoi } from "@/ui/hoje";
import { faz, minutosDesde } from "@/ui/relogio";

type ItemComHora = {
  liberaas: string | null;
  disponiveldesde: string | null;
  hoje: string;
  fuso: string;
};

/** "libera às 16h23" — a tarefa que ainda não liberou. */
export const textoLibera = (i: ItemComHora) => `libera ${quandoFoi(i.liberaas, i.hoje, i.fuso)}`;

/** "disponível agora" / "disponível há 12 min" — a que já está valendo. */
export const textoDisponivel = (i: ItemComHora, agora: string | null) =>
  `disponível ${faz(minutosDesde(i.disponiveldesde, agora))}`;

/** Separa como o tablet: "Para pegar" só com o que já liberou. */
export function separarParaPegar<T extends { situacao: string; liberada: boolean }>(itens: T[]) {
  const paraPegar = itens.filter((i) => i.situacao === "para_pegar");
  return { liberadas: paraPegar.filter((i) => i.liberada), aindaNao: paraPegar.filter((i) => !i.liberada) };
}
