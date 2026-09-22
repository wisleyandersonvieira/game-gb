// Estados padrão de qualquer lista ou painel: carregando, vazio e erro.
import { AlertTriangle, Inbox, Loader2 } from "lucide-react";
import type { ReactNode } from "react";

export function Carregando({ texto = "Carregando..." }: { texto?: string }) {
  return (
    <p className="flex items-center gap-2 py-6 text-sm text-muted-foreground" role="status">
      <Loader2 className="h-4 w-4 animate-spin" aria-hidden /> {texto}
    </p>
  );
}

export function Vazio({ texto, acao }: { texto: string; acao?: ReactNode }) {
  return (
    <div className="flex flex-col items-center gap-2 rounded-xl border border-dashed border-border px-4 py-8 text-center text-sm text-muted-foreground">
      <Inbox className="h-6 w-6" aria-hidden />
      <p>{texto}</p>
      {acao}
    </div>
  );
}

export function ErroTela({ erro }: { erro: unknown }) {
  const texto = erro instanceof Error ? erro.message : typeof erro === "string" ? erro : "Algo deu errado.";
  return (
    <p className="flex items-start gap-2 rounded-lg border border-destructive/40 bg-destructive/10 px-3 py-2 text-sm text-destructive" role="alert">
      <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" aria-hidden /> {texto}
    </p>
  );
}
