import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";

const campo =
  "rounded-lg border border-border bg-background px-3 py-2 text-sm placeholder:text-muted-foreground";

/** Atualiza tudo o que uma justificativa muda: pendências, nota, painel, listas. */
export function aposJustificar(qc: ReturnType<typeof useQueryClient>) {
  for (const k of ["justificativas", "justificaveis", "pendencias", "ranking-mensal", "analise-tarefas", "painel", "para-entregar", "quadro", "ganhadores"]) {
    qc.invalidateQueries({ queryKey: [k] });
  }
}

/**
 * Motivo + dois botões: "Registrar e aceitar" (o gestor já decide) ou
 * "Registrar para decidir depois" (fica pendente, como virá pelo bot).
 */
export function Justificar({
  atribuicaoid,
  dia,
  aoTerminar,
}: {
  atribuicaoid: number;
  dia: string;
  aoTerminar?: (texto: string) => void;
}) {
  const qc = useQueryClient();
  const [motivo, setMotivo] = useState("");

  const registrar = useMutation({
    mutationFn: async (aceitar: boolean) => {
      if (!motivo.trim()) throw new Error("Informe o motivo.");
      const { error } = await supabase.rpc("registrar_justificativa", {
        p_atribuicaoid: atribuicaoid,
        p_dia: dia,
        p_motivo: motivo.trim(),
        p_aceitar: aceitar,
      });
      if (error) throw error;
      return aceitar;
    },
    onSuccess: (aceitar) => {
      setMotivo("");
      aposJustificar(qc);
      aoTerminar?.(aceitar ? "Justificativa aceita." : "Justificativa registrada; falta decidir.");
    },
  });

  return (
    <div className="space-y-2">
      <input
        placeholder="Por que não se aplica? (ex.: não chegou mercadoria)"
        value={motivo}
        onChange={(e) => setMotivo(e.target.value)}
        className={`${campo} w-full`}
      />
      <div className="flex flex-wrap gap-2">
        <button
          type="button"
          disabled={registrar.isPending}
          onClick={() => registrar.mutate(true)}
          className="rounded-md bg-primary px-3 py-1.5 text-sm font-semibold text-primary-foreground disabled:opacity-60"
        >
          Registrar e aceitar
        </button>
        <button
          type="button"
          disabled={registrar.isPending}
          onClick={() => registrar.mutate(false)}
          className="rounded-md border border-border px-3 py-1.5 text-sm disabled:opacity-60"
        >
          Registrar para decidir depois
        </button>
      </div>
      {registrar.isError && <p className="text-sm text-destructive">{(registrar.error as Error).message}</p>}
    </div>
  );
}
