import { createFileRoute } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { TabelaResponsiva } from "@/ui/TabelaResponsiva";
import { AvisoSemLoja, useLojaAtiva } from "@/lojas/loja-ativa";

export const Route = createFileRoute("/_authenticated/metas")({
  component: Metas,
});

const campo =
  "rounded-lg border border-border bg-background px-3 py-2 text-sm placeholder:text-muted-foreground";

const reais = (v: number | null | undefined) =>
  v === null || v === undefined
    ? "—"
    : new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(Number(v));

const hoje = () => new Intl.DateTimeFormat("en-CA", { timeZone: "America/Sao_Paulo" }).format(new Date());
const dia = (iso: string) => `${iso.slice(8, 10)}/${iso.slice(5, 7)}/${iso.slice(0, 4)}`;
const numero = (t: string) => Number(t.replace(/\./g, "").replace(",", "."));
const DIAS_SEMANA = ["Domingo", "Segunda", "Terça", "Quarta", "Quinta", "Sexta", "Sábado"];

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

type DiaDoMes = {
  dia: string;
  apuracaoid: number | null;
  vendido: number | null;
  meta: number | null;
  pontos: number | null;
  origem: string | null;
  descricao: string | null;
  bateu: boolean;
  premiados: number;
};

type ResumoMes = {
  mes: { metaprincipalid: number; nomemeta: string; valormetatotal: number; pontospremio: number; premiado: boolean } | null;
  vendido: number;
  somametas: number;
  diaslancados: number;
  dias: DiaDoMes[];
  primeirodiaeditavel: string;
};

/** Tudo o que muda quando uma meta ou venda muda. */
function atualizarTudo(qc: ReturnType<typeof useQueryClient>) {
  for (const k of ["metas-mes", "metas-historico", "painel", "extrato", "pessoas-saldo", "metas-modelos", "metas-especiais"]) {
    qc.invalidateQueries({ queryKey: [k] });
  }
}

function useResumo(lojaid: number, mes: string) {
  return useQuery({
    queryKey: ["metas-mes", lojaid, mes],
    queryFn: async () => {
      const { data, error } = await supabase.rpc("metas_do_mes", { p_lojaid: lojaid, p_mes: `${mes}-01` });
      if (error) throw error;
      return data as unknown as ResumoMes;
    },
  });
}

