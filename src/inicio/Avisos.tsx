// Início: avisos que pedem atenção e a situação da rotina de hoje.
import { Link } from "@tanstack/react-router";
import { CircleAlert, CircleCheck, Clock } from "lucide-react";
import type { PainelInicio } from "./tipos";

const hora = (iso: string) => new Date(iso).toLocaleTimeString("pt-BR", { timeZone: "America/Sao_Paulo", hour: "2-digit", minute: "2-digit" });

export function SituacaoRotina({ rotina }: { rotina: PainelInicio["rotina"] }) {
  return (
    <Link to="/configuracoes" className="inline-flex items-center gap-1.5 text-xs text-muted-foreground hover:text-foreground">
      {!rotina ? (
        <>
          <Clock className="h-3.5 w-3.5" aria-hidden /> Lista de tarefas de hoje ainda não gerada
        </>
      ) : rotina.resultado === "ok" ? (
        <>
          <CircleCheck className="h-3.5 w-3.5 text-sucesso" aria-hidden /> Lista de tarefas de hoje: {hora(rotina.quando)}
          {rotina.origem === "manual" ? " (rodada à mão)" : ""} ✓
        </>
      ) : (
        <>
          <CircleAlert className="h-3.5 w-3.5 text-destructive" aria-hidden />
          <span className="text-destructive">Erro na rotina de hoje ({hora(rotina.quando)}): veja em Configurações</span>
        </>
      )}
    </Link>
  );
}

export function Avisos({ avisos }: { avisos: PainelInicio["avisos"] }) {
  if (!avisos) return null;
  const itens: { texto: string; para: string; grave?: boolean }[] = [];
  if (avisos.livro === "diferenca") {
    itens.push({ texto: "Diferença encontrada entre o saldo e o livro de pontos. Nada foi corrigido: veja os detalhes.", para: "/configuracoes", grave: true });
  }
  if (avisos.agendamentospassados > 0) {
    const n = avisos.agendamentospassados;
    itens.push({
      texto: `${n} ${n === 1 ? "agendamento já passou e continua" : "agendamentos já passaram e continuam"} como Confirmado.`,
      para: "/agenda",
    });
  }
  if (avisos.comunicados24h.comunicados > 0) {
    const c = avisos.comunicados24h;
    itens.push({
      texto: `${c.comunicados} ${c.comunicados === 1 ? "comunicado" : "comunicados"} sem ciência há mais de 24 h (${c.pessoas} ${c.pessoas === 1 ? "pessoa" : "pessoas"}).`,
      para: "/comunicados",
    });
  }
  if (itens.length === 0) return null;
  return (
    <ul className="space-y-2" aria-label="Avisos">
      {itens.map((i) => (
        <li key={i.texto}>
          <Link
            to={i.para}
            className={`flex items-start gap-2 rounded-lg border px-3 py-2 text-sm transition hover:shadow-sm ${
              i.grave ? "border-destructive/50 bg-destructive/10 text-destructive" : "border-accent/50 bg-accent/10"
            }`}
          >
            <CircleAlert className={`mt-0.5 h-4 w-4 shrink-0 ${i.grave ? "" : "text-accent"}`} aria-hidden />
            <span>{i.texto}</span>
          </Link>
        </li>
      ))}
    </ul>
  );
}
