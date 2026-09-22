// Quadro: tarefas de hoje de quem está de folga ou afastado. O gestor passa
// cada uma para quem trabalha hoje na loja; vira uma tarefa única de hoje,
// com os mesmos pontos. Para quem recebe é esforço extra (não é obrigação).
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Botao } from "@/ui/Botao";

type Item = {
  atribuicaoid: number;
  titulo: string;
  pontos: number;
  pessoa: string;
  motivo: "folga" | "afastamento";
  passadapara: string | null;
  entregue: boolean;
};
type Pessoa = { funcionarioid: number; nome: string };

const campo = "min-w-0 rounded-lg border border-border bg-background px-3 py-2 text-sm";

export function FolgaDeHoje({ lojaid }: { lojaid: number }) {
  const itens = useQuery({
    queryKey: ["folga-hoje", lojaid],
    queryFn: async () => {
      const { data, error } = await supabase.rpc("tarefas_de_folga_hoje", { p_lojaid: lojaid });
      if (error) throw error;
      return (data ?? []) as unknown as Item[];
    },
  });
  const gente = useQuery({
    queryKey: ["trabalha-hoje", lojaid],
    queryFn: async () => {
      const { data, error } = await supabase.rpc("quem_trabalha_hoje", { p_lojaid: lojaid });
      if (error) throw error;
      return (data ?? []) as unknown as Pessoa[];
    },
  });

  const lista = itens.data ?? [];
  if (!itens.isLoading && lista.length === 0) return null;

  return (
    <section className="space-y-3 rounded-xl border border-border bg-card p-4">
      <div>
        <h2 className="font-semibold">Tarefas de quem está de folga hoje</h2>
        <p className="text-xs text-muted-foreground">
          Folga, domingo de folga e afastamento. Passe para quem trabalha hoje: vira uma tarefa de hoje com os mesmos
          pontos, que entram na aprovação. Para quem recebe é esforço extra, não obrigação.
        </p>
      </div>
      {itens.isError && <p className="text-sm text-destructive">{(itens.error as Error).message}</p>}
      <ul className="space-y-2">
        {lista.map((i) => (
          <Linha key={i.atribuicaoid} item={i} gente={gente.data ?? []} lojaid={lojaid} />
        ))}
      </ul>
    </section>
  );
}

function Linha({ item, gente, lojaid }: { item: Item; gente: Pessoa[]; lojaid: number }) {
  const qc = useQueryClient();
  const [para, setPara] = useState<number | "">("");

  const passar = useMutation({
    mutationFn: async () => {
      if (para === "") throw new Error("Escolha quem vai fazer.");
      const { error } = await supabase.rpc("passar_tarefa_de_folga", { p_atribuicaoid: item.atribuicaoid, p_funcionarioid: para });
      if (error) throw error;
    },
    onSuccess: () => {
      for (const k of ["folga-hoje", "para-entregar", "quadro"]) qc.invalidateQueries({ queryKey: [k, lojaid] });
    },
  });

  return (
    <li className="flex flex-col gap-2 rounded-lg border border-border px-3 py-2 sm:flex-row sm:items-center sm:justify-between">
      <div className="min-w-0">
        <p className="font-medium">
          {item.titulo} <span className="text-sm font-normal text-muted-foreground">· {item.pontos} pts</span>
        </p>
        <p className="text-xs text-muted-foreground">
          {item.pessoa} · {item.motivo === "folga" ? "de folga" : "afastado(a)"}
        </p>
        {passar.isError && <p className="text-xs text-destructive">{(passar.error as Error).message}</p>}
      </div>
      {item.passadapara ? (
        <span className="text-sm text-sucesso">Passada para {item.passadapara}</span>
      ) : item.entregue ? (
        <span className="text-sm text-muted-foreground">Entregue</span>
      ) : gente.length === 0 ? (
        <span className="text-xs text-muted-foreground">Ninguém trabalhando hoje nesta loja.</span>
      ) : (
        <div className="flex gap-2">
          <select
            value={para}
            onChange={(e) => setPara(e.target.value === "" ? "" : Number(e.target.value))}
            className={`${campo} flex-1 sm:w-48`}
            aria-label={`Passar "${item.titulo}" para`}
          >
            <option value="">Passar para...</option>
            {gente.map((p) => (
              <option key={p.funcionarioid} value={p.funcionarioid}>
                {p.nome}
              </option>
            ))}
          </select>
          <Botao tamanho="pequeno" disabled={para === "" || passar.isPending} onClick={() => passar.mutate()}>
            Passar
          </Botao>
        </div>
      )}
    </li>
  );
}