function Metas() {
  const { lojas, lojaAtiva, loja, carregando } = useLojaAtiva();
  const [aba, setAba] = useState<"lancar" | "mes" | "semana" | "especiais" | "historico">("lancar");

  return (
    <div className="mx-auto max-w-5xl space-y-6">
      <h1 className="text-2xl font-bold tracking-tight sm:text-3xl">Metas {loja ? `· ${loja.nome}` : ""}</h1>
      {carregando ? (
        <p className="text-muted-foreground">Carregando...</p>
      ) : lojas.length === 0 || lojaAtiva === null ? (
        <AvisoSemLoja />
      ) : (
        <>
          <div className="flex flex-wrap gap-x-2 border-b border-border">
            {(
              [
                ["lancar", "Lançar venda"],
                ["mes", "Meta do mês"],
                ["semana", "Por dia da semana"],
                ["especiais", "Metas especiais"],
                ["historico", "Histórico"],
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
          {aba === "lancar" && <Lancar lojaid={lojaAtiva} />}
          {aba === "mes" && <MetaDoMes lojaid={lojaAtiva} />}
          {aba === "semana" && <PorDiaDaSemana lojaid={lojaAtiva} />}
          {aba === "especiais" && <Especiais lojaid={lojaAtiva} />}
          {aba === "historico" && <Historico lojaid={lojaAtiva} />}
        </>
      )}
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Lançar a venda do dia + o mês dia a dia                             */
/* ------------------------------------------------------------------ */

function Lancar({ lojaid }: { lojaid: number }) {
  const qc = useQueryClient();
  const h = hoje();
  const [data, setData] = useState(h);
  const [valor, setValor] = useState("");
  const [motivo, setMotivo] = useState("");
  const [recado, setRecado] = useState<string | null>(null);
  const resumo = useResumo(lojaid, data.slice(0, 7));
  const r = resumo.data;
  const doDia = r?.dias.find((d) => d.dia === data);
  const corrigindo = doDia?.apuracaoid != null;

  useEffect(() => {
    setValor(doDia?.vendido != null ? String(doDia.vendido).replace(".", ",") : "");
    setMotivo("");
  }, [data, doDia?.vendido]);

  const lancar = useMutation({
    mutationFn: async () => {
      const v = numero(valor);
      if (!(v >= 0) || valor.trim() === "") throw new Error("Informe o total vendido no dia.");
      if (corrigindo && !motivo.trim()) throw new Error("Este dia já tem lançamento. Informe o motivo da correção.");
      const { error } = await supabase.rpc("lancar_venda_do_dia", {
        p_lojaid: lojaid,
        p_dia: data,
        p_valor: v,
        p_motivo: motivo.trim() || undefined,
      });
      if (error) throw error;
      return v;
    },
    onSuccess: (v) => {
      setRecado(`${corrigindo ? "Correção salva" : "Venda lançada"}: ${reais(v)} em ${dia(data)}.`);
      atualizarTudo(qc);
    },
  });

  const percentual = (d: DiaDoMes) =>
    d.vendido != null && d.meta ? `${((d.vendido / d.meta) * 100).toLocaleString("pt-BR", { maximumFractionDigits: 1 })}%` : "—";

  const diasNoMes = r?.dias.length ?? 0;
  const projecao = r && r.diaslancados > 0 ? (r.vendido / r.diaslancados) * diasNoMes : null;

  return (
    <div className="space-y-6">
      <form
        onSubmit={(e) => {
          e.preventDefault();
          setRecado(null);
          lancar.mutate();
        }}
        className="space-y-3 rounded-xl border border-border bg-card p-4"
      >
        <p className="text-sm font-semibold">{corrigindo ? "Corrigir a venda do dia" : "Lançar a venda do dia"}</p>
        <div className="flex flex-wrap items-center gap-3">
          <label className="flex items-center gap-2 text-sm text-muted-foreground">
            Dia da venda
            <input
              type="date"
              value={data}
              max={h}
              min={r?.primeirodiaeditavel}
              onChange={(e) => {
                setData(e.target.value);
                setRecado(null);
              }}
              className={campo}
            />
          </label>
          <label className="flex items-center gap-2 text-sm text-muted-foreground">
            Total vendido (R$)
            <input
              inputMode="decimal"
              placeholder="0,00"
              value={valor}
              onChange={(e) => setValor(e.target.value)}
              className={`${campo} w-36`}
            />
          </label>
        </div>
        {doDia && (
          <p className="text-sm text-muted-foreground">
            Meta de {dia(data)}:{" "}
            <strong className="text-foreground">{doDia.meta ? reais(doDia.meta) : "sem meta"}</strong>
            {doDia.meta ? ` · ${doDia.pontos ?? 0} pontos para cada um da equipe` : ""}
            {doDia.origem === "especial" && ` · meta especial: ${doDia.descricao}`}
            {corrigindo && ` · já lançado: ${reais(doDia.vendido)}`}
          </p>
        )}
        {corrigindo && (
          <input
            required
            placeholder="Motivo da correção (obrigatório)"
            value={motivo}
            onChange={(e) => setMotivo(e.target.value)}
            className={`${campo} w-full`}
          />
        )}
        <button
          type="submit"
          disabled={lancar.isPending}
          className="rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground disabled:opacity-60"
        >
          {lancar.isPending ? "Salvando..." : corrigindo ? "Salvar correção" : "Lançar venda"}
        </button>
        <p className="text-xs text-muted-foreground">
          O valor é o total do dia (substitui o anterior). Batendo a meta, os pontos vão para quem está ligado à loja,
          ativo e não estava de folga nem afastado <strong>no dia da venda</strong>. Se uma correção fizer a meta deixar
          de bater, os pontos são estornados de quem recebeu; se voltar a bater, são pagos de novo. Só o mês atual e o
          anterior podem ser lançados ou corrigidos.
        </p>
        {recado && <p className="text-sm text-sucesso">{recado}</p>}
        {lancar.isError && <p className="text-sm text-destructive">{(lancar.error as Error).message}</p>}
      </form>

      {r && (
        <div className="grid gap-3 sm:grid-cols-3">
          <Cartao titulo="Vendido no mês" valor={reais(r.vendido)} />
          <Cartao
            titulo={r.mes ? `Meta do mês (${r.mes.nomemeta})` : "Meta do mês"}
            valor={r.mes ? `${((r.vendido / r.mes.valormetatotal) * 100).toLocaleString("pt-BR", { maximumFractionDigits: 1 })}% de ${reais(r.mes.valormetatotal)}` : "não cadastrada"}
            destaque={r.mes?.premiado ? "🎉 batida — prêmio pago" : undefined}
          />
          <Cartao titulo="Projeção do mês" valor={projecao ? reais(projecao) : "—"} />
        </div>
      )}

      {resumo.isLoading && <p className="text-muted-foreground">Carregando...</p>}
      {resumo.isError && <p className="text-sm text-destructive">{(resumo.error as Error).message}</p>}

      {r && (
        <TabelaResponsiva
          linhas={r.dias.filter((d) => d.dia <= h).reverse()}
          chave={(d) => d.dia}
          aoClicar={(d) => d.dia >= r.primeirodiaeditavel && setData(d.dia)}
          destacar={(d) => d.dia === data}
          vazio="Nenhum dia neste mês ainda."
          colunas={[
            {
              titulo: "Dia",
              principal: true,
              valor: (d) => (
                <>
                  {dia(d.dia)}{" "}
                  <span className="text-xs font-normal text-muted-foreground">
                    {DIAS_SEMANA[new Date(`${d.dia}T12:00:00Z`).getUTCDay()]}
                  </span>
                  {d.origem === "especial" && <span className="ml-1 text-xs text-accent">★ {d.descricao}</span>}
                </>
              ),
              classe: () => "whitespace-nowrap",
            },
            { titulo: "Meta", alinhar: "direita", valor: (d) => (d.meta ? reais(d.meta) : "—"), classe: () => "text-muted-foreground" },
            { titulo: "Vendido", alinhar: "direita", valor: (d) => (d.vendido != null ? reais(d.vendido) : "—") },
            { titulo: "%", alinhar: "direita", valor: (d) => percentual(d), classe: (d) => (d.bateu ? "font-semibold text-sucesso" : "") },
            {
              titulo: "Pontos",
              valor: (d) =>
                d.bateu && d.premiados > 0
                  ? `🎉 +${d.pontos} para ${d.premiados} ${d.premiados === 1 ? "pessoa" : "pessoas"}`
                  : d.vendido == null
                    ? "não lançado"
                    : "—",
              classe: () => "text-xs text-muted-foreground",
            },
          ]}
        />
      )}
    </div>
  );
}

function Cartao({ titulo, valor, destaque }: { titulo: string; valor: string; destaque?: string }) {
  return (
    <div className="rounded-xl border border-border bg-card p-4">
      <p className="text-xs text-muted-foreground">{titulo}</p>
      <p className="text-lg font-bold">{valor}</p>
      {destaque && <p className="text-xs text-sucesso">{destaque}</p>}
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Meta do mês                                                         */
/* ------------------------------------------------------------------ */

function MetaDoMes({ lojaid }: { lojaid: number }) {
  const qc = useQueryClient();
  const [mes, setMes] = useState(hoje().slice(0, 7));
  const resumo = useResumo(lojaid, mes);
  const r = resumo.data;
  const [form, setForm] = useState({ nome: "", valor: "", pontos: "0" });
  const [recado, setRecado] = useState<string | null>(null);

  useEffect(() => {
    setForm({
      nome: r?.mes?.nomemeta ?? "",
      valor: r?.mes ? String(r.mes.valormetatotal).replace(".", ",") : "",
      pontos: r?.mes ? String(r.mes.pontospremio) : "0",
    });
  }, [r?.mes?.metaprincipalid, r?.mes?.valormetatotal, r?.mes?.pontospremio, r?.mes?.nomemeta, mes]);

  const salvar = useMutation({
    mutationFn: async () => {
      const valor = numero(form.valor);
      const pontos = Number(form.pontos);
      if (!(valor > 0)) throw new Error("A meta do mês precisa ser maior que zero.");
      if (!Number.isInteger(pontos) || pontos < 0) throw new Error("Os pontos precisam ser um número inteiro, 0 ou mais.");
      const { error } = await supabase.rpc("salvar_meta_do_mes", {
        p_lojaid: lojaid,
        p_mes: `${mes}-01`,
        p_nome: form.nome,
        p_valor: valor,
        p_pontos: pontos,
      });
      if (error) throw error;
    },
    onSuccess: () => {
      setRecado("Meta do mês salva.");
      atualizarTudo(qc);
    },
  });

  const minimo = r?.primeirodiaeditavel?.slice(0, 7);

  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        setRecado(null);
        salvar.mutate();
      }}
      className="space-y-3 rounded-xl border border-border bg-card p-4"
    >
      <label className="flex items-center gap-2 text-sm text-muted-foreground">
        Mês
        <input type="month" value={mes} min={minimo} onChange={(e) => setMes(e.target.value)} className={campo} />
      </label>
      <div className="grid gap-3 sm:grid-cols-3">
        <input
          placeholder={`Nome (ex.: Meta de ${mes.slice(5, 7)}/${mes.slice(0, 4)})`}
          value={form.nome}
          onChange={(e) => setForm({ ...form, nome: e.target.value })}
          className={campo}
        />
        <label className="flex items-center gap-2 text-sm text-muted-foreground">
          R$
          <input
            required
            inputMode="decimal"
            placeholder="Valor da meta"
            value={form.valor}
            onChange={(e) => setForm({ ...form, valor: e.target.value })}
            className={`${campo} w-full`}
          />
        </label>
        <label className="flex items-center gap-2 text-sm text-muted-foreground">
          Prêmio
          <input
            type="number"
            min={0}
            value={form.pontos}
            onChange={(e) => setForm({ ...form, pontos: e.target.value })}
            className={`${campo} w-24`}
          />
          pontos
        </label>
      </div>
      {r && (
        <p className="text-sm text-muted-foreground">
          A soma das metas diárias deste mês dá <strong className="text-foreground">{reais(r.somametas)}</strong>
          {form.valor && numero(form.valor) > 0 && (
            <> · meta do mês: <strong className="text-foreground">{reais(numero(form.valor))}</strong></>
          )}
          . Vendido até agora: {reais(r.vendido)}.
        </p>
      )}
      <p className="text-xs text-muted-foreground">
        Batendo a meta do mês, cada pessoa ligada à loja e ativa naquele momento ganha os pontos do prêmio, uma vez só.
        Se uma correção fizer o mês deixar de bater, o prêmio é estornado. 0 pontos = meta sem prêmio.
      </p>
      <button
        type="submit"
        disabled={salvar.isPending}
        className="rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground disabled:opacity-60"
      >
        {r?.mes ? "Salvar alterações" : "Cadastrar meta do mês"}
      </button>
      {recado && <p className="text-sm text-sucesso">{recado}</p>}
      {salvar.isError && <p className="text-sm text-destructive">{(salvar.error as Error).message}</p>}
    </form>
  );
}

/* ------------------------------------------------------------------ */
/* Meta por dia da semana                                              */
/* ------------------------------------------------------------------ */

function PorDiaDaSemana({ lojaid }: { lojaid: number }) {
  const qc = useQueryClient();
  const [linhas, setLinhas] = useState(DIAS_SEMANA.map(() => ({ valor: "", pontos: "0" })));
  const [recado, setRecado] = useState<string | null>(null);

  const modelos = useQuery({
    queryKey: ["metas-modelos", lojaid],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("metasdiariasmodelos")
        .select("diasemanaid, valormeta, pontospremio")
        .eq("lojaid", lojaid);
      if (error) throw error;
      return data ?? [];
    },
  });

  useEffect(() => {
    if (!modelos.data) return;
    setLinhas(
      DIAS_SEMANA.map((_, i) => {
        const m = modelos.data.find((x) => x.diasemanaid === i + 1);
        return { valor: m ? String(m.valormeta).replace(".", ",") : "", pontos: m ? String(m.pontospremio) : "0" };
      }),
    );
  }, [modelos.data]);

  const salvar = useMutation({
    mutationFn: async () => {
      const dados = linhas.map((l, i) => {
        const valor = l.valor.trim() === "" ? 0 : numero(l.valor);
        const pontos = Number(l.pontos || 0);
        if (!(valor >= 0)) throw new Error(`Valor inválido em ${DIAS_SEMANA[i]}.`);
        if (!Number.isInteger(pontos) || pontos < 0) throw new Error(`Pontos inválidos em ${DIAS_SEMANA[i]}.`);
        return { lojaid, diasemanaid: i + 1, nomedia: DIAS_SEMANA[i], valormeta: valor, pontospremio: pontos };
      });
      const { error } = await supabase.from("metasdiariasmodelos").upsert(dados, { onConflict: "lojaid,diasemanaid" });
      if (error) throw error;
    },
    onSuccess: () => {
      setRecado("Metas por dia da semana salvas. Valem para os dias ainda não lançados.");
      atualizarTudo(qc);
    },
  });

  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        setRecado(null);
        salvar.mutate();
      }}
      className="space-y-3 rounded-xl border border-border bg-card p-4"
    >
      <p className="text-sm text-muted-foreground">
        A meta de cada dia da semana, em R$, e os pontos que cada pessoa da equipe ganha ao bater. Deixe em branco (ou 0)
        o dia sem meta. Uma meta especial para uma data substitui o valor do dia da semana.
      </p>
      <div className="space-y-2">
        {DIAS_SEMANA.map((nome, i) => (
          <div key={nome} className="grid grid-cols-[6rem_1fr_7rem] items-center gap-2 sm:grid-cols-[8rem_12rem_10rem]">
            <span className="text-sm font-medium">{nome}</span>
            <input
              inputMode="decimal"
              placeholder="R$ 0,00"
              value={linhas[i].valor}
              onChange={(e) => setLinhas(linhas.map((l, j) => (j === i ? { ...l, valor: e.target.value } : l)))}
              className={campo}
            />
            <label className="flex items-center gap-1 text-xs text-muted-foreground">
              <input
                type="number"
                min={0}
                value={linhas[i].pontos}
                onChange={(e) => setLinhas(linhas.map((l, j) => (j === i ? { ...l, pontos: e.target.value } : l)))}
                className={`${campo} w-16`}
              />
              pts
            </label>
          </div>
        ))}
      </div>
      <button
        type="submit"
        disabled={salvar.isPending}
        className="rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground disabled:opacity-60"
      >
        Salvar
      </button>
      <p className="text-xs text-muted-foreground">Mudar aqui não muda os dias já lançados: cada lançamento guarda a meta daquele dia.</p>
      {recado && <p className="text-sm text-sucesso">{recado}</p>}
      {salvar.isError && <p className="text-sm text-destructive">{(salvar.error as Error).message}</p>}
    </form>
  );
}

