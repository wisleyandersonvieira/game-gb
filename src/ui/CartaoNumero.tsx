// Cartão de número do painel: rótulo, valor grande, detalhe e cor pelo
// significado. Com "para", o cartão inteiro leva à tela correspondente.
import { Link } from "@tanstack/react-router";
import type { ReactNode } from "react";

export type Tom = "neutro" | "primario" | "sucesso" | "pendente" | "erro";

const COR: Record<Tom, string> = {
  neutro: "text-foreground",
  primario: "text-primary",
  sucesso: "text-sucesso",
  pendente: "text-azul",
  erro: "text-destructive",
};

export function CartaoNumero({
  titulo,
  valor,
  detalhe,
  tom = "neutro",
  para,
  etiqueta,
  progresso,
}: {
  titulo: string;
  valor: ReactNode;
  detalhe?: ReactNode;
  tom?: Tom;
  para?: string;
  etiqueta?: string;
  progresso?: number;
}) {
  const corpo = (
    <>
      <div className="flex items-start justify-between gap-2">
        <p className="text-xs font-medium text-muted-foreground">{titulo}</p>
        {etiqueta && <span className="rounded-full bg-muted px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-muted-foreground">{etiqueta}</span>}
      </div>
      <p className={`mt-1 font-mono text-2xl font-medium tabular-nums sm:text-3xl ${COR[tom]}`}>{valor}</p>
      {progresso !== undefined && (
        <div className="mt-2 h-1.5 overflow-hidden rounded-full bg-muted">
          <div
            className={`h-full rounded-full ${tom === "sucesso" ? "bg-sucesso" : tom === "pendente" ? "bg-azul" : "bg-primary"}`}
            style={{ width: `${Math.min(100, Math.max(0, progresso))}%` }}
          />
        </div>
      )}
      {detalhe && <p className="mt-1 text-xs text-muted-foreground">{detalhe}</p>}
    </>
  );
  const classe = "block rounded-xl border border-border bg-card p-4 shadow-card";
  return para ? (
    <Link to={para} className={`${classe} transition hover:border-primary hover:shadow-md focus-visible:outline-2 focus-visible:outline-primary`}>
      {corpo}
    </Link>
  ) : (
    <div className={classe}>{corpo}</div>
  );
}
