import { createFileRoute } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { dataHoraBr } from "@/rh/pdf";

export const Route = createFileRoute("/_authenticated/onboarding")({
  component: Onboarding,
});

const campo =
  "rounded-lg border border-border bg-background px-3 py-2 text-sm placeholder:text-muted-foreground";

type Etapa = { etapaid: number; nome: string; ordem: number; ativo: boolean };
type Item = {
  itemid: number;
  funcionarioid: number;
  etapaid: number;
  concluidoem: string | null;
  observacao: string | null;
  documentoid: number | null;
};

function useEtapas() {
  return useQuery({
    queryKey: ["onboarding-etapas"],
    queryFn: async () => {
      const { data, error } = await supabase.from("onboardingetapas").select("etapaid, nome, ordem, ativo").order("ordem").order("nome");
      if (error) throw error;
      return (data ?? []) as Etapa[];
    },
  });
}

function Onboarding() {
  const [aba, setAba] = useState<"pessoas" | "etapas">("pessoas");
  return (
    <div className="mx-auto max-w-5xl space-y-6">
      <h1 className="text-2xl font-bold tracking-tight sm:text-3xl">Onboarding</h1>
      <p className="text-sm text-muted-foreground">
        O checklist de admissão de cada pessoa. As etapas são da sua conta: você cria, renomeia, ordena e desativa
        (desativar nunca apaga o que já foi marcado).
      </p>
      <div className="flex gap-2 border-b border-border">
        {(
          [
            ["pessoas", "Pessoas"],
            ["etapas", "Etapas"],
          ] as const
        ).map(([id, rotulo]) => (
          <button
            key={id}
            onClick={() => setAba(id)}
            className={`rounded-t-lg px-4 py-2 text-sm font-medium ${aba === id ? "bg-card text-foreground" : "text-muted-foreground"}`}
          >
            {rotulo}
          </button>
        ))}
      </div>
      {aba === "pessoas" ? <Pessoas /> : <Etapas />}
    </div>
  );
}

