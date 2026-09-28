// O quadro da medição, o MESMO no tablet e no celular (29/09/2026). Só
// aparece com `?medir=` no endereço; mostra o total e o tempo de cada etapa.
import type { Medida } from "@/painel/medicaoDoTablet";

function hora(ms: number) {
  return new Date(ms).toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" }).replace(":", "h");
}

export function QuadroDaMedicao({
  caminho,
  medidas,
  rotuloTotal,
  limite,
}: {
  caminho: "novo" | "antigo";
  medidas: Medida[];
  /** O que o total mede ("do 6º dígito até o cartão mudar"). */
  rotuloTotal: string;
  /** Abaixo disto o total fica verde (o alvo). */
  limite: number;
}) {
  return (
    <section className="mt-6 space-y-3 rounded-xl border-2 border-dashed border-border bg-card p-4 text-sm">
      <p className="font-semibold">
        Medição ligada — caminho {caminho === "antigo" ? "ANTIGO (para comparar)" : "NOVO"}.{" "}
        <span className="font-normal text-muted-foreground">
          Troque com ?medir=1 / ?medir=antigo, desligue com ?medir=0.
        </span>
      </p>
      {medidas.length === 0 && <p className="text-muted-foreground">Faça a ação para medir.</p>}
      {medidas.map((m) => (
        <div key={m.quando} className="rounded-lg border border-border p-3">
          <p className="mb-1 font-semibold">
            {m.acao === "aceite" ? "Aceite" : "Entrega"} ({m.caminho}) às {hora(m.quando)}:{" "}
            <span className={`font-mono ${m.total < limite ? "text-sucesso" : "text-destructive"}`}>{m.total} ms</span>{" "}
            <span className="font-normal text-muted-foreground">{rotuloTotal}</span>
          </p>
          {m.detalhes.length > 0 && <p className="mb-1 text-xs text-muted-foreground">{m.detalhes.join(" · ")}</p>}
          <table className="w-full">
            <tbody>
              {m.etapas.map(([rotulo, ms]) => (
                <tr key={rotulo}>
                  <td className="pr-3">{rotulo}</td>
                  <td className="text-right font-mono">{ms} ms</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ))}
    </section>
  );
}
