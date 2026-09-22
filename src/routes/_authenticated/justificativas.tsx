import { createFileRoute } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Justificar, aposJustificar } from "@/pessoas/justificar";
import { Pagina } from "@/ui/Pagina";

export const Route = createFileRoute("/_authenticated/justificativas")({
  component: Justificativas,
});

const campo =
  "rounded-lg border border-border bg-background px-3 py-2 text-sm placeholder:text-muted-foreground";

const hoje = () => new Intl.DateTimeFormat("en-CA", { timeZone: "America/Sao_Paulo" }).format(new Date());
const dia = (iso: string) => `${iso.slice(8, 10)}/${iso.slice(5, 7)}/${iso.slice(0, 4)}`;

const COR: Record<string, string> = {
  Pendente: "border-azul/40 bg-azul-soft text-azul",
  Aceita: "border-sucesso/40 bg-sucesso-soft text-sucesso",
  Recusada: "border-perigo/40 bg-perigo-soft text-perigo",
};

type Linha = {
  justificativaid: number;
  atribuicaoid: number;
  funcionarioid: number;
  lojaid: number;
  dia: string;
  motivo: string;
  status: string;
  origem: string;
  motivorecusa: string | null;
  pessoa: string;
  tarefa: string;
  loja: string;
};

function useJustificativas() {
  return useQuery({
    queryKey: ["justificativas"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("justificativas")
        .select("justificativaid, atribuicaoid, funcionarioid, lojaid, dia, motivo, status, origem, motivorecusa")
        .order("dia", { ascending: false })
        .order("justificativaid", { ascending: false })
        .limit(300);
      if (error) throw error;
      const linhas = data ?? [];
      if (linhas.length === 0) return [] as Linha[];
      const [{ data: pessoas }, { data: atribuicoes }, { data: tarefas }, { data: lojas }] = await Promise.all([
        supabase.from("funcionarios").select("funcionarioid, nomecompleto"),
        supabase.from("tarefasatribuidas").select("atribuicaoid, tarefaid").in("atribuicaoid", linhas.map((l) => l.atribuicaoid)),
        supabase.from("tarefas").select("tarefaid, titulo"),
        supabase.from("lojas").select("lojaid, nome"),
      ]);
      const nome = new Map((pessoas ?? []).map((p) => [p.funcionarioid, p.nomecompleto]));
      const titulo = new Map((tarefas ?? []).map((t) => [t.tarefaid, t.titulo]));
      const tarefaDa = new Map((atribuicoes ?? []).map((a) => [a.atribuicaoid, titulo.get(a.tarefaid) ?? "—"]));
      const loja = new Map((lojas ?? []).map((l) => [l.lojaid, l.nome]));
      return linhas.map((l) => ({
        ...l,
        pessoa: nome.get(l.funcionarioid) ?? "—",
        tarefa: tarefaDa.get(l.atribuicaoid) ?? "—",
        loja: loja.get(l.lojaid) ?? "—",
      })) as Linha[];
    },
  });
}

function Justificativas() {
  const [aba, setAba] = useState<"pendentes" | "nova" | "todas">("pendentes");
  const lista = useJustificativas();
  const pendentes = (lista.data ?? []).filter((j) => j.status === "Pendente");

  return (
    <Pagina titulo="Justificativas">
      <p className="text-sm text-muted-foreground">
        "Não se aplica": a tarefa caía no dia, mas não fazia sentido fazer. Aceita, ela sai das pendências, não conta nos
        pontos possíveis da nota do mês e vira dia neutro na sequência de dias (como a folga). Pendente ou recusada, conta
        normalmente.
      </p>

      <div className="flex flex-wrap gap-x-2 border-b border-border">
        {(
          [
            ["pendentes", `Para decidir${pendentes.length ? ` (${pendentes.length})` : ""}`],
            ["nova", "Nova justificativa"],
            ["todas", "Todas"],
          ] as const
        ).map(([id, rotulo]) => (
          <button
            key={id}
            onClick={() => setAba(id)}
            className={`whitespace-nowrap rounded-t-lg px-4 py-2 text-sm font-medium ${
              aba === id ? "bg-card text-foreground" : "text-muted-foreground"
            }`}
          >
            {rotulo}
          </button>
        ))}
      </div>

      {lista.isError && <p className="text-sm text-destructive">{(lista.error as Error).message}</p>}
      {aba === "pendentes" && <ParaDecidir linhas={pendentes} carregando={lista.isLoading} />}
      {aba === "nova" && <Nova />}
      {aba === "todas" && <Todas linhas={lista.data ?? []} carregando={lista.isLoading} />}
    </Pagina>
  );
}