/* ------------------------------------------------------------------ */
/* Metas especiais (feriados, datas comemorativas)                     */
/* ------------------------------------------------------------------ */

function Especiais({ lojaid }: { lojaid: number }) {
  const qc = useQueryClient();
  const [form, setForm] = useState({ data: "", descricao: "", valor: "", pontos: "0" });

  const especiais = useQuery({
    queryKey: ["metas-especiais", lojaid],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("metasespeciais")
        .select("metaespecialid, data, descricao, valormeta, pontospremio")
        .eq("lojaid", lojaid)
        .order("data", { ascending: false })
        .limit(100);
      if (error) throw error;
      return data ?? [];
    },
  });

  const criar = useMutation({
    mutationFn: async () => {
      const valor = numero(form.valor);
      const pontos = Number(form.pontos || 0);
      if (!form.data) throw new Error("Escolha a data.");
      if (!form.descricao.trim()) throw new Error("Dê um nome (ex.: Dia das Mães).");
      if (!(valor >= 0)) throw new Error("Valor inválido.");
      if (!Number.isInteger(pontos) || pontos < 0) throw new Error("Pontos inválidos.");
      const { error } = await supabase.from("metasespeciais").insert({
        lojaid,
        data: form.data,
        descricao: form.descricao.trim(),
        valormeta: valor,
        pontospremio: pontos,
      });
      if (error) {
        if (error.code === "23505") throw new Error("Já existe uma meta especial nesta data.");
        throw error;
      }
    },
    onSuccess: () => {
      setForm({ data: "", descricao: "", valor: "", pontos: "0" });
      atualizarTudo(qc);
    },
  });

  const apagar = useMutation({
    mutationFn: async (id: number) => {
      const { error } = await supabase.from("metasespeciais").delete().eq("metaespecialid", id);
      if (error) throw error;
    },
    onSuccess: () => atualizarTudo(qc),
  });

  return (
    <div className="space-y-4">
      <form
        onSubmit={(e) => {
          e.preventDefault();
          criar.mutate();
        }}
        className="space-y-3 rounded-xl border border-border bg-card p-4"
      >
        <p className="text-sm font-semibold">Nova meta especial</p>
        <div className="grid gap-3 sm:grid-cols-4">
          <input type="date" required value={form.data} onChange={(e) => setForm({ ...form, data: e.target.value })} className={campo} />
          <input
            required
            placeholder="Nome (ex.: Dia das Mães)"
            maxLength={100}
            value={form.descricao}
            onChange={(e) => setForm({ ...form, descricao: e.target.value })}
            className={campo}
          />
          <input
            required
            inputMode="decimal"
            placeholder="Meta em R$"
            value={form.valor}
            onChange={(e) => setForm({ ...form, valor: e.target.value })}
            className={campo}
          />
          <label className="flex items-center gap-1 text-sm text-muted-foreground">
            <input
              type="number"
              min={0}
              value={form.pontos}
              onChange={(e) => setForm({ ...form, pontos: e.target.value })}
              className={`${campo} w-20`}
            />
            pontos
          </label>
        </div>
        <p className="text-xs text-muted-foreground">
          Naquela data, esta meta substitui a do dia da semana. Se o dia já foi lançado, ele continua com a meta que
          tinha.
        </p>
        <button
          type="submit"
          disabled={criar.isPending}
          className="rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground disabled:opacity-60"
        >
          Adicionar
        </button>
        {criar.isError && <p className="text-sm text-destructive">{(criar.error as Error).message}</p>}
      </form>

      <div className="space-y-2">
        {(especiais.data ?? []).map((m) => (
          <div
            key={m.metaespecialid}
            className="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-border bg-card px-4 py-3"
          >
            <p>
              <strong>{dia(m.data)}</strong> · {m.descricao}
              <span className="ml-2 text-sm text-muted-foreground">
                {reais(m.valormeta)} · {m.pontospremio} pontos
              </span>
            </p>
            <button
              onClick={() => window.confirm(`Apagar a meta especial de ${dia(m.data)}?`) && apagar.mutate(m.metaespecialid)}
              className="rounded-md border border-border px-3 py-1 text-sm"
            >
              Apagar
            </button>
          </div>
        ))}
        {!especiais.isLoading && (especiais.data ?? []).length === 0 && (
          <p className="text-sm text-muted-foreground">Nenhuma meta especial cadastrada.</p>
        )}
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Histórico de lançamentos e correções                                */
/* ------------------------------------------------------------------ */

function Historico({ lojaid }: { lojaid: number }) {
  const eu = useQuery({
    queryKey: ["meu-uid"],
    queryFn: async () => (await supabase.auth.getUser()).data.user?.id ?? null,
  });
  const historico = useQuery({
    queryKey: ["metas-historico", lojaid],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("metashistorico")
        .select("historicoid, dataapuracao, valoranterior, valornovo, motivo, alteradopor, alteradoem")
        .eq("lojaid", lojaid)
        .order("alteradoem", { ascending: false })
        .limit(200);
      if (error) throw error;
      return data ?? [];
    },
  });

  return (
    <TabelaResponsiva
      linhas={historico.data ?? []}
      chave={(h) => h.historicoid}
      vazio={historico.isLoading ? "Carregando..." : "Nenhum lançamento ainda."}
      colunas={[
        { titulo: "Quando", valor: (h) => dataHora(h.alteradoem), classe: () => "whitespace-nowrap text-muted-foreground" },
        { titulo: "Dia da venda", principal: true, valor: (h) => `Venda de ${dia(h.dataapuracao)}`, classe: () => "whitespace-nowrap" },
        {
          titulo: "De",
          alinhar: "direita",
          valor: (h) => (h.valoranterior === null ? "lançamento" : reais(h.valoranterior)),
          classe: () => "text-muted-foreground",
        },
        { titulo: "Para", alinhar: "direita", valor: (h) => reais(h.valornovo), classe: () => "font-medium" },
        { titulo: "Motivo", valor: (h) => h.motivo ?? "—", classe: () => "text-muted-foreground" },
        {
          titulo: "Quem",
          valor: (h) => (h.alteradopor && h.alteradopor === eu.data ? "Você" : h.alteradopor ? "Outro usuário" : "—"),
          classe: () => "text-muted-foreground",
        },
      ]}
    />
  );
}
