// "Minhas tarefas" no celular: o que é dela hoje, e a entrega com foto.
//
// Só aparece o que JÁ É DELA — a tarefa que ela pegou no tablet ou que foi
// atribuída ao nome dela. A fila da loja não vem para cá: pegar é no tablet.
import { createFileRoute } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import {
  autorizacaoDeFotoDoCelular,
  entregarPeloCelular,
  minhasTarefas,
  type MinhaTarefa,
} from "@/servidor/colaborador";
import { OPERACIONAL } from "@/ui/prazos";

export const Route = createFileRoute("/eu/tarefas")({ component: Tarefas });

const FAIXA: Record<MinhaTarefa["situacao"], { texto: string; cor: string }> = {
  a_fazer: { texto: "A fazer", cor: "bg-primary/15 text-primary" },
  esperando: { texto: "Esperando o gestor", cor: "bg-amber-500/15 text-amber-600 dark:text-amber-400" },
  aprovada: { texto: "Aprovada", cor: "bg-emerald-500/15 text-emerald-600 dark:text-emerald-400" },
  recusada: { texto: "Recusada", cor: "bg-destructive/15 text-destructive" },
};

function hora(iso: string | null) {
  if (!iso) return "";
  return new Date(iso).toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" });
}

function Tarefas() {
  const [entregando, setEntregando] = useState<MinhaTarefa | null>(null);

  const tarefas = useQuery({
    queryKey: ["eu-tarefas"],
    queryFn: () => minhasTarefas(),
    staleTime: OPERACIONAL,
    refetchOnWindowFocus: true,
  });

  const lista = tarefas.data ?? [];

  return (
    <div className="space-y-4">
      <h1 className="font-display text-2xl font-semibold">Minhas tarefas</h1>

      {tarefas.isLoading ? (
        <p className="text-sm text-muted-foreground">Carregando…</p>
      ) : lista.length === 0 ? (
        <p className="rounded-2xl border border-border bg-card p-5 text-sm text-muted-foreground">
          Nenhuma tarefa sua hoje. Pegue uma no tablet da loja.
        </p>
      ) : (
        <ul className="space-y-3">
          {lista.map((t) => {
            const f = FAIXA[t.situacao];
            return (
              <li key={t.atribuicaoid} className="rounded-2xl border border-border bg-card p-4">
                <div className="flex items-start justify-between gap-3">
                  <p className="font-medium leading-snug">{t.titulo}</p>
                  <span className="shrink-0 tabular-nums text-sm text-muted-foreground">+{t.pontos}</span>
                </div>
                <p className="mt-1 text-xs text-muted-foreground">
                  {t.loja}
                  {t.pegaem ? ` · você pegou às ${hora(t.pegaem)}` : ""}
                </p>
                <div className="mt-3 flex items-center justify-between gap-3">
                  <span className={`rounded-full px-2.5 py-1 text-xs font-medium ${f.cor}`}>
                    {/* Antes da hora, a tarefa aparece mas ainda não dá para entregar. */}
                    {t.liberada ? f.texto : `a partir das ${hora(t.liberaas)}`}
                  </span>
                  {t.liberada && (t.situacao === "a_fazer" || t.situacao === "recusada") ? (
                    <button
                      onClick={() => setEntregando(t)}
                      className="rounded-xl bg-primary px-4 py-2.5 text-sm font-medium text-primary-foreground"
                    >
                      Entregar
                    </button>
                  ) : null}
                </div>
              </li>
            );
          })}
        </ul>
      )}

      {entregando ? <Entregar tarefa={entregando} fechar={() => setEntregando(null)} /> : null}
    </div>
  );
}

function Entregar({ tarefa, fechar }: { tarefa: MinhaTarefa; fechar: () => void }) {
  const qc = useQueryClient();
  const [arquivo, setArquivo] = useState<File | null>(null);
  const [observacao, setObservacao] = useState("");

  const enviar = useMutation({
    mutationFn: async () => {
      let caminho: string | null = null;
      let bilhete: string | null = null;

      if (arquivo) {
        // A foto sobe direto para o Storage com uma autorização de prazo
        // curto: a chave secreta nunca passa pelo celular. Quem olha a foto
        // depois — a impressão digital e a hora em que ela foi tirada — é o
        // SERVIDOR, que baixa o arquivo. Este aparelho não opina sobre ela.
        const a = await autorizacaoDeFotoDoCelular({ data: { atribuicaoid: tarefa.atribuicaoid } });
        const { error } = await supabase.storage.from("entregas").uploadToSignedUrl(a.caminho, a.token, arquivo);
        if (error) throw new Error("A foto não subiu. Tente de novo.");
        caminho = a.caminho;
        bilhete = a.bilhete;
      }

      return await entregarPeloCelular({
        data: {
          atribuicaoid: tarefa.atribuicaoid,
          caminho,
          bilhete,
          observacao: observacao.trim() || null,
        },
      });
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["eu-tarefas"] });
      qc.invalidateQueries({ queryKey: ["eu-inicio"] });
      fechar();
    },
  });

  return (
    <div className="fixed inset-0 z-20 flex items-end bg-black/50" onClick={fechar}>
      <div
        className="max-h-[92vh] w-full overflow-y-auto rounded-t-3xl bg-background p-5 pb-[max(1.25rem,env(safe-area-inset-bottom))]"
        onClick={(e) => e.stopPropagation()}
      >
        <h2 className="font-display text-xl font-semibold">{tarefa.titulo}</h2>

        <p className="mt-3 text-sm text-muted-foreground">
          Tire a foto <strong className="text-foreground">agora</strong>, com a tarefa pronta na sua frente. Foto tirada
          antes, ou escolhida da galeria, pode ser recusada.
        </p>

        <label className="mt-4 block">
          <span className="text-sm font-medium">Foto</span>
          <input
            type="file"
            accept="image/*"
            capture="environment"
            onChange={(e) => setArquivo(e.target.files?.[0] ?? null)}
            className="mt-1.5 block w-full rounded-xl border border-border p-3 text-sm file:mr-3 file:rounded-lg file:border-0 file:bg-muted file:px-3 file:py-2 file:text-sm"
          />
        </label>

        <label className="mt-4 block">
          <span className="text-sm font-medium">Observação (opcional)</span>
          <textarea
            value={observacao}
            onChange={(e) => setObservacao(e.target.value)}
            rows={3}
            className="mt-1.5 w-full rounded-xl border border-border bg-background p-3 text-sm"
            placeholder="Algo que o gestor precise saber"
          />
        </label>

        {enviar.isError ? (
          <p className="mt-3 rounded-xl bg-destructive/10 p-3 text-sm text-destructive">
            {(enviar.error as Error).message}
          </p>
        ) : null}

        <div className="mt-5 flex gap-3">
          <button onClick={fechar} className="flex-1 rounded-xl border border-border px-4 py-3 text-sm">
            Cancelar
          </button>
          <button
            onClick={() => enviar.mutate()}
            disabled={enviar.isPending}
            className="flex-1 rounded-xl bg-primary px-4 py-3 text-sm font-medium text-primary-foreground disabled:opacity-60"
          >
            {enviar.isPending ? "Enviando…" : "Enviar entrega"}
          </button>
        </div>
      </div>
    </div>
  );
}