function Cartao({ j, children }: { j: Linha; children?: React.ReactNode }) {
  return (
    <div className="space-y-2 rounded-lg border border-border bg-card px-4 py-3">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="font-medium">
          {j.tarefa}
          <span className={`ml-2 rounded-md border px-2 py-0.5 text-xs font-normal ${COR[j.status] ?? ""}`}>{j.status}</span>
        </p>
        <p className="text-sm text-muted-foreground">
          {j.pessoa} · {dia(j.dia)} · {j.loja}
        </p>
      </div>
      <p className="text-sm">“{j.motivo}”</p>
      {j.motivorecusa && <p className="text-xs text-destructive">Recusada: {j.motivorecusa}</p>}
      <p className="text-xs text-muted-foreground">{j.origem === "gestor" ? "Registrada pelo gestor" : "Enviada pelo bot"}</p>
      {children}
    </div>
  );
}

function ParaDecidir({ linhas, carregando }: { linhas: Linha[]; carregando: boolean }) {
  const qc = useQueryClient();
  const [aviso, setAviso] = useState<{ texto: string; grave: boolean } | null>(null);

  const decidir = useMutation({
    mutationFn: async (p: { id: number; aceitar: boolean; motivo?: string }) => {
      const { error } = await supabase.rpc("decidir_justificativa", {
        p_justificativaid: p.id,
        p_aceitar: p.aceitar,
        p_motivo: p.motivo,
      });
      if (error) throw error;
      return p.aceitar;
    },
    onSuccess: (aceitar) => {
      setAviso({ texto: aceitar ? "Justificativa aceita." : "Justificativa recusada.", grave: false });
      aposJustificar(qc);
    },
    onError: (e) => setAviso({ texto: (e as Error).message, grave: true }),
  });

  function recusar(id: number) {
    const motivo = window.prompt("Por que está recusando esta justificativa?");
    if (motivo === null) return;
    if (!motivo.trim()) {
      setAviso({ texto: "O motivo é obrigatório.", grave: true });
      return;
    }
    decidir.mutate({ id, aceitar: false, motivo: motivo.trim() });
  }

  return (
    <div className="space-y-2">
      {aviso && (
        <p className={`rounded-lg border bg-card px-4 py-3 text-sm ${aviso.grave ? "border-destructive text-destructive" : "border-border"}`}>
          {aviso.texto}
        </p>
      )}
      {carregando && <p className="text-muted-foreground">Carregando...</p>}
      {linhas.map((j) => (
        <Cartao key={j.justificativaid} j={j}>
          <div className="flex gap-2">
            <button
              onClick={() => decidir.mutate({ id: j.justificativaid, aceitar: true })}
              className="rounded-md bg-primary px-3 py-1 text-sm font-semibold text-primary-foreground"
            >
              Aceitar
            </button>
            <button
              onClick={() => recusar(j.justificativaid)}
              className="rounded-md border border-destructive px-3 py-1 text-sm text-destructive"
            >
              Recusar
            </button>
          </div>
        </Cartao>
      ))}
      {!carregando && linhas.length === 0 && (
        <p className="text-sm text-muted-foreground">Nenhuma justificativa esperando decisão.</p>
      )}
    </div>
  );
}

