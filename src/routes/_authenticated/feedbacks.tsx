import { createFileRoute } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Pagina } from "@/ui/Pagina";

export const Route = createFileRoute("/_authenticated/feedbacks")({
  component: Feedbacks,
});

const campo =
  "rounded-lg border border-border bg-background px-3 py-2 text-sm placeholder:text-muted-foreground";

const hoje = () => new Intl.DateTimeFormat("en-CA", { timeZone: "America/Sao_Paulo" }).format(new Date());

function menosUmDia(iso: string) {
  const d = new Date(`${iso}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() - 1);
  return d.toISOString().slice(0, 10);
}

/** AAAA-MM-DD → dd/mm/aaaa, sem passar por fuso. */
const dia = (iso: string) => `${iso.slice(8, 10)}/${iso.slice(5, 7)}/${iso.slice(0, 4)}`;

function corDaNota(n: number) {
  if (n >= 8) return "text-sucesso";
  if (n >= 5) return "text-azul";
  return "text-destructive";
}

function usePessoas() {
  return useQuery({
    queryKey: ["pessoas-feedback"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("funcionarios")
        .select("funcionarioid, nomecompleto, ativo")
        .order("nomecompleto");
      if (error) throw error;
      return data ?? [];
    },
  });
}

function Feedbacks() {
  return (
    <Pagina titulo="Feedbacks">
      <p className="text-sm text-muted-foreground">
        A nota que cada pessoa dá para o próprio dia, de 0 a 10. Enquanto o bot não chega, o gestor registra (fica marcado
        como "registrado pelo gestor"). Um por pessoa por dia; o bônus entra no saldo e aparece no extrato.
      </p>
      <Registrar />
      <Lista />
    </Pagina>
  );
}

/* ------------------------------------------------------------------ */
/* Registrar                                                           */
/* ------------------------------------------------------------------ */

function Registrar() {
  const qc = useQueryClient();
  const pessoas = usePessoas();
  const h = hoje();
  const [funcionarioid, setFuncionarioid] = useState<number | "">("");
  const [qualDia, setQualDia] = useState<"hoje" | "ontem">("hoje");
  const [nota, setNota] = useState<number | null>(null);
  const [comentario, setComentario] = useState("");
  const [recado, setRecado] = useState<string | null>(null);

  const registrar = useMutation({
    mutationFn: async () => {
      if (funcionarioid === "") throw new Error("Escolha a pessoa.");
      if (nota === null) throw new Error("Escolha a nota.");
      const { error } = await supabase.rpc("registrar_feedback", {
        p_funcionarioid: funcionarioid,
        p_dia: qualDia === "hoje" ? h : menosUmDia(h),
        p_nota: nota,
        p_comentario: comentario,
      });
      if (error) throw error;
    },
    onSuccess: () => {
      const nome = (pessoas.data ?? []).find((p) => p.funcionarioid === funcionarioid)?.nomecompleto;
      setRecado(`Feedback de ${nome} registrado: nota ${nota}.`);
      setNota(null);
      setComentario("");
      setFuncionarioid("");
      for (const k of ["feedbacks", "extrato", "pessoas-saldo", "ganhadores", "conquistas-pessoa"]) {
        qc.invalidateQueries({ queryKey: [k] });
      }
    },
  });

  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        setRecado(null);
        registrar.mutate();
      }}
      className="space-y-3 rounded-xl border border-border bg-card p-4"
    >
      <p className="text-sm font-semibold">Registrar feedback</p>
      <div className="flex flex-wrap items-center gap-3">
        <select
          required
          value={funcionarioid}
          onChange={(e) => setFuncionarioid(e.target.value === "" ? "" : Number(e.target.value))}
          className={`${campo} w-full sm:w-auto`}
        >
          <option value="">Quem está avaliando o dia...</option>
          {(pessoas.data ?? [])
            .filter((p) => p.ativo)
            .map((p) => (
              <option key={p.funcionarioid} value={p.funcionarioid}>
                {p.nomecompleto}
              </option>
            ))}
        </select>
        <div className="flex gap-4 text-sm">
          <label className="flex items-center gap-2">
            <input type="radio" checked={qualDia === "hoje"} onChange={() => setQualDia("hoje")} />
            Hoje ({dia(h)})
          </label>
          <label className="flex items-center gap-2">
            <input type="radio" checked={qualDia === "ontem"} onChange={() => setQualDia("ontem")} />
            Ontem ({dia(menosUmDia(h))})
          </label>
        </div>
      </div>

      <div>
        <p className="mb-2 text-sm text-muted-foreground">Nota do dia (0 = muito ruim, 10 = excelente)</p>
        <div className="grid grid-cols-6 gap-2 sm:flex sm:flex-wrap">
          {Array.from({ length: 11 }, (_, n) => (
            <button
              key={n}
              type="button"
              onClick={() => setNota(n)}
              aria-pressed={nota === n}
              className={`h-11 rounded-lg border text-base font-semibold sm:w-11 ${
                nota === n ? "border-primary bg-primary text-primary-foreground" : "border-border bg-background"
              }`}
            >
              {n}
            </button>
          ))}
        </div>
      </div>

      <input
        placeholder="Comentário (opcional)"
        maxLength={500}
        value={comentario}
        onChange={(e) => setComentario(e.target.value)}
        className={`${campo} w-full`}
      />

      <button
        type="submit"
        disabled={registrar.isPending}
        className="rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground disabled:opacity-60"
      >
        {registrar.isPending ? "Registrando..." : "Registrar feedback"}
      </button>
      <p className="text-xs text-muted-foreground">
        Só hoje ou ontem. A nota não se altera depois; se foi lançada errado, anule com motivo (o bônus é estornado).
      </p>
      {recado && <p className="text-sm text-sucesso">{recado}</p>}
      {registrar.isError && <p className="text-sm text-destructive">{(registrar.error as Error).message}</p>}
    </form>
  );
}

/* ------------------------------------------------------------------ */
/* Lista com filtro, médias e anulação                                 */
/* ------------------------------------------------------------------ */

type Feedback = {
  feedbackid: number;
  funcionarioid: number;
  datafeedback: string;
  notadia: number;
  comentario: string | null;
  origem: string;
  pontosbonus: number;
  anuladoem: string | null;
  motivoanulacao: string | null;
};

function Lista() {
  const qc = useQueryClient();
  const pessoas = usePessoas();
  const h = hoje();
  const [funcionarioid, setFuncionarioid] = useState<number | "">("");
  const [de, setDe] = useState(`${h.slice(0, 7)}-01`);
  const [ate, setAte] = useState(h);
  const [aviso, setAviso] = useState<{ texto: string; grave: boolean } | null>(null);

  const feedbacks = useQuery({
    queryKey: ["feedbacks", funcionarioid, de, ate],
    enabled: de !== "" && ate !== "",
    queryFn: async () => {
      let q = supabase
        .from("feedbacks")
        .select("feedbackid, funcionarioid, datafeedback, notadia, comentario, origem, pontosbonus, anuladoem, motivoanulacao")
        .gte("datafeedback", de)
        .lte("datafeedback", ate)
        .order("datafeedback", { ascending: false })
        .order("feedbackid", { ascending: false })
        .limit(500);
      if (funcionarioid !== "") q = q.eq("funcionarioid", funcionarioid);
      const { data, error } = await q;
      if (error) throw error;
      return (data ?? []) as Feedback[];
    },
  });

  const anular = useMutation({
    mutationFn: async ({ feedbackid, motivo }: { feedbackid: number; motivo: string }) => {
      const { error } = await supabase.rpc("anular_feedback", { p_feedbackid: feedbackid, p_motivo: motivo });
      if (error) throw error;
    },
    onSuccess: () => {
      setAviso({ texto: "Feedback anulado e bônus estornado.", grave: false });
      for (const k of ["feedbacks", "extrato", "pessoas-saldo"]) qc.invalidateQueries({ queryKey: [k] });
    },
    onError: (e) => setAviso({ texto: (e as Error).message, grave: true }),
  });

  function pedirMotivo(feedbackid: number) {
    const motivo = window.prompt("Por que está anulando este feedback? (o bônus será estornado)");
    if (motivo === null) return;
    if (motivo.trim() === "") {
      setAviso({ texto: "O motivo é obrigatório.", grave: true });
      return;
    }
    anular.mutate({ feedbackid, motivo: motivo.trim() });
  }

  const nome = new Map((pessoas.data ?? []).map((p) => [p.funcionarioid, p.nomecompleto]));
  const lista = feedbacks.data ?? [];
  const validos = lista.filter((f) => !f.anuladoem);

  // Média por pessoa no período (sem os anulados).
  const medias = [...validos.reduce((m, f) => {
    const a = m.get(f.funcionarioid) ?? { soma: 0, qtd: 0 };
    m.set(f.funcionarioid, { soma: a.soma + f.notadia, qtd: a.qtd + 1 });
    return m;
  }, new Map<number, { soma: number; qtd: number }>())]
    .map(([id, v]) => ({ id, media: v.soma / v.qtd, qtd: v.qtd }))
    .sort((a, b) => a.media - b.media);

  return (
    <section className="space-y-4">
      <div className="flex flex-wrap items-center gap-3">
        <select
          value={funcionarioid}
          onChange={(e) => setFuncionarioid(e.target.value === "" ? "" : Number(e.target.value))}
          className={campo}
        >
          <option value="">Todas as pessoas</option>
          {(pessoas.data ?? []).map((p) => (
            <option key={p.funcionarioid} value={p.funcionarioid}>
              {p.nomecompleto}
            </option>
          ))}
        </select>
        <label className="flex items-center gap-2 text-sm text-muted-foreground">
          De
          <input type="date" value={de} onChange={(e) => setDe(e.target.value)} className={campo} />
        </label>
        <label className="flex items-center gap-2 text-sm text-muted-foreground">
          até
          <input type="date" value={ate} onChange={(e) => setAte(e.target.value)} className={campo} />
        </label>
      </div>

      {medias.length > 0 && (
        <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
          {medias.map((m) => (
            <div key={m.id} className="flex items-center justify-between rounded-lg border border-border bg-card px-4 py-2">
              <span className="text-sm">{nome.get(m.id) ?? "—"}</span>
              <span className="text-sm text-muted-foreground">
                média <strong className={corDaNota(m.media)}>{m.media.toLocaleString("pt-BR", { maximumFractionDigits: 1 })}</strong>{" "}
                · {m.qtd} {m.qtd === 1 ? "dia" : "dias"}
              </span>
            </div>
          ))}
        </div>
      )}

      {aviso && (
        <p className={`rounded-lg border bg-card px-4 py-3 text-sm ${aviso.grave ? "border-destructive text-destructive" : "border-border"}`}>
          {aviso.texto}
        </p>
      )}
      {feedbacks.isLoading && <p className="text-muted-foreground">Carregando...</p>}
      {feedbacks.isError && <p className="text-sm text-destructive">{(feedbacks.error as Error).message}</p>}

      <div className="space-y-2">
        {lista.map((f) => (
          <div
            key={f.feedbackid}
            className={`flex flex-wrap items-center justify-between gap-3 rounded-lg border border-border bg-card px-4 py-3 ${
              f.anuladoem ? "opacity-60" : ""
            }`}
          >
            <div className="flex min-w-0 items-center gap-4">
              <span className={`w-10 text-center text-2xl font-bold ${f.anuladoem ? "line-through" : corDaNota(f.notadia)}`}>
                {f.notadia}
              </span>
              <div className="min-w-0">
                <p className="font-medium">
                  {nome.get(f.funcionarioid) ?? "—"}
                  <span className="ml-2 text-sm font-normal text-muted-foreground">{dia(f.datafeedback)}</span>
                </p>
                {f.comentario && <p className="text-sm text-muted-foreground">“{f.comentario}”</p>}
                <p className="text-xs text-muted-foreground">
                  {f.origem === "gestor" ? "Registrado pelo gestor" : "Enviado pelo bot"}
                  {f.pontosbonus > 0 && ` · +${f.pontosbonus} pontos de bônus`}
                  {f.anuladoem && (
                    <span className="text-destructive"> · Anulado: {f.motivoanulacao} (bônus estornado)</span>
                  )}
                </p>
              </div>
            </div>
            {!f.anuladoem && (
              <button
                onClick={() => pedirMotivo(f.feedbackid)}
                className="rounded-md border border-destructive px-3 py-1 text-sm text-destructive"
              >
                Anular
              </button>
            )}
          </div>
        ))}
        {!feedbacks.isLoading && lista.length === 0 && (
          <p className="text-sm text-muted-foreground">Nenhum feedback neste período.</p>
        )}
      </div>
    </section>
  );
}
