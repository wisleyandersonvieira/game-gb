// "Ainda não liberadas (5)", recolhida: a mesma lista no tablet e no Quadro.
// Elas NÃO entram em "Para pegar" — ninguém pode pegar antes da hora.
import { useState } from "react";
import { textoLibera } from "@/painel/textoDaFila";

type Item = { atribuicaoid: number; titulo: string; liberaas: string | null; disponiveldesde: string | null; hoje: string; fuso: string };

export function AindaNaoLiberadas({ itens, grande = false }: { itens: Item[]; grande?: boolean }) {
  const [aberta, setAberta] = useState(false);
  if (itens.length === 0) return null;
  const texto = grande ? "text-lg" : "text-sm";
  return (
    <section className={`rounded-2xl border border-border bg-card p-3 ${grande ? "mt-4" : ""}`}>
      <button onClick={() => setAberta((v) => !v)} className={`flex w-full items-center justify-between font-semibold ${texto}`}>
        <span>
          Ainda não liberadas <span className="text-muted-foreground">({itens.length})</span>
        </span>
        <span className="text-muted-foreground">{aberta ? "▲" : "▼"}</span>
      </button>
      {aberta && (
        <ul className="mt-2 space-y-2">
          {itens.map((i) => (
            <li key={i.atribuicaoid} className={`rounded-xl bg-background px-3 py-2 ${texto}`}>
              {i.titulo} <span className="text-muted-foreground">— {textoLibera(i)}</span>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
