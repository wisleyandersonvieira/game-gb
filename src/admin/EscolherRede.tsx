// A rede do cliente: a lista suspensa com busca (EscolherDaLista), com "sem rede".
import { EscolherDaLista, filtrarLista } from "@/ui/EscolherDaLista";

type Rede = { redeid: number; nome: string };

/** As redes que batem com a busca, em ordem alfabética. */
export const filtrarRedes = (redes: Rede[], busca: string) => filtrarLista(redes, busca);

export function EscolherRede({ redes, valor, mudar }: { redes: Rede[]; valor: number | null; mudar: (redeid: number | null) => void }) {
  return (
    <EscolherDaLista
      itens={redes.map((r) => ({ id: r.redeid, nome: r.nome }))}
      valor={valor}
      mudar={mudar}
      rotulo="Rede"
      semItem="sem rede"
      buscaTexto="Buscar rede por parte do nome"
    />
  );
}
