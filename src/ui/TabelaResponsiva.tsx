// Tabela no computador; no celular, cada linha vira um cartão com
// "rótulo: valor", sem rolagem para o lado.
import type { ReactNode } from "react";

export type Coluna<T> = {
  titulo: string;
  valor: (linha: T) => ReactNode;
  alinhar?: "direita";
  /** No cartão do celular, vira o título do cartão. */
  principal?: boolean;
  classe?: (linha: T) => string;
};

export function TabelaResponsiva<T>({
  colunas,
  linhas,
  chave,
  vazio = "Nada por aqui.",
  aoClicar,
  destacar,
}: {
  colunas: Coluna<T>[];
  linhas: T[];
  chave: (linha: T, i: number) => string | number;
  vazio?: string;
  aoClicar?: (linha: T) => void;
  destacar?: (linha: T) => boolean;
}) {
  if (linhas.length === 0) {
    return <p className="rounded-xl border border-dashed border-border px-3 py-6 text-center text-sm text-muted-foreground">{vazio}</p>;
  }
  const principal = colunas.find((c) => c.principal) ?? colunas[0];
  const demais = colunas.filter((c) => c !== principal);
  return (
    <>
      <div className="hidden overflow-hidden rounded-xl border border-border md:block">
        <table className="w-full text-sm">
          <thead className="bg-muted/60 text-left text-muted-foreground">
            <tr>
              {colunas.map((c) => (
                <th key={c.titulo} className={`px-3 py-2 font-medium ${c.alinhar === "direita" ? "text-right" : ""}`}>
                  {c.titulo}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {linhas.map((l, i) => (
              <tr
                key={chave(l, i)}
                onClick={aoClicar ? () => aoClicar(l) : undefined}
                className={`border-t border-border bg-card ${aoClicar ? "cursor-pointer hover:bg-muted/60" : ""} ${destacar?.(l) ? "bg-primary/5" : ""}`}
              >
                {colunas.map((c) => (
                  <td key={c.titulo} className={`px-3 py-2 ${c.alinhar === "direita" ? "text-right tabular-nums" : ""} ${c.classe?.(l) ?? ""}`}>
                    {c.valor(l)}
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <ul className="space-y-2 md:hidden">
        {linhas.map((l, i) => (
          <li
            key={chave(l, i)}
            onClick={aoClicar ? () => aoClicar(l) : undefined}
            className={`rounded-xl border bg-card p-3 text-sm ${destacar?.(l) ? "border-primary" : "border-border"} ${aoClicar ? "cursor-pointer" : ""}`}
          >
            <div className={`font-medium ${principal.classe?.(l) ?? ""}`}>{principal.valor(l)}</div>
            <dl className="mt-1 grid grid-cols-[auto_1fr] gap-x-3 gap-y-0.5 text-xs">
              {demais.map((c) => (
                <div key={c.titulo} className="contents">
                  <dt className="text-muted-foreground">{c.titulo}</dt>
                  <dd className={`break-words text-right ${c.classe?.(l) ?? ""}`}>{c.valor(l)}</dd>
                </div>
              ))}
            </dl>
          </li>
        ))}
      </ul>
    </>
  );
}
