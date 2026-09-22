import { createFileRoute } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { AvisoSemLoja, useLojaAtiva } from "@/lojas/loja-ativa";

export const Route = createFileRoute("/_authenticated/solicitacoes")({
  component: Solicitacoes,
});

const campo =
  "rounded-lg border border-border bg-background px-3 py-2 text-sm placeholder:text-muted-foreground";

const CATEGORIAS: Record<string, string[]> = {
  Compra: ["Limpeza", "Escritório", "Cozinha", "Outros"],
  Manutencao: ["Predial", "Equipamento", "Outros"],
};

const SITUACOES = ["Aberta", "Em andamento", "Concluída", "Recusada"] as const;

const COR: Record<string, string> = {
  Aberta: "border-accent text-accent",
  "Em andamento": "border-primary text-primary",
  Concluída: "border-border text-muted-foreground",
  Recusada: "border-destructive text-destructive",
};

function dataHora(iso: string) {
  return new Date(iso).toLocaleString("pt-BR", {
    timeZone: "America/Sao_Paulo",
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

function Solicitacoes() {
  const { lojas, lojaAtiva, loja, carregando } = useLojaAtiva();

  return (
    <div className="mx-auto max-w-5xl space-y-6">
      <h1 className="text-2xl font-bold tracking-tight sm:text-3xl">Solicitações</h1>
      {carregando ? (
        <p className="text-muted-foreground">Carregando...</p>
      ) : lojas.length === 0 || lojaAtiva === null ? (
        <AvisoSemLoja />
      ) : (
        <>
          <p className="text-sm text-muted-foreground">
            Pedidos de compra e de manutenção da loja <strong>{loja?.nome}</strong>. Por enquanto o gestor registra; com o bot,
            os líderes pedem direto (e a foto da manutenção vem junto).
          </p>
          <Abrir lojaid={lojaAtiva} />
          <Lista lojaid={lojaAtiva} />
        </>
      )}
    </div>
  );
}

function Abrir({ lojaid }: { lojaid: number }) {
  const qc = useQueryClient();
  const [tipo, setTipo] = useState<"Compra" | "Manutencao">("Compra");
  const [categoria, setCategoria] = useState("Limpeza");
  const [funcionarioid, setFuncionarioid] = useState<number | "">("");
  const [descricao, setDescricao] = useState("");
  const [quantidade, setQuantidade] = useState("");
  const [unidade, setUnidade] = useState("");
  const [recado, setRecado] = useState<string | null>(null);

  const pessoas = useQuery({
    queryKey: ["pessoas-da-loja-solicitacao", lojaid],
    queryFn: async () => {
      const [{ data: vinculos, error }, { data: gente }] = await Promise.all([
        supabase.from("funcionarioslojas").select("funcionarioid").eq("lojaid", lojaid).eq("ativo", true),
        supabase.from("funcionarios").select("funcionarioid, nomecompleto, ativo"),
      ]);
      if (error) throw error;
      const daLoja = new Set((vinculos ?? []).map((v) => v.funcionarioid));
      return (gente ?? [])
        .filter((p) => p.ativo && daLoja.has(p.funcionarioid))
        .map((p) => ({ funcionarioid: p.funcionarioid, nome: p.nomecompleto }))
        .sort((a, b) => a.nome.localeCompare(b.nome));
    },
  });

  const abrir = useMutation({
    mutationFn: async () => {
      if (funcionarioid === "") throw new Error("Escolha quem pediu.");
      const qtd = quantidade.trim() === "" ? null : Number(quantidade.replace(",", "."));
      if (qtd !== null && !(qtd > 0)) throw new Error("A quantidade precisa ser maior que zero.");
      const { error } = await supabase.rpc("abrir_solicitacao", {
        p_lojaid: lojaid,
        p_funcionarioid: funcionarioid,
        p_tipo: tipo,
        p_categoria: categoria,
        p_descricao: descricao,
        p_quantidade: tipo === "Compra" && qtd !== null ? qtd : undefined,
        p_unidade: tipo === "Compra" ? unidade : undefined,
      });
      if (error) throw error;
    },
    onSuccess: () => {
      setRecado("Solicitação aberta.");
      setDescricao("");
      setQuantidade("");
      setUnidade("");
      qc.invalidateQueries({ queryKey: ["solicitacoes", lojaid] });
    },
  });

  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        setRecado(null);
        abrir.mutate();
      }}
      className="space-y-3 rounded-xl border border-border bg-card p-4"
    >
      <p className="text-sm font-semibold">Nova solicitação</p>
      <div className="flex flex-wrap gap-4 text-sm">
        {(["Compra", "Manutencao"] as const).map((t) => (
          <label key={t} className="flex items-center gap-2">
            <input
              type="radio"
              checked={tipo === t}
              onChange={() => {
                setTipo(t);
                setCategoria(CATEGORIAS[t][0]);
              }}
            />
            {t === "Compra" ? "🛒 Compra" : "🔧 Manutenção"}
          </label>
        ))}
      </div>
      <div className="grid gap-3 sm:grid-cols-2">
        <select
          required
          value={funcionarioid}
          onChange={(e) => setFuncionarioid(e.target.value === "" ? "" : Number(e.target.value))}
          className={campo}
        >
          <option value="">Quem pediu...</option>
          {(pessoas.data ?? []).map((p) => (
            <option key={p.funcionarioid} value={p.funcionarioid}>
              {p.nome}
            </option>
          ))}
        </select>
        <select value={categoria} onChange={(e) => setCategoria(e.target.value)} className={campo}>
          {CATEGORIAS[tipo].map((c) => (
            <option key={c}>{c}</option>
          ))}
        </select>
        <input
          required
          placeholder={tipo === "Compra" ? "Item (ex.: Detergente)" : "O que precisa de conserto (ex.: pia vazando)"}
          value={descricao}
          onChange={(e) => setDescricao(e.target.value)}
          className={`${campo} sm:col-span-2`}
        />
        {tipo === "Compra" && (
          <div className="flex gap-2 sm:col-span-2">
            <input
              inputMode="decimal"
              placeholder="Quantidade"
              value={quantidade}
              onChange={(e) => setQuantidade(e.target.value)}
              className={`${campo} w-32`}
            />
            <input
              placeholder="Unidade (ex.: litros, caixas)"
              maxLength={20}
              value={unidade}
              onChange={(e) => setUnidade(e.target.value)}
              className={`${campo} flex-1`}
            />
          </div>
        )}
      </div>
      <button
        type="submit"
        disabled={abrir.isPending}
        className="rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground disabled:opacity-60"
      >
        {abrir.isPending ? "Abrindo..." : "Abrir solicitação"}
      </button>
      {recado && <p className="text-sm text-sucesso">{recado}</p>}
      {abrir.isError && <p className="text-sm text-destructive">{(abrir.error as Error).message}</p>}
    </form>
  );
}

