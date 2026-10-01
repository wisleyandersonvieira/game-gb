// Navegar entre meses e anos (30/09/2026): livre, para frente e para trás.
// O que continua limitado são as AÇÕES, e quem decide é o banco.
import { ChevronLeft, ChevronRight } from "lucide-react";
import { nomeDoMes, somarMes } from "./mes";

export function NavegarMes({ mes, mesAtual, aoMudar }: { mes: string; mesAtual: string; aoMudar: (mes: string) => void }) {
  const botao = "rounded-lg border border-border p-2 hover:bg-muted";
  return (
    <div className="flex flex-wrap items-center gap-2">
      <button type="button" aria-label="Mês anterior" onClick={() => aoMudar(somarMes(mes, -1))} className={botao}>
        <ChevronLeft className="h-4 w-4" />
      </button>
      <span className="min-w-40 text-center text-sm font-semibold capitalize">{nomeDoMes(mes)}</span>
      <button type="button" aria-label="Próximo mês" onClick={() => aoMudar(somarMes(mes, 1))} className={botao}>
        <ChevronRight className="h-4 w-4" />
      </button>
      {mes !== mesAtual && (
        <button type="button" onClick={() => aoMudar(mesAtual)} className="text-sm text-primary underline-offset-2 hover:underline">
          voltar para o mês atual
        </button>
      )}
      {mes < mesAtual && <span className="text-xs text-muted-foreground">mês que já passou</span>}
    </div>
  );
}
