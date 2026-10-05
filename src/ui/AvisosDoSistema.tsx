// Início: os avisos do sistema ainda não lidos (agenda, comunicado, fotos
// apagadas, rotina que não achou a tarefa...), com "Marcar como lido".
// Morava no arquivo do Telegram, que saiu em 04/10/2026; o aviso não é do
// Telegram e continua igual. Lê a tabela direto: a regra dela só devolve
// linhas ao master (o gerente recebe a lista vazia).
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Bell } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";

const dataHora = (iso: string) =>
  new Date(iso).toLocaleString("pt-BR", { timeZone: "America/Sao_Paulo", day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit" });

export function AvisosDoSistema() {
  const qc = useQueryClient();
  const avisos = useQuery({
    queryKey: ["avisos-sistema"],
    refetchInterval: 60_000,
    queryFn: async () => {
      const { data, error } = await supabase
        .from("avisossistema")
        .select("avisoid, texto, criadoem")
        .is("lidoem", null)
        .order("criadoem", { ascending: false })
        .limit(10);
      if (error) throw error;
      return data ?? [];
    },
  });
  const lido = useMutation({
    mutationFn: async (avisoid: number) => {
      const { error } = await supabase.rpc("marcar_aviso_lido", { p_avisoid: avisoid });
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ["avisos-sistema"] }),
  });

  const lista = avisos.data ?? [];
  if (lista.length === 0) return null;
  return (
    <ul className="space-y-2" aria-label="Novidades">
      {lista.map((a) => (
        <li key={a.avisoid} className="flex items-start gap-2 rounded-lg border border-border bg-card px-3 py-2 text-sm">
          <Bell className="mt-0.5 h-4 w-4 shrink-0 text-azul" aria-hidden />
          <span className="flex-1">
            {a.texto} <span className="text-xs text-muted-foreground">({dataHora(a.criadoem)})</span>
          </span>
          <button
            onClick={() => lido.mutate(a.avisoid)}
            disabled={lido.isPending}
            className="shrink-0 rounded-md px-2 py-0.5 text-xs text-muted-foreground hover:bg-muted hover:text-foreground"
          >
            Marcar como lido
          </button>
        </li>
      ))}
    </ul>
  );
}
