// A rede do cliente: lista em ordem alfabética, com busca na primeira linha
// (por parte do nome) e a opção "Sem rede".
import { useEffect, useRef, useState } from "react";

type Rede = { redeid: number; nome: string };

const semAcento = (t: string) => t.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();

/** As redes que batem com a busca, em ordem alfabética. Separado para teste. */
export function filtrarRedes(redes: Rede[], busca: string): Rede[] {
  const b = semAcento(busca.trim());
  return [...redes]
    .filter((r) => !b || semAcento(r.nome).includes(b))
    .sort((x, y) => x.nome.localeCompare(y.nome, "pt-BR", { sensitivity: "base" }));
}

export function EscolherRede({
  redes,
  valor,
  mudar,
}: {
  redes: Rede[];
  valor: number | null;
  mudar: (redeid: number | null) => void;
}) {
  const [aberto, setAberto] = useState(false);
  const [busca, setBusca] = useState("");
  const caixa = useRef<HTMLDivElement>(null);
  const escolhida = redes.find((r) => r.redeid === valor);

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
  const lista = filtrarRedes(redes, busca);

  return (
    <div ref={caixa} className="relative">
      <button
        type="button"
        onClick={() => setAberto((v) => !v)}
        className="w-full rounded-lg border border-border bg-background px-3 py-2 text-left text-sm"
        aria-haspopup="listbox"
        aria-expanded={aberto}
      >
        Rede: {escolhida ? escolhida.nome : "sem rede"}
      </button>
      {aberto && (
        <div className="absolute z-30 mt-1 w-full overflow-hidden rounded-lg border border-border bg-card shadow-lg">
          <input
            autoFocus
            value={busca}
            onChange={(e) => setBusca(e.target.value)}
            placeholder="Buscar rede por parte do nome"
            className="w-full border-b border-border bg-background px-3 py-2 text-sm outline-none"
          />
          <ul role="listbox" className="max-h-60 overflow-y-auto">
            <li>
              <button type="button" onClick={() => escolher(null)} className="w-full px-3 py-2 text-left text-sm italic hover:bg-muted">
                Sem rede
              </button>
            </li>
            {lista.map((r) => (
              <li key={r.redeid}>
                <button
                  type="button"
                  onClick={() => escolher(r.redeid)}
                  className={`w-full px-3 py-2 text-left text-sm hover:bg-muted ${r.redeid === valor ? "font-semibold" : ""}`}
                >
                  {r.nome}
                </button>
              </li>
            ))}
            {lista.length === 0 && <li className="px-3 py-2 text-xs text-muted-foreground">Nenhuma rede com esse nome.</li>}
          </ul>
        </div>
      )}
    </div>
  );
}