function Nova() {
  const h = hoje();
  const [funcionarioid, setFuncionarioid] = useState<number | "">("");
  const [data, setData] = useState(h);
  const [escolhida, setEscolhida] = useState<number | null>(null);
  const [recado, setRecado] = useState<string | null>(null);

  const pessoas = useQuery({
    queryKey: ["pessoas-justificativa"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("funcionarios")
        .select("funcionarioid, nomecompleto")
        .eq("ativo", true)
        .order("nomecompleto");
      if (error) throw error;
      return data ?? [];
    },
  });

  const tarefas = useQuery({
    queryKey: ["justificaveis", funcionarioid, data],
    enabled: funcionarioid !== "" && data !== "",
    queryFn: async () => {
      const { data: r, error } = await supabase.rpc("justificaveis", {
        p_funcionarioid: Number(funcionarioid),
        p_dia: data,
      });
      if (error) throw error;
      return (r ?? []) as unknown as { atribuicaoid: number; titulo: string; pontos: number; loja: string | null }[];
    },
  });

  return (
    <div className="space-y-4 rounded-xl border border-border bg-card p-4">
      <div className="flex flex-wrap items-center gap-3">
        <select
          value={funcionarioid}
          onChange={(e) => {
            setFuncionarioid(e.target.value === "" ? "" : Number(e.target.value));
            setEscolhida(null);
          }}
          className={`${campo} w-full sm:w-auto`}
        >
          <option value="">Escolha a pessoa...</option>
          {(pessoas.data ?? []).map((p) => (
            <option key={p.funcionarioid} value={p.funcionarioid}>
              {p.nomecompleto}
            </option>
          ))}
        </select>
        <label className="flex items-center gap-2 text-sm text-muted-foreground">
          Dia
          <input
            type="date"
            value={data}
            max={h}
            onChange={(e) => {
              setData(e.target.value);
              setEscolhida(null);
            }}
            className={campo}
          />
        </label>
      </div>

      {tarefas.isLoading && funcionarioid !== "" && <p className="text-muted-foreground">Carregando...</p>}
      {tarefas.isError && <p className="text-sm text-destructive">{(tarefas.error as Error).message}</p>}

      {funcionarioid !== "" && tarefas.data && (
        <div className="space-y-2">
          {tarefas.data.length === 0 ? (
            <p className="text-sm text-muted-foreground">
              Nada para justificar neste dia: as tarefas foram entregues ou já justificadas, ou era folga/afastamento.
            </p>
          ) : (
            <>
              <p className="text-sm text-muted-foreground">Qual tarefa não se aplica?</p>
              {tarefas.data.map((t) => (
                <label key={t.atribuicaoid} className="flex items-center gap-2 text-sm">
                  <input type="radio" checked={escolhida === t.atribuicaoid} onChange={() => setEscolhida(t.atribuicaoid)} />
                  {t.titulo} <span className="text-muted-foreground">· {t.pontos} pontos{t.loja ? ` · ${t.loja}` : ""}</span>
                </label>
              ))}
            </>
          )}
        </div>
      )}

      {escolhida !== null && (
        <Justificar
          atribuicaoid={escolhida}
          dia={data}
          aoTerminar={(texto) => {
            setRecado(texto);
            setEscolhida(null);
          }}
        />
      )}
      {recado && <p className="text-sm text-sucesso">{recado}</p>}
    </div>
  );
}

function Todas({ linhas, carregando }: { linhas: Linha[]; carregando: boolean }) {
  return (
    <div className="space-y-2">
      {carregando && <p className="text-muted-foreground">Carregando...</p>}
      {linhas.map((j) => (
        <Cartao key={j.justificativaid} j={j} />
      ))}
      {!carregando && linhas.length === 0 && <p className="text-sm text-muted-foreground">Nenhuma justificativa ainda.</p>}
    </div>
  );
}
