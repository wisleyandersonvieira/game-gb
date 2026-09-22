import { createFileRoute } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { AvisoSemLoja, useLojaAtiva } from "@/lojas/loja-ativa";
import { validarArquivo } from "@/rh/arquivos";

export const Route = createFileRoute("/_authenticated/agenda")({
  component: Agenda,
});

const campo =
  "rounded-lg border border-border bg-background px-3 py-2 text-sm placeholder:text-muted-foreground";

const FUSO = "America/Sao_Paulo";
const PAGAMENTOS = ["Pendente", "Sinal pago", "Pago"] as const;

const reais = (v: number | null) =>
  v === null ? "" : new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(Number(v));
const hoje = () => new Intl.DateTimeFormat("en-CA", { timeZone: FUSO }).format(new Date());
const numero = (t: string) => Number(t.replace(/\./g, "").replace(",", "."));

/** Data e hora digitadas (horário de Brasília) → instante. */
const instante = (data: string, hora: string) => `${data}T${hora}:00-03:00`;

function quando(iso: string) {
  return new Date(iso).toLocaleString("pt-BR", {
    timeZone: FUSO,
    weekday: "short",
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}
function dataHora(iso: string) {
  return new Date(iso).toLocaleString("pt-BR", {
    timeZone: FUSO,
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}
const partes = (iso: string) => {
  const d = new Date(iso);
  return {
    data: new Intl.DateTimeFormat("en-CA", { timeZone: FUSO }).format(d),
    hora: d.toLocaleTimeString("pt-BR", { timeZone: FUSO, hour: "2-digit", minute: "2-digit" }),
  };
};
const cpfMascarado = (cpf: string | null) => (cpf ? `***.***.${cpf.slice(6, 9)}-${cpf.slice(9)}` : "");
const cpfCompleto = (cpf: string | null) =>
  cpf ? `${cpf.slice(0, 3)}.${cpf.slice(3, 6)}.${cpf.slice(6, 9)}-${cpf.slice(9)}` : "";
const telefone = (t: string | null) => {
  if (!t) return "";
  const d = t.length > 11 ? t.slice(-11) : t;
  return d.length === 11 ? `(${d.slice(0, 2)}) ${d.slice(2, 7)}-${d.slice(7)}` : `(${d.slice(0, 2)}) ${d.slice(2, 6)}-${d.slice(6)}`;
};

type Agendamento = {
  agendamentoid: number;
  contaid: number;
  lojaid: number;
  nomecliente: string;
  cpfcliente: string | null;
  telefonecliente: string | null;
  tipoevento: string;
  tipoeventoid: number | null;
  dataevento: string;
  statusagendamento: string;
  statuspagamento: string;
  valor: number | null;
  funcionarioid: number;
  observacoes: string | null;
  aceitawhatsapp: boolean;
  motivocancelamento: string | null;
};

const COR: Record<string, string> = {
  Confirmado: "border-primary text-primary",
  Realizado: "border-border text-muted-foreground",
  Cancelado: "border-perigo/40 bg-perigo-soft text-perigo",
};

function atualizarTudo(qc: ReturnType<typeof useQueryClient>) {
  for (const k of ["agenda", "agenda-historico", "agenda-anexos", "painel", "para-entregar", "quadro"]) {
    qc.invalidateQueries({ queryKey: [k] });
  }
}

function useTipos() {
  return useQuery({
    queryKey: ["tipos-evento"],
    queryFn: async () => {
      const { data, error } = await supabase.from("tiposevento").select("tipoeventoid, nome, ativo").order("nome");
      if (error) throw error;
      return data ?? [];
    },
  });
}

function usePessoasDaLoja(lojaid: number) {
  return useQuery({
    queryKey: ["pessoas-da-loja-agenda", lojaid],
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
}

function Agenda() {
  const { lojas, lojaAtiva, loja, carregando } = useLojaAtiva();
  const [aba, setAba] = useState<"lista" | "novo" | "tipos">("lista");

  return (
    <div className="mx-auto max-w-5xl space-y-6">
      <h1 className="font-display text-2xl font-semibold tracking-tight sm:text-3xl">Agenda {loja ? `· ${loja.nome}` : ""}</h1>
      {carregando ? (
        <p className="text-muted-foreground">Carregando...</p>
      ) : lojas.length === 0 || lojaAtiva === null ? (
        <AvisoSemLoja />
      ) : (
        <>
          <div className="flex flex-wrap gap-x-2 border-b border-border">
            {(
              [
                ["lista", "Agendamentos"],
                ["novo", "Novo agendamento"],
                ["tipos", "Tipos de evento"],
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
          {aba === "lista" && <Lista lojaid={lojaAtiva} />}
          {aba === "novo" && (
            <Novo
              lojaid={lojaAtiva}
              responsavelPadrao={loja?.responsavelagendamentosid ?? null}
              aoCriar={() => setAba("lista")}
            />
          )}
          {aba === "tipos" && <Tipos />}
        </>
      )}
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Novo agendamento                                                    */
/* ------------------------------------------------------------------ */

const VAZIO = {
  tipo: "" as number | "",
  data: "",
  hora: "14:00",
  nome: "",
  cpf: "",
  telefone: "",
  observacoes: "",
  valor: "",
  pagamento: "Pendente",
  responsavel: "" as number | "",
  whatsapp: false,
};

function Novo({
  lojaid,
  responsavelPadrao,
  aoCriar,
}: {
  lojaid: number;
  responsavelPadrao: number | null;
  aoCriar: () => void;
}) {
  const qc = useQueryClient();
  const tipos = useTipos();
  const pessoas = usePessoasDaLoja(lojaid);
  const [f, setF] = useState({ ...VAZIO, data: hoje(), responsavel: (responsavelPadrao ?? "") as number | "" });

  const criar = useMutation({
    mutationFn: async () => {
      if (f.tipo === "") throw new Error("Escolha o tipo de evento.");
      if (!f.data || !f.hora) throw new Error("Informe a data e a hora.");
      if (f.responsavel === "") throw new Error("Escolha o responsável.");
      const inicio = instante(f.data, f.hora);
      const { data: perto } = await supabase.rpc("conflitos_agendamento", { p_lojaid: lojaid, p_dataevento: inicio });
      const lista = (perto ?? []) as unknown as { quando: string; tipo: string }[];
      if (lista.length > 0) {
        const texto = lista.map((c) => `${partes(c.quando).hora} — ${c.tipo}`).join(", ");
        if (!window.confirm(`Já existe agendamento perto desse horário (${texto}). Agendar mesmo assim?`)) {
          throw new Error("Agendamento não criado.");
        }
      }
      const { error } = await supabase.rpc("criar_agendamento", {
        p_lojaid: lojaid,
        p_tipoeventoid: f.tipo,
        p_dataevento: inicio,
        p_nomecliente: f.nome,
        p_cpf: f.cpf || undefined,
        p_telefone: f.telefone || undefined,
        p_observacoes: f.observacoes || undefined,
        p_valor: f.valor.trim() ? numero(f.valor) : undefined,
        p_pagamento: f.pagamento,
        p_responsavelid: f.responsavel,
        p_aceitawhatsapp: f.whatsapp,
      });
      if (error) throw error;
    },
    onSuccess: () => {
      setF({ ...VAZIO, data: hoje(), responsavel: (responsavelPadrao ?? "") as number | "" });
      atualizarTudo(qc);
      aoCriar();
    },
  });

  const tiposAtivos = (tipos.data ?? []).filter((t) => t.ativo);

  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        criar.mutate();
      }}
      className="space-y-3 rounded-xl border border-border bg-card p-4"
    >
      <div className="grid gap-3 sm:grid-cols-3">
        <select
          required
          value={f.tipo}
          onChange={(e) => setF({ ...f, tipo: e.target.value === "" ? "" : Number(e.target.value) })}
          className={campo}
        >
          <option value="">Tipo de evento...</option>
          {tiposAtivos.map((t) => (
            <option key={t.tipoeventoid} value={t.tipoeventoid}>
              {t.nome}
            </option>
          ))}
        </select>
        <input type="date" required min={hoje()} value={f.data} onChange={(e) => setF({ ...f, data: e.target.value })} className={campo} />
        <input type="time" required value={f.hora} onChange={(e) => setF({ ...f, hora: e.target.value })} className={campo} />
        <input
          required
          placeholder="Nome do cliente"
          value={f.nome}
          onChange={(e) => setF({ ...f, nome: e.target.value })}
          className={`${campo} sm:col-span-3`}
        />
        <input
          placeholder="CPF (opcional)"
          inputMode="numeric"
          value={f.cpf}
          onChange={(e) => setF({ ...f, cpf: e.target.value })}
          className={campo}
        />
        <input
          placeholder="Telefone com DDD (opcional)"
          inputMode="tel"
          value={f.telefone}
          onChange={(e) => setF({ ...f, telefone: e.target.value })}
          className={campo}
        />
        <label className="flex items-center gap-2 text-sm text-muted-foreground">
          <input type="checkbox" checked={f.whatsapp} onChange={(e) => setF({ ...f, whatsapp: e.target.checked })} />
          Aceita receber WhatsApp
        </label>
        <select value={f.pagamento} onChange={(e) => setF({ ...f, pagamento: e.target.value })} className={campo}>
          {PAGAMENTOS.map((p) => (
            <option key={p}>{p}</option>
          ))}
        </select>
        <input
          placeholder="Valor combinado R$ (opcional)"
          inputMode="decimal"
          value={f.valor}
          onChange={(e) => setF({ ...f, valor: e.target.value })}
          className={campo}
        />
        <select
          required
          value={f.responsavel}
          onChange={(e) => setF({ ...f, responsavel: e.target.value === "" ? "" : Number(e.target.value) })}
          className={campo}
        >
          <option value="">Responsável...</option>
          {(pessoas.data ?? []).map((p) => (
            <option key={p.funcionarioid} value={p.funcionarioid}>
              {p.nome}
              {p.funcionarioid === responsavelPadrao ? " (responsável da loja)" : ""}
            </option>
          ))}
        </select>
        <textarea
          rows={2}
          placeholder="Observações (opcional)"
          value={f.observacoes}
          onChange={(e) => setF({ ...f, observacoes: e.target.value })}
          className={`${campo} sm:col-span-3`}
        />
      </div>
      <p className="text-xs text-muted-foreground">
        O responsável recebe a tarefa "Atender agendamento" no dia do evento. Os dados do cliente ficam só aqui: a TV
        mostra apenas a hora e o tipo. Mensagens por WhatsApp começam com o bot (Etapa 1.13).
      </p>
      <button
        type="submit"
        disabled={criar.isPending}
        className="rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground disabled:opacity-60"
      >
        {criar.isPending ? "Salvando..." : "Agendar"}
      </button>
      {criar.isError && <p className="text-sm text-destructive">{(criar.error as Error).message}</p>}
    </form>
  );
}

/* ------------------------------------------------------------------ */
/* Lista de agendamentos                                               */
/* ------------------------------------------------------------------ */

function Lista({ lojaid }: { lojaid: number }) {
  const [filtro, setFiltro] = useState<"proximos" | "realizados" | "cancelados" | "todos">("proximos");
  const [aberto, setAberto] = useState<number | null>(null);
  const [vista, setVista] = useState<"lista" | "mes">("lista");
  const [mes, setMes] = useState(hoje().slice(0, 7));
  const [diaEscolhido, setDiaEscolhido] = useState<string | null>(null);
  const pessoas = usePessoasDaLoja(lojaid);

  const agenda = useQuery({
    queryKey: ["agenda", lojaid],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("agendamentos")
        .select(
          "agendamentoid, contaid, lojaid, nomecliente, cpfcliente, telefonecliente, tipoevento, tipoeventoid, dataevento, statusagendamento, statuspagamento, valor, funcionarioid, observacoes, aceitawhatsapp, motivocancelamento",
        )
        .eq("lojaid", lojaid)
        .order("dataevento")
        .limit(500);
      if (error) throw error;
      return (data ?? []) as Agendamento[];
    },
  });

  const nomes = useQuery({
    queryKey: ["nomes-funcionarios"],
    queryFn: async () => {
      const { data, error } = await supabase.from("funcionarios").select("funcionarioid, nomecompleto");
      if (error) throw error;
      return new Map((data ?? []).map((p) => [p.funcionarioid, p.nomecompleto]));
    },
  });

  const inicioDeHoje = `${hoje()}T00:00:00-03:00`;
  const lista = (agenda.data ?? []).filter((a) =>
    vista === "mes"
      ? diaEscolhido !== null && partes(a.dataevento).data === diaEscolhido
      : filtro === "proximos"
      ? a.statusagendamento === "Confirmado" && new Date(a.dataevento) >= new Date(inicioDeHoje)
      : filtro === "realizados"
        ? a.statusagendamento === "Realizado"
        : filtro === "cancelados"
          ? a.statusagendamento === "Cancelado"
          : true,
  );
  const atrasados = (agenda.data ?? []).filter(
    (a) => a.statusagendamento === "Confirmado" && new Date(a.dataevento) < new Date(inicioDeHoje),
  );

  return (
    <section className="space-y-3">
      <div className="flex w-fit gap-1 rounded-lg border border-border p-1">
        {(
          [
            ["lista", "Lista"],
            ["mes", "Calendário do mês"],
          ] as const
        ).map(([id, rotulo]) => (
          <button
            key={id}
            onClick={() => setVista(id)}
            className={`rounded-md px-3 py-1 text-sm ${vista === id ? "bg-card font-semibold" : "text-muted-foreground"}`}
          >
            {rotulo}
          </button>
        ))}
      </div>

      {vista === "mes" && (
        <Calendario
          mes={mes}
          setMes={(m) => {
            setMes(m);
            setDiaEscolhido(null);
          }}
          agenda={agenda.data ?? []}
          diaEscolhido={diaEscolhido}
          escolher={setDiaEscolhido}
        />
      )}

      <div className={`flex flex-wrap gap-1 ${vista === "mes" ? "hidden" : ""}`}>
        {(
          [
            ["proximos", "Próximos"],
            ["realizados", "Realizados"],
            ["cancelados", "Cancelados"],
            ["todos", "Todos"],
          ] as const
        ).map(([id, rotulo]) => (
          <button
            key={id}
            onClick={() => setFiltro(id)}
            className={`rounded-lg px-3 py-1.5 text-sm ${filtro === id ? "bg-card font-semibold" : "text-muted-foreground"}`}
          >
            {rotulo}
          </button>
        ))}
      </div>

      {vista === "lista" && filtro === "proximos" && atrasados.length > 0 && (
        <p className="rounded-lg border border-azul/40 bg-azul-soft px-4 py-2 text-sm text-azul">
          {atrasados.length} {atrasados.length === 1 ? "agendamento já passou e continua" : "agendamentos já passaram e continuam"}{" "}
          "Confirmado". Marque como realizado ou cancele (veja em "Todos").
        </p>
      )}
      {agenda.isLoading && <p className="text-muted-foreground">Carregando...</p>}
      {agenda.isError && <p className="text-sm text-destructive">{(agenda.error as Error).message}</p>}

      {lista.map((a) => (
        <div key={a.agendamentoid} className="space-y-2 rounded-lg border border-border bg-card px-4 py-3">
          <button className="w-full text-left" onClick={() => setAberto(aberto === a.agendamentoid ? null : a.agendamentoid)}>
            <div className="flex flex-wrap items-baseline justify-between gap-2">
              <p className="font-medium">
                {quando(a.dataevento)} · {a.tipoevento}
                <span className={`ml-2 rounded-md border px-2 py-0.5 text-xs font-normal ${COR[a.statusagendamento] ?? ""}`}>
                  {a.statusagendamento}
                </span>
              </p>
              <p className="text-sm text-muted-foreground">
                {a.statuspagamento}
                {a.valor !== null && ` · ${reais(a.valor)}`}
              </p>
            </div>
            <p className="text-sm text-muted-foreground">
              {a.nomecliente}
              {a.telefonecliente && ` · ${telefone(a.telefonecliente)}`}
              {a.cpfcliente && ` · CPF ${cpfMascarado(a.cpfcliente)}`}
              {" · "}Responsável: {nomes.data?.get(a.funcionarioid) ?? "—"}
            </p>
            {a.motivocancelamento && <p className="text-xs text-destructive">Cancelado: {a.motivocancelamento}</p>}
          </button>
          {aberto === a.agendamentoid && <Detalhe a={a} pessoas={pessoas.data ?? []} />}
        </div>
      ))}
      {!agenda.isLoading && lista.length === 0 && (
        <p className="text-sm text-muted-foreground">
          {vista === "mes" ? (diaEscolhido ? "Nenhum agendamento neste dia." : "Toque num dia para ver os agendamentos.") : "Nenhum agendamento aqui."}
        </p>
      )}
    </section>
  );
}

/** Grade do mês: cada dia mostra os agendamentos (hora e tipo). */
function Calendario({
  mes,
  setMes,
  agenda,
  diaEscolhido,
  escolher,
}: {
  mes: string;
  setMes: (m: string) => void;
  agenda: Agendamento[];
  diaEscolhido: string | null;
  escolher: (d: string) => void;
}) {
  const [ano, m] = mes.split("-").map(Number);
  const primeiro = new Date(Date.UTC(ano, m - 1, 1));
  const diasNoMes = new Date(Date.UTC(ano, m, 0)).getUTCDate();
  const vazios = primeiro.getUTCDay();
  const h = hoje();
  const mudar = (delta: number) => {
    const d = new Date(Date.UTC(ano, m - 1 + delta, 1));
    setMes(d.toISOString().slice(0, 7));
  };
  const doDia = (dia: string) =>
    agenda.filter((a) => a.statusagendamento !== "Cancelado" && partes(a.dataevento).data === dia);
  const nomeMes = primeiro.toLocaleDateString("pt-BR", { month: "long", year: "numeric", timeZone: "UTC" });

  return (
    <div className="space-y-2">
      <div className="flex items-center justify-between">
        <button onClick={() => mudar(-1)} className="rounded-md border border-border px-3 py-1 text-sm" aria-label="Mês anterior">
          ‹
        </button>
        <p className="font-semibold capitalize">{nomeMes}</p>
        <button onClick={() => mudar(1)} className="rounded-md border border-border px-3 py-1 text-sm" aria-label="Próximo mês">
          ›
        </button>
      </div>
      <div className="grid grid-cols-7 gap-1 text-center text-xs text-muted-foreground">
        {["D", "S", "T", "Q", "Q", "S", "S"].map((d, i) => (
          <span key={i}>{d}</span>
        ))}
      </div>
      <div className="grid grid-cols-7 gap-1">
        {Array.from({ length: vazios }, (_, i) => (
          <span key={`v${i}`} />
        ))}
        {Array.from({ length: diasNoMes }, (_, i) => {
          const dia = `${mes}-${String(i + 1).padStart(2, "0")}`;
          const itens = doDia(dia);
          return (
            <button
              key={dia}
              onClick={() => escolher(dia)}
              className={`min-h-16 rounded-md border p-1 text-left align-top sm:min-h-20 ${
                dia === diaEscolhido ? "border-primary bg-card" : "border-border"
              } ${dia === h ? "ring-1 ring-azul" : ""}`}
            >
              <span className={`text-xs ${dia < h ? "text-muted-foreground" : "font-semibold"}`}>{i + 1}</span>
              <span className="hidden sm:block">
                {itens.slice(0, 2).map((a) => (
                  <span key={a.agendamentoid} className="block truncate text-[11px] text-muted-foreground">
                    {partes(a.dataevento).hora} {a.tipoevento}
                  </span>
                ))}
                {itens.length > 2 && <span className="block text-[11px] text-azul">+{itens.length - 2}</span>}
              </span>
              {itens.length > 0 && (
                <span className="mt-1 block text-center text-xs font-semibold text-azul sm:hidden">{itens.length}</span>
              )}
            </button>
          );
        })}
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Detalhe: ações, anexos e histórico                                  */
/* ------------------------------------------------------------------ */

function Detalhe({ a, pessoas }: { a: Agendamento; pessoas: { funcionarioid: number; nome: string }[] }) {
  const qc = useQueryClient();
  const tipos = useTipos();
  const [aviso, setAviso] = useState<{ texto: string; grave: boolean } | null>(null);
  const [editando, setEditando] = useState<null | "dados" | "remarcar">(null);
  const p = partes(a.dataevento);
  const [nova, setNova] = useState({ data: p.data, hora: p.hora, motivo: "" });
  const [dados, setDados] = useState({
    tipo: a.tipoeventoid ?? ("" as number | ""),
    nome: a.nomecliente,
    cpf: cpfCompleto(a.cpfcliente),
    telefone: a.telefonecliente ?? "",
    observacoes: a.observacoes ?? "",
    whatsapp: a.aceitawhatsapp,
  });
  const confirmado = a.statusagendamento === "Confirmado";

  const acao = useMutation({
    mutationFn: async (fazer: () => Promise<{ error: unknown }>) => {
      const { error } = await fazer();
      if (error) throw error;
    },
    onSuccess: () => {
      setAviso({ texto: "Salvo.", grave: false });
      setEditando(null);
      atualizarTudo(qc);
    },
    onError: (e) => setAviso({ texto: (e as Error).message, grave: true }),
  });

  function comMotivo(pergunta: string, fazer: (motivo: string) => Promise<{ error: unknown }>) {
    const motivo = window.prompt(pergunta);
    if (motivo === null) return;
    if (!motivo.trim()) {
      setAviso({ texto: "O motivo é obrigatório.", grave: true });
      return;
    }
    acao.mutate(() => fazer(motivo.trim()) as Promise<{ error: unknown }>);
  }

  const botao = "rounded-md border border-border px-3 py-1 text-sm";

  return (
    <div className="space-y-3 border-t border-border pt-3">
      <div className="grid gap-1 text-sm sm:grid-cols-2">
        {a.cpfcliente && <p>CPF: {cpfCompleto(a.cpfcliente)}</p>}
        {a.telefonecliente && <p>Telefone: {telefone(a.telefonecliente)}</p>}
        <p>WhatsApp: {a.aceitawhatsapp ? "cliente aceita" : "não autorizado"}</p>
        {a.observacoes && <p className="sm:col-span-2">Observações: {a.observacoes}</p>}
      </div>

      <div className="flex flex-wrap gap-2">
        {confirmado && (
          <>
            <button onClick={() => setEditando(editando === "remarcar" ? null : "remarcar")} className={botao}>
              Remarcar
            </button>
            <button onClick={() => setEditando(editando === "dados" ? null : "dados")} className={botao}>
              Editar dados
            </button>
            <select
              value={a.funcionarioid}
              onChange={(e) =>
                acao.mutate(() =>
                  supabase.rpc("trocar_responsavel_agendamento", {
                    p_agendamentoid: a.agendamentoid,
                    p_funcionarioid: Number(e.target.value),
                  }) as unknown as Promise<{ error: unknown }>,
                )
              }
              className={`${campo} py-1`}
              aria-label="Responsável"
            >
              {!pessoas.some((x) => x.funcionarioid === a.funcionarioid) && <option value={a.funcionarioid}>(atual)</option>}
              {pessoas.map((x) => (
                <option key={x.funcionarioid} value={x.funcionarioid}>
                  Responsável: {x.nome}
                </option>
              ))}
            </select>
          </>
        )}
        {a.statusagendamento !== "Cancelado" && (
          <select
            value={a.statuspagamento}
            onChange={(e) => {
              const status = e.target.value;
              const valor = window.prompt("Valor combinado (R$). Deixe em branco se não houver.", a.valor !== null ? String(a.valor).replace(".", ",") : "");
              if (valor === null) return;
              acao.mutate(() =>
                supabase.rpc("alterar_pagamento_agendamento", {
                  p_agendamentoid: a.agendamentoid,
                  p_status: status,
                  p_valor: valor.trim() ? numero(valor) : undefined,
                }) as unknown as Promise<{ error: unknown }>,
              );
            }}
            className={`${campo} py-1`}
            aria-label="Pagamento"
          >
            {PAGAMENTOS.map((x) => (
              <option key={x} value={x}>
                Pagamento: {x}
              </option>
            ))}
          </select>
        )}
        {confirmado && (
          <button
            onClick={() =>
              acao.mutate(() => supabase.rpc("marcar_agendamento_realizado", { p_agendamentoid: a.agendamentoid }) as unknown as Promise<{ error: unknown }>)
            }
            className="rounded-md bg-primary px-3 py-1 text-sm font-semibold text-primary-foreground"
          >
            Marcar como realizado
          </button>
        )}
        {a.statusagendamento === "Realizado" && (
          <button
            onClick={() =>
              comMotivo("Por que o agendamento volta para confirmado?", (motivo) =>
                supabase.rpc("reabrir_agendamento", { p_agendamentoid: a.agendamentoid, p_motivo: motivo }) as unknown as Promise<{ error: unknown }>,
              )
            }
            className={botao}
          >
            Voltar para confirmado
          </button>
        )}
        {confirmado && (
          <button
            onClick={() =>
              comMotivo("Por que o agendamento está sendo cancelado?", (motivo) =>
                supabase.rpc("cancelar_agendamento", { p_agendamentoid: a.agendamentoid, p_motivo: motivo }) as unknown as Promise<{ error: unknown }>,
              )
            }
            className="rounded-md border border-destructive px-3 py-1 text-sm text-destructive"
          >
            Cancelar
          </button>
        )}
      </div>

      {editando === "remarcar" && (
        <form
          onSubmit={(e) => {
            e.preventDefault();
            acao.mutate(async () => {
              const inicio = instante(nova.data, nova.hora);
              const { data: perto } = await supabase.rpc("conflitos_agendamento", {
                p_lojaid: a.lojaid,
                p_dataevento: inicio,
                p_ignorar: a.agendamentoid,
              });
              const lista = (perto ?? []) as unknown as { quando: string; tipo: string }[];
              if (lista.length > 0 && !window.confirm(`Já existe agendamento perto desse horário (${lista.map((c) => `${partes(c.quando).hora} — ${c.tipo}`).join(", ")}). Remarcar mesmo assim?`)) {
                return { error: new Error("Remarcação cancelada.") };
              }
              return supabase.rpc("remarcar_agendamento", {
                p_agendamentoid: a.agendamentoid,
                p_novadata: inicio,
                p_motivo: nova.motivo || undefined,
              }) as unknown as Promise<{ error: unknown }>;
            });
          }}
          className="flex flex-wrap items-center gap-2"
        >
          <input type="date" required min={hoje()} value={nova.data} onChange={(e) => setNova({ ...nova, data: e.target.value })} className={campo} />
          <input type="time" required value={nova.hora} onChange={(e) => setNova({ ...nova, hora: e.target.value })} className={campo} />
          <input placeholder="Motivo (opcional)" value={nova.motivo} onChange={(e) => setNova({ ...nova, motivo: e.target.value })} className={`${campo} flex-1`} />
          <button type="submit" className="rounded-md bg-primary px-3 py-2 text-sm font-semibold text-primary-foreground">
            Salvar nova data
          </button>
        </form>
      )}

      {editando === "dados" && (
        <form
          onSubmit={(e) => {
            e.preventDefault();
            acao.mutate(() =>
              supabase.rpc("editar_agendamento", {
                p_agendamentoid: a.agendamentoid,
                p_tipoeventoid: Number(dados.tipo),
                p_nomecliente: dados.nome,
                p_cpf: dados.cpf,
                p_telefone: dados.telefone,
                p_observacoes: dados.observacoes,
                p_aceitawhatsapp: dados.whatsapp,
              }) as unknown as Promise<{ error: unknown }>,
            );
          }}
          className="grid gap-2 sm:grid-cols-3"
        >
          <select value={dados.tipo} onChange={(e) => setDados({ ...dados, tipo: Number(e.target.value) })} className={campo}>
            {(tipos.data ?? []).filter((t) => t.ativo || t.tipoeventoid === a.tipoeventoid).map((t) => (
              <option key={t.tipoeventoid} value={t.tipoeventoid}>
                {t.nome}
              </option>
            ))}
          </select>
          <input required value={dados.nome} onChange={(e) => setDados({ ...dados, nome: e.target.value })} className={`${campo} sm:col-span-2`} />
          <input placeholder="CPF" value={dados.cpf} onChange={(e) => setDados({ ...dados, cpf: e.target.value })} className={campo} />
          <input placeholder="Telefone" value={dados.telefone} onChange={(e) => setDados({ ...dados, telefone: e.target.value })} className={campo} />
          <label className="flex items-center gap-2 text-sm text-muted-foreground">
            <input type="checkbox" checked={dados.whatsapp} onChange={(e) => setDados({ ...dados, whatsapp: e.target.checked })} />
            Aceita WhatsApp
          </label>
          <textarea rows={2} value={dados.observacoes} onChange={(e) => setDados({ ...dados, observacoes: e.target.value })} className={`${campo} sm:col-span-3`} />
          <button type="submit" className="w-fit rounded-md bg-primary px-3 py-2 text-sm font-semibold text-primary-foreground">
            Salvar dados
          </button>
        </form>
      )}

      {aviso && <p className={`text-sm ${aviso.grave ? "text-destructive" : "text-sucesso"}`}>{aviso.texto}</p>}

      <Anexos a={a} />
      <Historico agendamentoid={a.agendamentoid} />
    </div>
  );
}

function Anexos({ a }: { a: Agendamento }) {
  const qc = useQueryClient();
  const [erro, setErro] = useState<string | null>(null);

  const anexos = useQuery({
    queryKey: ["agenda-anexos", a.agendamentoid],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("agendamentosanexos")
        .select("anexoid, caminho, nomearquivo, tamanho, enviadoem")
        .eq("agendamentoid", a.agendamentoid)
        .is("removidoem", null)
        .order("enviadoem");
      if (error) throw error;
      return data ?? [];
    },
  });

  const enviar = useMutation({
    mutationFn: async (arquivo: File) => {
      const tipo = await validarArquivo(arquivo);
      const seguro = arquivo.name.normalize("NFD").replace(/[^\w.-]+/g, "_").slice(-80);
      const caminho = `${a.contaid}/${a.lojaid}/${a.agendamentoid}/${Date.now()}-${seguro}`;
      const { error: e1 } = await supabase.storage.from("agendamentos").upload(caminho, arquivo, { contentType: tipo });
      if (e1) throw e1;
      const { error: e2 } = await supabase.rpc("registrar_anexo_agendamento", {
        p_agendamentoid: a.agendamentoid,
        p_caminho: caminho,
        p_nomearquivo: arquivo.name,
        p_tipo: tipo,
        p_tamanho: arquivo.size,
      });
      if (e2) {
        await supabase.storage.from("agendamentos").remove([caminho]);
        throw e2;
      }
    },
    onSuccess: () => {
      setErro(null);
      atualizarTudo(qc);
    },
    onError: (e) => setErro((e as Error).message),
  });

  async function abrir(caminho: string) {
    // Link temporário: vale 5 minutos.
    const { data, error } = await supabase.storage.from("agendamentos").createSignedUrl(caminho, 300);
    if (error || !data) {
      setErro("Não foi possível abrir o arquivo.");
      return;
    }
    window.open(data.signedUrl, "_blank", "noopener");
  }

  const remover = useMutation({
    mutationFn: async (anexoid: number) => {
      const { data: caminho, error } = await supabase.rpc("remover_anexo_agendamento", { p_anexoid: anexoid });
      if (error) throw error;
      if (caminho) await supabase.storage.from("agendamentos").remove([caminho as string]);
    },
    onSuccess: () => atualizarTudo(qc),
    onError: (e) => setErro((e as Error).message),
  });

  return (
    <div className="space-y-2">
      <p className="text-sm font-semibold">Anexos</p>
      {(anexos.data ?? []).map((x) => (
        <div key={x.anexoid} className="flex flex-wrap items-center justify-between gap-2 text-sm">
          <button onClick={() => abrir(x.caminho)} className="text-left underline">
            📎 {x.nomearquivo}
          </button>
          <span className="flex items-center gap-2 text-xs text-muted-foreground">
            {(x.tamanho / 1024).toLocaleString("pt-BR", { maximumFractionDigits: 0 })} KB · {dataHora(x.enviadoem)}
            <button
              onClick={() => window.confirm(`Remover o anexo "${x.nomearquivo}"?`) && remover.mutate(x.anexoid)}
              className="rounded-md border border-border px-2 py-0.5"
            >
              Remover
            </button>
          </span>
        </div>
      ))}
      {a.statusagendamento !== "Cancelado" && (
        <label className="block w-fit cursor-pointer rounded-md border border-dashed border-border px-3 py-1.5 text-sm text-muted-foreground">
          {enviar.isPending ? "Enviando..." : "+ Anexar (PDF, JPG ou PNG, até 10 MB)"}
          <input
            type="file"
            accept="application/pdf,image/jpeg,image/png"
            className="hidden"
            disabled={enviar.isPending}
            onChange={(e) => {
              const arquivo = e.target.files?.[0];
              e.target.value = "";
              if (arquivo) enviar.mutate(arquivo);
            }}
          />
        </label>
      )}
      {erro && <p className="text-sm text-destructive">{erro}</p>}
    </div>
  );
}

const ACOES: Record<string, string> = {
  criado: "Criado",
  editado: "Dados alterados",
  remarcado: "Remarcado",
  responsavel: "Responsável trocado",
  pagamento: "Pagamento",
  realizado: "Marcado como realizado",
  reaberto: "Voltou para confirmado",
  cancelado: "Cancelado",
  anexo: "Anexo enviado",
  anexo_removido: "Anexo removido",
};

function Historico({ agendamentoid }: { agendamentoid: number }) {
  const historico = useQuery({
    queryKey: ["agenda-historico", agendamentoid],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("agendamentoshistorico")
        .select("historicoid, acao, valoranterior, valornovo, motivo, alteradoem")
        .eq("agendamentoid", agendamentoid)
        .order("historicoid");
      if (error) throw error;
      return data ?? [];
    },
  });

  return (
    <div className="space-y-1">
      <p className="text-sm font-semibold">Histórico</p>
      <ol className="space-y-1 border-l border-border pl-3 text-xs text-muted-foreground">
        {(historico.data ?? []).map((h) => (
          <li key={h.historicoid}>
            {dataHora(h.alteradoem)} · <strong className="text-foreground">{ACOES[h.acao] ?? h.acao}</strong>
            {h.valoranterior && h.valornovo ? `: ${h.valoranterior} → ${h.valornovo}` : h.valornovo ? `: ${h.valornovo}` : h.valoranterior ? `: ${h.valoranterior}` : ""}
            {h.motivo && ` · “${h.motivo}”`}
          </li>
        ))}
      </ol>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Tipos de evento (por conta)                                         */
/* ------------------------------------------------------------------ */

function Tipos() {
  const qc = useQueryClient();
  const tipos = useTipos();
  const [nome, setNome] = useState("");

  const criar = useMutation({
    mutationFn: async () => {
      if (!nome.trim()) throw new Error("Dê um nome ao tipo.");
      const { error } = await supabase.from("tiposevento").insert({ nome: nome.trim() });
      if (error) {
        if (error.code === "23505") throw new Error("Já existe um tipo com esse nome.");
        throw error;
      }
    },
    onSuccess: () => {
      setNome("");
      qc.invalidateQueries({ queryKey: ["tipos-evento"] });
    },
  });

  const alterar = useMutation({
    mutationFn: async (x: { id: number; nome?: string; ativo?: boolean }) => {
      const { error } = await supabase
        .from("tiposevento")
        .update({ ...(x.nome !== undefined ? { nome: x.nome } : {}), ...(x.ativo !== undefined ? { ativo: x.ativo } : {}) })
        .eq("tipoeventoid", x.id);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ["tipos-evento"] }),
  });

  return (
    <div className="space-y-3">
      <form
        onSubmit={(e) => {
          e.preventDefault();
          criar.mutate();
        }}
        className="flex flex-wrap gap-2 rounded-xl border border-border bg-card p-4"
      >
        <input placeholder="Novo tipo (ex.: Festa infantil)" maxLength={100} value={nome} onChange={(e) => setNome(e.target.value)} className={`${campo} flex-1`} />
        <button type="submit" className="rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground">
          Adicionar
        </button>
      </form>
      {criar.isError && <p className="text-sm text-destructive">{(criar.error as Error).message}</p>}
      {alterar.isError && <p className="text-sm text-destructive">{(alterar.error as Error).message}</p>}
      <p className="text-xs text-muted-foreground">
        Desativar um tipo tira ele da lista de novos agendamentos; os agendamentos já feitos continuam com o nome que tinham.
      </p>
      {(tipos.data ?? []).map((t) => (
        <div key={t.tipoeventoid} className="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-border bg-card px-4 py-2">
          <span className={t.ativo ? "" : "text-muted-foreground line-through"}>{t.nome}</span>
          <span className="flex gap-2">
            <button
              onClick={() => {
                const novo = window.prompt("Novo nome do tipo:", t.nome);
                if (novo && novo.trim()) alterar.mutate({ id: t.tipoeventoid, nome: novo.trim() });
              }}
              className="rounded-md border border-border px-3 py-1 text-sm"
            >
              Renomear
            </button>
            <button onClick={() => alterar.mutate({ id: t.tipoeventoid, ativo: !t.ativo })} className="rounded-md border border-border px-3 py-1 text-sm">
              {t.ativo ? "Desativar" : "Reativar"}
            </button>
          </span>
        </div>
      ))}
    </div>
  );
}