type Solicitacao = {
  solicitacaoid: number;
  tipo: string;
  categoria: string | null;
  descricao: string | null;
  quantidade: number | null;
  unidade: string | null;
  status: string;
  motivorecusa: string | null;
  datasolicitacao: string;
  funcionarioid: number | null;
};

type Mudanca = {
  historicoid: number;
  solicitacaoid: number;
  statusanterior: string | null;
  statusnovo: string;
  observacao: string | null;
  alteradoem: string;
};

function Lista({ lojaid }: { lojaid: number }) {
  const qc = useQueryClient();
  const [filtro, setFiltro] = useState<"abertas" | (typeof SITUACOES)[number] | "todas">("abertas");
  const [aberta, setAberta] = useState<number | null>(null);
  const [aviso, setAviso] = useState<{ texto: string; grave: boolean } | null>(null);

  const dados = useQuery({
    queryKey: ["solicitacoes", lojaid],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("solicitacoesinternas")
        .select("solicitacaoid, tipo, categoria, descricao, quantidade, unidade, status, motivorecusa, datasolicitacao, funcionarioid")
        .eq("lojaid", lojaid)
        .order("datasolicitacao", { ascending: false })
        .limit(300);
      if (error) throw error;
      const [{ data: pessoas }, { data: historico }] = await Promise.all([
        supabase.from("funcionarios").select("funcionarioid, nomecompleto"),
        supabase
          .from("solicitacoeshistorico")
          .select("historicoid, solicitacaoid, statusanterior, statusnovo, observacao, alteradoem")
          .eq("lojaid", lojaid)
          .order("historicoid"),
      ]);
      return {
        lista: (data ?? []) as Solicitacao[],
        nome: new Map((pessoas ?? []).map((p) => [p.funcionarioid, p.nomecompleto])),
        historico: (historico ?? []) as Mudanca[],
      };
    },
  });

  const mudar = useMutation({
    mutationFn: async (p: { id: number; status: string; observacao?: string }) => {
      const { error } = await supabase.rpc("mudar_situacao_solicitacao", {
        p_solicitacaoid: p.id,
        p_status: p.status,
        p_observacao: p.observacao,
      });
      if (error) throw error;
      return p.status;
    },
    onSuccess: (status) => {
      setAviso({ texto: `Situação: ${status}.`, grave: false });
      qc.invalidateQueries({ queryKey: ["solicitacoes", lojaid] });
    },
    onError: (e) => setAviso({ texto: (e as Error).message, grave: true }),
  });

  function comTexto(id: number, status: string) {
    const recusa = status === "Recusada";
    const texto = window.prompt(recusa ? "Por que está recusando?" : "Observação (opcional):");
    if (texto === null) return;
    if (recusa && !texto.trim()) {
      setAviso({ texto: "Para recusar, informe o motivo.", grave: true });
      return;
    }
    mudar.mutate({ id, status, observacao: texto.trim() || undefined });
  }

  const lista = (dados.data?.lista ?? []).filter((s) =>
    filtro === "todas" ? true : filtro === "abertas" ? ["Aberta", "Em andamento"].includes(s.status) : s.status === filtro,
  );

  return (
    <section className="space-y-3">
      <div className="flex flex-wrap gap-1">
        {(["abertas", ...SITUACOES, "todas"] as const).map((f) => (
          <button
            key={f}
            onClick={() => setFiltro(f)}
            className={`rounded-lg px-3 py-1.5 text-sm ${filtro === f ? "bg-card font-semibold" : "text-muted-foreground"}`}
          >
            {f === "abertas" ? "A resolver" : f === "todas" ? "Todas" : f}
          </button>
        ))}
      </div>

      {aviso && (
        <p className={`rounded-lg border bg-card px-4 py-3 text-sm ${aviso.grave ? "border-destructive text-destructive" : "border-border"}`}>
          {aviso.texto}
        </p>
      )}
      {dados.isLoading && <p className="text-muted-foreground">Carregando...</p>}
      {dados.isError && <p className="text-sm text-destructive">{(dados.error as Error).message}</p>}

      {lista.map((s) => {
        const mudancas = (dados.data?.historico ?? []).filter((h) => h.solicitacaoid === s.solicitacaoid);
        return (
          <div key={s.solicitacaoid} className="space-y-2 rounded-lg border border-border bg-card px-4 py-3">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <p className="font-medium">
                {s.tipo === "Compra" ? "🛒" : "🔧"} {s.descricao}
                {s.quantidade !== null && ` — ${Number(s.quantidade).toLocaleString("pt-BR")} ${s.unidade ?? ""}`}
                <span className={`ml-2 rounded-md border px-2 py-0.5 text-xs font-normal ${COR[s.status] ?? ""}`}>{s.status}</span>
              </p>
              <p className="text-sm text-muted-foreground">
                {s.categoria && `${s.categoria} · `}
                {s.funcionarioid ? dados.data?.nome.get(s.funcionarioid) : "—"} · {dataHora(s.datasolicitacao)}
              </p>
            </div>
            {s.motivorecusa && <p className="text-xs text-destructive">Recusada: {s.motivorecusa}</p>}
            <div className="flex flex-wrap gap-2">
              {s.status === "Aberta" && (
                <button onClick={() => comTexto(s.solicitacaoid, "Em andamento")} className="rounded-md border border-border px-3 py-1 text-sm">
                  Começar
                </button>
              )}
              {["Aberta", "Em andamento"].includes(s.status) && (
                <>
                  <button
                    onClick={() => comTexto(s.solicitacaoid, "Concluída")}
                    className="rounded-md bg-primary px-3 py-1 text-sm font-semibold text-primary-foreground"
                  >
                    Concluir
                  </button>
                  <button
                    onClick={() => comTexto(s.solicitacaoid, "Recusada")}
                    className="rounded-md border border-destructive px-3 py-1 text-sm text-destructive"
                  >
                    Recusar
                  </button>
                </>
              )}
              <button
                onClick={() => setAberta(aberta === s.solicitacaoid ? null : s.solicitacaoid)}
                className="rounded-md px-3 py-1 text-sm text-muted-foreground underline"
              >
                {aberta === s.solicitacaoid ? "Esconder histórico" : "Histórico"}
              </button>
            </div>
            {aberta === s.solicitacaoid && (
              <ol className="space-y-1 border-l border-border pl-3 text-xs text-muted-foreground">
                {mudancas.map((m) => (
                  <li key={m.historicoid}>
                    {dataHora(m.alteradoem)} · {m.statusanterior ? `${m.statusanterior} → ` : "Aberta por "}
                    {m.statusanterior ? m.statusnovo : "gestor"}
                    {m.observacao && ` · “${m.observacao}”`}
                  </li>
                ))}
              </ol>
            )}
          </div>
        );
      })}
      {!dados.isLoading && lista.length === 0 && <p className="text-sm text-muted-foreground">Nenhuma solicitação aqui.</p>}
    </section>
  );
}