function Pessoas() {
  const qc = useQueryClient();
  const etapas = useEtapas();
  const [aberto, setAberto] = useState<number | null>(null);
  const [aviso, setAviso] = useState<string | null>(null);

  const dados = useQuery({
    queryKey: ["onboarding"],
    queryFn: async () => {
      const [{ data: pessoas, error }, { data: status }, { data: itens }] = await Promise.all([
        supabase.from("funcionarios").select("funcionarioid, nomecompleto, ativo").order("nomecompleto"),
        supabase.from("onboardingstatus").select("funcionarioid, statusworkflow, iniciadoem, concluidoem"),
        supabase.from("onboardingitens").select("itemid, funcionarioid, etapaid, concluidoem, observacao, documentoid"),
      ]);
      if (error) throw error;
      return {
        pessoas: pessoas ?? [],
        status: new Map((status ?? []).map((s) => [s.funcionarioid, s])),
        itens: (itens ?? []) as Item[],
      };
    },
  });

  const master = useQuery({
    queryKey: ["sou-master"],
    queryFn: async () => (await supabase.rpc("sou_master")).data === true,
  });

  const acao = useMutation({
    mutationFn: async (fazer: () => Promise<{ error: unknown }>) => {
      const { error } = await fazer();
      if (error) throw error;
    },
    onSuccess: () => {
      setAviso(null);
      qc.invalidateQueries({ queryKey: ["onboarding"] });
    },
    onError: (e) => setAviso((e as Error).message),
  });
  const rpc = (nome: string, args: Record<string, unknown>) =>
    acao.mutate(() => supabase.rpc(nome as never, args as never) as unknown as Promise<{ error: unknown }>);

  const d = dados.data;
  const nomeEtapa = new Map((etapas.data ?? []).map((e) => [e.etapaid, e]));
  const ativasSemItem = (fid: number) =>
    (etapas.data ?? []).filter((e) => e.ativo && !(d?.itens ?? []).some((i) => i.funcionarioid === fid && i.etapaid === e.etapaid)).length;

  return (
    <div className="space-y-2">
      {aviso && <p className="text-sm text-destructive">{aviso}</p>}
      {dados.isLoading && <p className="text-muted-foreground">Carregando...</p>}
      {(d?.pessoas ?? [])
        .filter((p) => p.ativo || d?.status.has(p.funcionarioid))
        .map((p) => {
          const st = d?.status.get(p.funcionarioid);
          const itens = (d?.itens ?? [])
            .filter((i) => i.funcionarioid === p.funcionarioid)
            .sort((a, b) => (nomeEtapa.get(a.etapaid)?.ordem ?? 0) - (nomeEtapa.get(b.etapaid)?.ordem ?? 0));
          const feitos = itens.filter((i) => i.concluidoem).length;
          const faltamNovas = st ? ativasSemItem(p.funcionarioid) : 0;
          return (
            <div key={p.funcionarioid} className="space-y-2 rounded-lg border border-border bg-card px-4 py-3">
              <div className="flex flex-wrap items-center justify-between gap-2">
                <button className="text-left font-medium" onClick={() => setAberto(aberto === p.funcionarioid ? null : p.funcionarioid)}>
                  {p.nomecompleto}
                  {!p.ativo && <span className="ml-2 text-xs text-muted-foreground">(desativado)</span>}
                </button>
                {st ? (
                  <span className={`text-sm ${st.statusworkflow === "Concluído" ? "text-sucesso" : "text-azul"}`}>
                    {st.statusworkflow === "Concluído" ? `✓ Concluído em ${dataHoraBr(st.concluidoem!)}` : `${feitos} de ${itens.length} etapas`}
                  </span>
                ) : (
                  p.ativo && (
                    <button
                      onClick={() => {
                        rpc("iniciar_onboarding", { p_funcionarioid: p.funcionarioid });
                        setAberto(p.funcionarioid);
                      }}
                      className="rounded-md bg-primary px-3 py-1 text-sm font-semibold text-primary-foreground"
                    >
                      Iniciar onboarding
                    </button>
                  )
                )}
              </div>
              {aberto === p.funcionarioid && st && (
                <div className="space-y-1 border-t border-border pt-2">
                  {faltamNovas > 0 && p.ativo && (
                    <button onClick={() => rpc("iniciar_onboarding", { p_funcionarioid: p.funcionarioid })} className="text-xs text-azul underline">
                      Há {faltamNovas} {faltamNovas === 1 ? "etapa nova" : "etapas novas"} na conta. Acrescentar ao checklist
                    </button>
                  )}
                  {itens.map((i) => (
                    <ItemDoChecklist key={i.itemid} item={i} etapa={nomeEtapa.get(i.etapaid)} podeDocumento={!!master.data} rpc={rpc} />
                  ))}
                </div>
              )}
            </div>
          );
        })}
    </div>
  );
}

function ItemDoChecklist({
  item,
  etapa,
  podeDocumento,
  rpc,
}: {
  item: Item;
  etapa: Etapa | undefined;
  podeDocumento: boolean;
  rpc: (nome: string, args: Record<string, unknown>) => void;
}) {
  const [obs, setObs] = useState(item.observacao ?? "");
  const docs = useQuery({
    queryKey: ["documentos-da-pessoa-onboarding", item.funcionarioid],
    enabled: podeDocumento,
    queryFn: async () => {
      const { data } = await supabase
        .from("documentospessoais")
        .select("documentoid, tipodocumento, nomearquivo, situacao")
        .eq("funcionarioid", item.funcionarioid)
        .in("situacao", ["Ativo", "Arquivado"]);
      return data ?? [];
    },
  });

  return (
    <div className="flex flex-wrap items-center gap-2 text-sm">
      <label className="flex min-w-48 flex-1 items-center gap-2">
        <input
          type="checkbox"
          checked={!!item.concluidoem}
          onChange={(e) => rpc("marcar_etapa_onboarding", { p_itemid: item.itemid, p_feito: e.target.checked })}
        />
        <span className={etapa?.ativo === false ? "text-muted-foreground" : ""}>
          {etapa?.nome ?? "Etapa"}
          {etapa?.ativo === false && " (etapa desativada)"}
        </span>
        {item.concluidoem && <span className="text-xs text-muted-foreground">{dataHoraBr(item.concluidoem)}</span>}
      </label>
      <input
        placeholder="Observação"
        value={obs}
        onChange={(e) => setObs(e.target.value)}
        onBlur={() => obs !== (item.observacao ?? "") && rpc("marcar_etapa_onboarding", { p_itemid: item.itemid, p_feito: !!item.concluidoem, p_observacao: obs })}
        className={`${campo} py-1 text-xs sm:w-56`}
      />
      {podeDocumento && (
        <select
          value={item.documentoid ?? ""}
          onChange={(e) =>
            e.target.value &&
            rpc("marcar_etapa_onboarding", { p_itemid: item.itemid, p_feito: !!item.concluidoem, p_documentoid: Number(e.target.value) })
          }
          className={`${campo} py-1 text-xs`}
          aria-label="Documento ligado"
        >
          <option value="">Ligar documento...</option>
          {(docs.data ?? []).map((d) => (
            <option key={d.documentoid} value={d.documentoid}>
              {d.tipodocumento} · {d.nomearquivo}
            </option>
          ))}
        </select>
      )}
    </div>
  );
}

