import { createFileRoute } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { AvisoSemLoja, useLojaAtiva } from "@/lojas/loja-ativa";
import { FolgaDeHoje } from "@/painel/FolgaDeHoje";

export const Route = createFileRoute("/_authenticated/painel")({
  component: Quadro,
});

const BUCKET = "entregas";
const DIAS_DE_HISTORICO = 7;

const campo =
  "rounded-lg border border-border bg-background px-3 py-2 text-sm placeholder:text-muted-foreground";

function dataHora(iso: string | null) {
  if (!iso) return "—";
  return new Date(iso).toLocaleString("pt-BR", {
    timeZone: "America/Sao_Paulo",
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

type Entrega = {
  entregaid: number;
  statusvalidacao: string;
  dataenvio: string;
  dataaprovacao: string | null;
  datarecusa: string | null;
  dataestorno: string | null;
  pontosganhos: number | null;
  observacao: string | null;
  motivorecusa: string | null;
  motivoestorno: string | null;
  titulo: string;
  pontosDaTarefa: number;
  nome: string;
  foto: string | null;
};

function Quadro() {
  const { lojas, lojaAtiva, loja, carregando } = useLojaAtiva();

  if (carregando) {
    return (
      <div className="mx-auto max-w-6xl space-y-6">
        <p className="text-muted-foreground">Carregando...</p>
      </div>
    );
  }

  if (lojas.length === 0 || lojaAtiva === null) {
    return (
      <div className="mx-auto max-w-6xl space-y-6">
        <h1 className="text-2xl font-bold tracking-tight sm:text-3xl">Quadro</h1>
        <AvisoSemLoja />
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-6xl space-y-6">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <h1 className="text-2xl font-bold tracking-tight sm:text-3xl">Quadro</h1>
        <p className="text-sm text-muted-foreground">
          Loja <strong className="text-foreground">{loja?.nome}</strong>
        </p>
      </div>
      <RegistrarEntrega lojaid={lojaAtiva} />
      <FolgaDeHoje lojaid={lojaAtiva} />
      <Validacao lojaid={lojaAtiva} />
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Registrar entrega (enquanto o bot não existe)                       */
/* ------------------------------------------------------------------ */

function RegistrarEntrega({ lojaid }: { lojaid: number }) {
  const qc = useQueryClient();
  const [atribuicaoid, setAtribuicaoid] = useState<number | "">("");
  const [observacao, setObservacao] = useState("");
  const [foto, setFoto] = useState<File | null>(null);
  const [jaAprovada, setJaAprovada] = useState(false);
  const [recado, setRecado] = useState<string | null>(null);

  const opcoes = useQuery({
    queryKey: ["para-entregar", lojaid],
    queryFn: async () => {
      const { data, error } = await supabase.rpc("atribuicoes_para_entregar", { p_lojaid: lojaid });
      if (error) throw error;
      return data ?? [];
    },
  });

  const registrar = useMutation({
    mutationFn: async () => {
      if (atribuicaoid === "") throw new Error("Escolha o que foi feito.");

      // A foto vai para <contaid>/<lojaid>/..., a pasta que só esta conta enxerga.
      let caminho: string | null = null;
      if (foto) {
        const { data: conta, error: erroConta } = await supabase.rpc("minha_conta");
        if (erroConta || conta === null) throw new Error("Não foi possível identificar sua conta.");
        const extensao = (foto.name.split(".").pop() || "jpg").toLowerCase();
        caminho = `${conta}/${lojaid}/${crypto.randomUUID()}.${extensao}`;
        const { error: erroUpload } = await supabase.storage
          .from(BUCKET)
          .upload(caminho, foto, { contentType: foto.type || "image/jpeg", upsert: false });
        if (erroUpload) throw new Error(`Não foi possível enviar a foto: ${erroUpload.message}`);
      }

      const { error } = await supabase.rpc("registrar_entrega", {
        p_atribuicaoid: Number(atribuicaoid),
        p_observacao: observacao,
        p_pathfoto: caminho ?? undefined,
        p_aprovar: jaAprovada,
      });
      if (error) {
        if (caminho) await supabase.storage.from(BUCKET).remove([caminho]);
        throw error;
      }
      return jaAprovada;
    },
    onSuccess: (aprovada) => {
      setRecado(aprovada ? "Entrega registrada e aprovada." : "Entrega registrada. Ela está em Pendentes.");
      setAtribuicaoid("");
      setObservacao("");
      setFoto(null);
      setJaAprovada(false);
      qc.invalidateQueries({ queryKey: ["para-entregar", lojaid] });
      qc.invalidateQueries({ queryKey: ["quadro", lojaid] });
      qc.invalidateQueries({ queryKey: ["equipe"] });
      qc.invalidateQueries({ queryKey: ["folga-hoje", lojaid] });
    },
  });

  const lista = opcoes.data ?? [];

  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        setRecado(null);
        registrar.mutate();
      }}
      className="space-y-3 rounded-xl border border-border bg-card p-4"
    >
      <div>
        <p className="text-sm font-semibold">Registrar entrega</p>
        <p className="text-xs text-muted-foreground">
          Aparecem só as tarefas que caem hoje ou estão atrasadas, e que ainda não foram entregues.
        </p>
      </div>

      <div className="grid grid-cols-1 gap-3 md:grid-cols-2">
        <select
          required
          value={atribuicaoid}
          onChange={(e) => setAtribuicaoid(e.target.value === "" ? "" : Number(e.target.value))}
          className={campo}
        >
          <option value="">
            {lista.length === 0 ? "Nada para entregar hoje" : "Quem fez o quê..."}
          </option>
          {lista.map((a) => (
            <option key={a.atribuicaoid} value={a.atribuicaoid}>
              {a.nomecompleto} — {a.titulo} ({a.pontos} pts){a.atrasada ? " · ATRASADA" : ""}
            </option>
          ))}
        </select>

        <label className="flex min-w-0 flex-wrap items-center gap-2 text-sm text-muted-foreground">
          Foto (opcional):
          <input
            type="file"
            accept="image/*"
            onChange={(e) => setFoto(e.target.files?.[0] ?? null)}
            className="min-w-0 max-w-full text-sm"
          />
        </label>

        <input
          placeholder="Observação (opcional)"
          value={observacao}
          onChange={(e) => setObservacao(e.target.value)}
          className={`${campo} md:col-span-2`}
        />
      </div>

      <label className="flex items-center gap-2 text-sm">
        <input type="checkbox" checked={jaAprovada} onChange={(e) => setJaAprovada(e.target.checked)} />
        Registrar já aprovada (eu mesmo conferi agora)
      </label>

      <button
        type="submit"
        disabled={registrar.isPending || lista.length === 0}
        className="rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground disabled:opacity-50"
      >
        {registrar.isPending ? "Registrando..." : "Registrar"}
      </button>

      {recado && <p className="text-sm text-sucesso">{recado}</p>}
      {registrar.isError && (
        <p className="text-sm text-destructive">{(registrar.error as Error).message}</p>
      )}
    </form>
  );
}

/* ------------------------------------------------------------------ */
/* Validação: Pendentes · Aprovadas · Recusadas                        */
/* ------------------------------------------------------------------ */

function Validacao({ lojaid }: { lojaid: number }) {
  const qc = useQueryClient();
  const [aviso, setAviso] = useState<{ texto: string; grave: boolean } | null>(null);

  const quadro = useQuery({
    queryKey: ["quadro", lojaid],
    queryFn: async (): Promise<Entrega[]> => {
      const desde = new Date(Date.now() - DIAS_DE_HISTORICO * 24 * 3600 * 1000).toISOString();
      const { data, error } = await supabase
        .from("entregas")
        .select(
          "entregaid, tarefaid, funcionarioid, statusvalidacao, dataenvio, dataaprovacao, datarecusa, dataestorno, pontosganhos, observacao, motivorecusa, motivoestorno, pathfotoevidencia",
        )
        .eq("lojaid", lojaid)
        .or(`statusvalidacao.eq.Pendente,dataenvio.gte.${desde}`)
        .order("dataenvio", { ascending: false });
      if (error) throw error;
      const linhas = data ?? [];
      if (linhas.length === 0) return [];

      const { data: tarefas } = await supabase
        .from("tarefas")
        .select("tarefaid, titulo, pontos")
        .in("tarefaid", [...new Set(linhas.map((l) => l.tarefaid))]);
      const { data: pessoas } = await supabase
        .from("funcionarios")
        .select("funcionarioid, nomecompleto")
        .in("funcionarioid", [...new Set(linhas.map((l) => l.funcionarioid))]);

      // Link temporário (1 hora). O bucket é privado: não existe link público.
      const caminhos = linhas.map((l) => l.pathfotoevidencia).filter((c): c is string => !!c);
      const links = new Map<string, string>();
      if (caminhos.length > 0) {
        const { data: assinados } = await supabase.storage.from(BUCKET).createSignedUrls(caminhos, 3600);
        for (const a of assinados ?? []) if (a.path && a.signedUrl) links.set(a.path, a.signedUrl);
      }

      const tarefa = new Map((tarefas ?? []).map((t) => [t.tarefaid, t]));
      const nome = new Map((pessoas ?? []).map((p) => [p.funcionarioid, p.nomecompleto]));

      return linhas.map((l) => ({
        ...l,
        titulo: tarefa.get(l.tarefaid)?.titulo ?? `Tarefa ${l.tarefaid}`,
        pontosDaTarefa: tarefa.get(l.tarefaid)?.pontos ?? 0,
        nome: nome.get(l.funcionarioid) ?? "—",
        foto: l.pathfotoevidencia ? (links.get(l.pathfotoevidencia) ?? null) : null,
      }));
    },
  });

  function atualizar() {
    qc.invalidateQueries({ queryKey: ["quadro", lojaid] });
    qc.invalidateQueries({ queryKey: ["para-entregar", lojaid] });
    qc.invalidateQueries({ queryKey: ["equipe"] });
    qc.invalidateQueries({ queryKey: ["ranking"] });
  }

  const aprovar = useMutation({
    mutationFn: async (e: Entrega) => {
      const { data, error } = await supabase.rpc("aprovar_entrega", { p_entregaid: e.entregaid });
      if (error) throw error;
      return { pontos: data as number, nome: e.nome };
    },
    onSuccess: (r) => {
      setAviso({ texto: `Aprovada: +${r.pontos} pontos para ${r.nome}.`, grave: false });
      atualizar();
    },
    onError: (err) => setAviso({ texto: (err as Error).message, grave: true }),
  });

  const recusar = useMutation({
    mutationFn: async ({ e, motivo }: { e: Entrega; motivo: string }) => {
      const { error } = await supabase.rpc("recusar_entrega", { p_entregaid: e.entregaid, p_motivo: motivo });
      if (error) throw error;
      return e.nome;
    },
    onSuccess: (nome) => {
      setAviso({ texto: `Recusada. A tarefa volta a aparecer para ${nome}.`, grave: false });
      atualizar();
    },
    onError: (err) => setAviso({ texto: (err as Error).message, grave: true }),
  });

  const estornar = useMutation({
    mutationFn: async ({ e, motivo }: { e: Entrega; motivo: string }) => {
      const { data, error } = await supabase.rpc("estornar_entrega", { p_entregaid: e.entregaid, p_motivo: motivo });
      if (error) throw error;
      return { saldo: data as number, nome: e.nome, pontos: e.pontosganhos ?? 0 };
    },
    onSuccess: (r) => {
      setAviso(
        r.saldo < 0
          ? {
              texto: `Estornado: −${r.pontos} pontos. ATENÇÃO: o saldo de ${r.nome} ficou NEGATIVO (${r.saldo} pontos).`,
              grave: true,
            }
          : { texto: `Estornado: −${r.pontos} pontos de ${r.nome}. Saldo agora: ${r.saldo}.`, grave: false },
      );
      atualizar();
    },
    onError: (err) => setAviso({ texto: (err as Error).message, grave: true }),
  });

  const todas = quadro.data ?? [];
  const pendentes = todas.filter((e) => e.statusvalidacao === "Pendente");
  const aprovadas = todas.filter((e) => e.statusvalidacao === "Aprovada");
  const recusadas = todas.filter((e) => e.statusvalidacao === "Recusada" || e.statusvalidacao === "Estornada");

  return (
    <section className="space-y-3">
      {aviso && (
        <p
          className={`rounded-lg border px-4 py-3 text-sm ${
            aviso.grave ? "border-destructive text-destructive" : "border-border text-foreground"
          } bg-card`}
        >
          {aviso.texto}
        </p>
      )}

      {quadro.isLoading && <p className="text-muted-foreground">Carregando...</p>}
      {quadro.isError && <p className="text-sm text-destructive">{(quadro.error as Error).message}</p>}

      <div className="grid gap-4 md:grid-cols-3">
        <Coluna titulo="Pendentes" quantidade={pendentes.length}>
          {pendentes.map((e) => (
            <Cartao key={e.entregaid} e={e}>
              <div className="flex flex-wrap gap-2">
                <button
                  onClick={() => aprovar.mutate(e)}
                  disabled={aprovar.isPending}
                  className="rounded-md bg-primary px-3 py-1 text-sm font-semibold text-primary-foreground disabled:opacity-50"
                >
                  Aprovar (+{e.pontosDaTarefa})
                </button>
                <BotaoComMotivo
                  rotulo="Recusar"
                  pergunta="Por que está recusando? A pessoa vai ver este motivo."
                  onConfirmar={(motivo) => recusar.mutate({ e, motivo })}
                />
              </div>
            </Cartao>
          ))}
          {pendentes.length === 0 && <Vazio texto="Nada esperando validação." />}
        </Coluna>

        <Coluna titulo={`Aprovadas (${DIAS_DE_HISTORICO} dias)`} quantidade={aprovadas.length}>
          {aprovadas.map((e) => (
            <Cartao key={e.entregaid} e={e}>
              <p className="text-xs text-muted-foreground">
                Aprovada em {dataHora(e.dataaprovacao)} · <strong className="text-sucesso">+{e.pontosganhos}</strong>
              </p>
              <BotaoComMotivo
                rotulo="Estornar"
                pergunta={`Estornar desconta ${e.pontosganhos} pontos de ${e.nome}, mesmo que o saldo fique negativo. Qual o motivo?`}
                onConfirmar={(motivo) => estornar.mutate({ e, motivo })}
              />
            </Cartao>
          ))}
          {aprovadas.length === 0 && <Vazio texto="Nenhuma aprovação recente." />}
        </Coluna>

        <Coluna titulo={`Recusadas e estornadas (${DIAS_DE_HISTORICO} dias)`} quantidade={recusadas.length}>
          {recusadas.map((e) => (
            <Cartao key={e.entregaid} e={e}>
              {e.statusvalidacao === "Recusada" ? (
                <p className="text-xs text-muted-foreground">
                  Recusada em {dataHora(e.datarecusa)}: <em>{e.motivorecusa}</em>
                </p>
              ) : (
                <p className="text-xs text-destructive">
                  Estornada em {dataHora(e.dataestorno)} (−{e.pontosganhos}): <em>{e.motivoestorno}</em>
                </p>
              )}
            </Cartao>
          ))}
          {recusadas.length === 0 && <Vazio texto="Nada recusado recentemente." />}
        </Coluna>
      </div>
    </section>
  );
}

function Coluna({ titulo, quantidade, children }: { titulo: string; quantidade: number; children: React.ReactNode }) {
  return (
    <div className="space-y-2">
      <h2 className="text-sm font-semibold">
        {titulo} <span className="text-muted-foreground">· {quantidade}</span>
      </h2>
      {children}
    </div>
  );
}

function Vazio({ texto }: { texto: string }) {
  return <p className="rounded-lg border border-dashed border-border px-3 py-4 text-center text-sm text-muted-foreground">{texto}</p>;
}

function Cartao({ e, children }: { e: Entrega; children: React.ReactNode }) {
  return (
    <div className="space-y-2 rounded-lg border border-border bg-card p-3">
      {e.foto && (
        <a href={e.foto} target="_blank" rel="noreferrer">
          <img src={e.foto} alt={`Foto de ${e.titulo}`} className="max-h-40 w-full rounded-md object-cover" />
        </a>
      )}
      <div>
        <p className="font-medium">{e.titulo}</p>
        <p className="text-sm text-muted-foreground">
          {e.nome} · enviada em {dataHora(e.dataenvio)}
        </p>
        {e.observacao && <p className="text-sm">“{e.observacao}”</p>}
      </div>
      {children}
    </div>
  );
}

/** Botão que pede um motivo antes de agir. O banco também exige o motivo. */
function BotaoComMotivo({
  rotulo,
  pergunta,
  onConfirmar,
}: {
  rotulo: string;
  pergunta: string;
  onConfirmar: (motivo: string) => void;
}) {
  const [aberto, setAberto] = useState(false);
  const [motivo, setMotivo] = useState("");

  if (!aberto) {
    return (
      <button onClick={() => setAberto(true)} className="rounded-md border border-border px-3 py-1 text-sm">
        {rotulo}
      </button>
    );
  }

  return (
    <div className="w-full space-y-2">
      <p className="text-xs text-muted-foreground">{pergunta}</p>
      <textarea
        autoFocus
        value={motivo}
        onChange={(e) => setMotivo(e.target.value)}
        rows={2}
        className={`${campo} w-full`}
        placeholder="Motivo (obrigatório)"
      />
      <div className="flex gap-2">
        <button
          disabled={motivo.trim().length === 0}
          onClick={() => {
            if (!window.confirm(`Confirmar: ${rotulo.toLowerCase()}?`)) return;
            onConfirmar(motivo.trim());
            setAberto(false);
            setMotivo("");
          }}
          className="rounded-md border border-destructive px-3 py-1 text-sm text-destructive disabled:opacity-50"
        >
          Confirmar
        </button>
        <button
          onClick={() => {
            setAberto(false);
            setMotivo("");
          }}
          className="rounded-md border border-border px-3 py-1 text-sm"
        >
          Cancelar
        </button>
      </div>
    </div>
  );
}
