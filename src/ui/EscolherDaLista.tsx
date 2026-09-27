// Escolher um item de uma lista: ordem alfabética, busca na primeira linha
// (por parte do nome, sem ligar para acento nem maiúscula) e a opção "sem".
// Usada para Rede (admin) e Jornada (Equipe).
import { useEffect, useRef, useState } from "react";

export type ItemDaLista = { id: number; nome: string };

const semAcento = (t: string) => t.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();

/** Os itens que batem com a busca, em ordem alfabética. Separado para teste. */
export function filtrarLista<T extends { nome: string }>(itens: T[], busca: string): T[] {
  const b = semAcento(busca.trim());
  return [...itens]
    .filter((r) => !b || semAcento(r.nome).includes(b))
    .sort((x, y) => x.nome.localeCompare(y.nome, "pt-BR", { sensitivity: "base" }));
}

export function EscolherDaLista({
  itens,
  valor,
  mudar,
  rotulo,
  semItem,
  buscaTexto,
  abertoDeInicio = false,
}: {
  itens: ItemDaLista[];
  valor: number | null;
  mudar: (id: number | null) => void;
  /** "Rede", "Jornada". */
  rotulo: string;
  /** "sem rede", "sem jornada". */
  semItem: string;
  buscaTexto: string;
  abertoDeInicio?: boolean;
}) {
  const [aberto, setAberto] = useState(abertoDeInicio);
  const [busca, setBusca] = useState("");
  const caixa = useRef<HTMLDivElement>(null);
  const escolhido = itens.find((r) => r.id === valor);

  useEffect(() => {
    if (!aberto) return;
    const fora = (e: MouseEvent) => {
      if (caixa.current && !caixa.current.contains(e.target as Node)) setAberto(false);
    };
    document.addEventListener("mousedown", fora);
    return () => document.removeEventListener("mousedown", fora);
  }, [aberto]);

  const escolher = (id: number | null) => {
    mudar(id);
    setAberto(false);
    setBusca("");
  };
  const lista = filtrarLista(itens, busca);

  return (
    <div ref={caixa} className="relative">
      <button
        type="button"
        onClick={() => setAberto((v) => !v)}
        className="w-full rounded-lg border border-border bg-background px-3 py-2 text-left text-sm"
        aria-haspopup="listbox"
        aria-expanded={aberto}
      >
        {rotulo}: {escolhido ? escolhido.nome : semItem}
      </button>
      {aberto && (
        <div className="absolute z-30 mt-1 w-full min-w-56 overflow-hidden rounded-lg border border-border bg-card shadow-lg">
          <input
            autoFocus
            value={busca}
            onChange={(e) => setBusca(e.target.value)}
            placeholder={buscaTexto}
            className="w-full border-b border-border bg-background px-3 py-2 text-sm outline-none"
          />
          <ul role="listbox" className="max-h-60 overflow-y-auto">
            <li>
              <button type="button" onClick={() => escolher(null)} className="w-full px-3 py-2 text-left text-sm italic hover:bg-muted">
                {semItem.charAt(0).toUpperCase() + semItem.slice(1)}
              </button>
            </li>
            {lista.map((r) => (
              <li key={r.id}>
                <button
                  type="button"
                  onClick={() => escolher(r.id)}
                  className={`w-full px-3 py-2 text-left text-sm hover:bg-muted ${r.id === valor ? "font-semibold" : ""}`}
                >
                  {r.nome}
                </button>
              </li>
            ))}
            {lista.length === 0 && <li className="px-3 py-2 text-xs text-muted-foreground">Nada com esse nome.</li>}
          </ul>
        </div>
      )}
    </div>
  );
}