function Etapas() {
  const qc = useQueryClient();
  const etapas = useEtapas();
  const [nome, setNome] = useState("");
  const [erro, setErro] = useState<string | null>(null);

  const salvar = useMutation({
    mutationFn: async (x: { id?: number; nome?: string; ordem?: number; ativo?: boolean }) => {
      if (x.id === undefined) {
        const ordem = Math.max(0, ...(etapas.data ?? []).map((e) => e.ordem)) + 1;
        const { error } = await supabase.from("onboardingetapas").insert({ nome: (x.nome ?? "").trim(), ordem });
        if (error) throw error.code === "23505" ? new Error("Já existe uma etapa com esse nome.") : error;
        return;
      }
      const mudar: { nome?: string; ordem?: number; ativo?: boolean } = {};
      if (x.nome !== undefined) mudar.nome = x.nome;
      if (x.ordem !== undefined) mudar.ordem = x.ordem;
      if (x.ativo !== undefined) mudar.ativo = x.ativo;
      const { error } = await supabase.from("onboardingetapas").update(mudar).eq("etapaid", x.id);
      if (error) throw error;
    },
    onSuccess: () => {
      setErro(null);
      setNome("");
      qc.invalidateQueries({ queryKey: ["onboarding-etapas"] });
    },
    onError: (e) => setErro((e as Error).message),
  });

  const lista = etapas.data ?? [];
  return (
    <div className="space-y-3">
      <form
        onSubmit={(e) => {
          e.preventDefault();
          if (nome.trim()) salvar.mutate({ nome });
        }}
        className="flex flex-wrap gap-2 rounded-xl border border-border bg-card p-4"
      >
        <input placeholder="Nova etapa (ex.: Entrega do uniforme)" maxLength={120} value={nome} onChange={(e) => setNome(e.target.value)} className={`${campo} flex-1`} />
        <button type="submit" className="rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground">
          Adicionar
        </button>
      </form>
      {erro && <p className="text-sm text-destructive">{erro}</p>}
      {lista.map((e, i) => (
        <div key={e.etapaid} className="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-border bg-card px-4 py-2">
          <span className={e.ativo ? "" : "text-muted-foreground line-through"}>
            {i + 1}. {e.nome}
          </span>
          <span className="flex gap-2">
            <button
              disabled={i === 0}
              onClick={() => {
                const acima = lista[i - 1];
                salvar.mutate({ id: e.etapaid, ordem: acima.ordem });
                salvar.mutate({ id: acima.etapaid, ordem: e.ordem });
              }}
              className="rounded-md border border-border px-2 py-1 text-sm disabled:opacity-40"
              aria-label="Subir"
            >
              ↑
            </button>
            <button
              onClick={() => {
                const novo = window.prompt("Novo nome da etapa:", e.nome);
                if (novo && novo.trim()) salvar.mutate({ id: e.etapaid, nome: novo.trim() });
              }}
              className="rounded-md border border-border px-3 py-1 text-sm"
            >
              Renomear
            </button>
            <button onClick={() => salvar.mutate({ id: e.etapaid, ativo: !e.ativo })} className="rounded-md border border-border px-3 py-1 text-sm">
              {e.ativo ? "Desativar" : "Reativar"}
            </button>
          </span>
        </div>
      ))}
    </div>
  );
}
