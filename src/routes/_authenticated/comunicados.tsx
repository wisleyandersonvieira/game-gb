import { createFileRoute } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { dataHoraBr, pdfComunicado, pdfReciboCiencia } from "@/rh/pdf";

export const Route = createFileRoute("/_authenticated/comunicados")({
  component: Comunicados,
});

const campo =
  "rounded-lg border border-border bg-background px-3 py-2 text-sm placeholder:text-muted-foreground";

type Comunicado = {
  documentoid: number;
  titulo: string;
  conteudo: string;
  pontosporciencia: number;
  datacriacao: string;
  status: string;
  alvo: string;
  primeiracienciaem: string | null;
};
type Ciencia = {
  assinaturaid: number;
  documentoid: number;
  funcionarioid: number;
  statusassinatura: string;
  dataciencia: string | null;
  origem: string | null;
  pontospagos: number;
  motivodesfazer: string | null;
};

function atualizarTudo(qc: ReturnType<typeof useQueryClient>) {
  for (const k of ["comunicados", "ciencias", "fora-do-comunicado", "extrato", "pessoas-saldo", "ganhadores"]) {
    qc.invalidateQueries({ queryKey: [k] });
  }
}

function usePessoas() {
  return useQuery({
    queryKey: ["pessoas-comunicado"],
    queryFn: async () => {
      const { data, error } = await supabase.from("funcionarios").select("funcionarioid, nomecompleto, ativo").order("nomecompleto");
      if (error) throw error;
      return data ?? [];
    },
  });
}

function useLojas() {
  return useQuery({
    queryKey: ["lojas-comunicado"],
    queryFn: async () => {
      const { data, error } = await supabase.from("lojas").select("lojaid, nome, ativa").order("nome");
      if (error) throw error;
      return data ?? [];
    },
  });
}

function Comunicados() {
  const [aba, setAba] = useState<"publicados" | "arquivados" | "novo">("publicados");
  const [aberto, setAberto] = useState<number | null>(null);

  const comunicados = useQuery({
    queryKey: ["comunicados"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("documentos")
        .select("documentoid, titulo, conteudo, pontosporciencia, datacriacao, status, alvo, primeiracienciaem")
        .order("datacriacao", { ascending: false })
        .limit(300);
      if (error) throw error;
      return (data ?? []) as Comunicado[];
    },
  });

  const ciencias = useQuery({
    queryKey: ["ciencias"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("documentosassinaturas")
        .select("assinaturaid, documentoid, funcionarioid, statusassinatura, dataciencia, origem, pontospagos, motivodesfazer");
      if (error) throw error;
      return (data ?? []) as Ciencia[];
    },
  });

  const lista = (comunicados.data ?? []).filter((c) => (aba === "arquivados" ? c.status === "Arquivado" : c.status === "Publicado"));

  return (
    <div className="mx-auto max-w-5xl space-y-6">
      <h1 className="text-2xl font-bold tracking-tight sm:text-3xl">Comunicados</h1>
      <p className="text-sm text-muted-foreground">
        Avisos para a equipe, com registro de quem leu e deu ciência. Por enquanto o gestor registra a ciência de cada
        pessoa (com data e hora); quando houver o portal ou o bot, o próprio funcionário confirma.
      </p>

      <div className="flex flex-wrap gap-x-2 border-b border-border">
        {(
          [
            ["publicados", "Publicados"],
            ["arquivados", "Arquivados"],
            ["novo", "Novo comunicado"],
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

      {aba === "novo" ? (
        <Novo aoPublicar={(id) => { setAba("publicados"); setAberto(id); }} />
      ) : (
        <div className="space-y-2">
          {comunicados.isLoading && <p className="text-muted-foreground">Carregando...</p>}
          {comunicados.isError && <p className="text-sm text-destructive">{(comunicados.error as Error).message}</p>}
          {lista.map((c) => {
            const destes = (ciencias.data ?? []).filter((s) => s.documentoid === c.documentoid);
            const cientes = destes.filter((s) => s.statusassinatura === "Ciente").length;
            return (
              <div key={c.documentoid} className="space-y-2 rounded-lg border border-border bg-card px-4 py-3">
                <button className="w-full text-left" onClick={() => setAberto(aberto === c.documentoid ? null : c.documentoid)}>
                  <div className="flex flex-wrap items-baseline justify-between gap-2">
                    <p className="font-medium">{c.titulo}</p>
                    <p className="text-sm text-muted-foreground">
                      <strong className={cientes === destes.length ? "text-sucesso" : "text-accent"}>
                        {cientes} de {destes.length}
                      </strong>{" "}
                      cientes · {dataHoraBr(c.datacriacao)}
                    </p>
                  </div>
                  <p className="text-xs text-muted-foreground">
                    {c.pontosporciencia > 0 ? `${c.pontosporciencia} pontos por ciência` : "Sem pontos"}
                    {c.primeiracienciaem ? " · texto travado (já tem ciência)" : ""}
                  </p>
                </button>
                {aberto === c.documentoid && <Detalhe c={c} ciencias={destes} />}
              </div>
            );
          })}
          {!comunicados.isLoading && lista.length === 0 && <p className="text-sm text-muted-foreground">Nenhum comunicado aqui.</p>}
        </div>
      )}
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Novo comunicado                                                     */
/* ------------------------------------------------------------------ */

function Novo({ aoPublicar }: { aoPublicar: (id: number) => void }) {
  const qc = useQueryClient();
  const pessoas = usePessoas();
  const lojas = useLojas();
  const padrao = useQuery({
    queryKey: ["pontos-leitura"],
    queryFn: async () => {
      const { data } = await supabase.from("tarefas").select("pontos").eq("sistema", "leitura").maybeSingle();
      return data?.pontos ?? 0;
    },
  });
  const [f, setF] = useState({ titulo: "", conteudo: "", pontos: "" });
  const [alvo, setAlvo] = useState<"conta" | "lojas" | "funcionarios">("conta");
  const [lojasEscolhidas, setLojas] = useState<number[]>([]);
  const [gente, setGente] = useState<number[]>([]);

  const alternar = (lista: number[], id: number) => (lista.includes(id) ? lista.filter((x) => x !== id) : [...lista, id]);

  const publicar = useMutation({
    mutationFn: async () => {
      const pontos = f.pontos.trim() === "" ? undefined : Number(f.pontos);
      if (pontos !== undefined && (!Number.isInteger(pontos) || pontos < 0)) throw new Error("Os pontos precisam ser um número inteiro, 0 ou mais.");
      const { data, error } = await supabase.rpc("publicar_comunicado", {
        p_titulo: f.titulo,
        p_conteudo: f.conteudo,
        p_pontos: pontos ?? (null as unknown as number),
        p_alvo: alvo,
        p_lojas: alvo === "lojas" ? lojasEscolhidas : undefined,
        p_funcionarios: alvo === "funcionarios" ? gente : undefined,
      });
      if (error) throw error;
      return data as number;
    },
    onSuccess: (id) => {
      setF({ titulo: "", conteudo: "", pontos: "" });
      atualizarTudo(qc);
      aoPublicar(id);
    },
  });

  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        publicar.mutate();
      }}
      className="space-y-3 rounded-xl border border-border bg-card p-4"
    >
      <input required maxLength={255} placeholder="Título" value={f.titulo} onChange={(e) => setF({ ...f, titulo: e.target.value })} className={`${campo} w-full`} />
      <textarea required rows={6} placeholder="Texto do comunicado" value={f.conteudo} onChange={(e) => setF({ ...f, conteudo: e.target.value })} className={`${campo} w-full`} />
      <label className="flex items-center gap-2 text-sm text-muted-foreground">
        Pontos por ciência:
        <input
          type="number"
          min={0}
          placeholder={String(padrao.data ?? 0)}
          value={f.pontos}
          onChange={(e) => setF({ ...f, pontos: e.target.value })}
          className={`${campo} w-24`}
        />
        <span className="text-xs">(em branco = {padrao.data ?? 0}, o padrão da tarefa do sistema "Leitura de comunicado")</span>
      </label>

      <fieldset className="space-y-2 text-sm">
        <legend className="mb-1 font-medium">Para quem?</legend>
        {(
          [
            ["conta", "Toda a equipe (todos os funcionários ativos)"],
            ["lojas", "Lojas específicas"],
            ["funcionarios", "Pessoas específicas"],
          ] as const
        ).map(([id, rotulo]) => (
          <label key={id} className="flex items-center gap-2">
            <input type="radio" checked={alvo === id} onChange={() => setAlvo(id)} />
            {rotulo}
          </label>
        ))}
        {alvo === "lojas" && (
          <div className="flex flex-wrap gap-3 pl-6">
            {(lojas.data ?? []).filter((l) => l.ativa).map((l) => (
              <label key={l.lojaid} className="flex items-center gap-2">
                <input type="checkbox" checked={lojasEscolhidas.includes(l.lojaid)} onChange={() => setLojas(alternar(lojasEscolhidas, l.lojaid))} />
                {l.nome}
              </label>
            ))}
          </div>
        )}
        {alvo === "funcionarios" && (
          <div className="grid gap-1 pl-6 sm:grid-cols-2">
            {(pessoas.data ?? []).filter((p) => p.ativo).map((p) => (
              <label key={p.funcionarioid} className="flex items-center gap-2">
                <input type="checkbox" checked={gente.includes(p.funcionarioid)} onChange={() => setGente(alternar(gente, p.funcionarioid))} />
                {p.nomecompleto}
              </label>
            ))}
          </div>
        )}
      </fieldset>
      <p className="text-xs text-muted-foreground">
        A lista de destinatários é fixada ao publicar (só funcionários ativos). Quem entrar depois pode ser incluído na
        tela do comunicado. Enquanto ninguém der ciência, dá para corrigir título, texto e pontos; depois, não.
      </p>
      <button type="submit" disabled={publicar.isPending} className="rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground disabled:opacity-60">
        {publicar.isPending ? "Publicando..." : "Publicar comunicado"}
      </button>
      {publicar.isError && <p className="text-sm text-destructive">{(publicar.error as Error).message}</p>}
    </form>
  );
}

/* ------------------------------------------------------------------ */
/* Detalhe: texto, destinatários e ciências                            */
/* ------------------------------------------------------------------ */

function Detalhe({ c, ciencias }: { c: Comunicado; ciencias: Ciencia[] }) {
  const qc = useQueryClient();
  const pessoas = usePessoas();
  const [aviso, setAviso] = useState<{ texto: string; grave: boolean } | null>(null);
  const [editando, setEditando] = useState(false);
  const [ed, setEd] = useState({ titulo: c.titulo, conteudo: c.conteudo, pontos: String(c.pontosporciencia) });
  const [incluir, setIncluir] = useState<number | "">("");
  const publicado = c.status === "Publicado";

  const master = useQuery({
    queryKey: ["sou-master"],
    queryFn: async () => (await supabase.rpc("sou_master")).data === true,
  });
  const fora = useQuery({
    queryKey: ["fora-do-comunicado", c.documentoid],
    enabled: publicado && c.alvo !== "funcionarios",
    queryFn: async () => {
      const { data, error } = await supabase.rpc("fora_do_comunicado", { p_documentoid: c.documentoid });
      if (error) throw error;
      return (data ?? []) as unknown as { funcionarioid: number; nome: string }[];
    },
  });

  const acao = useMutation({
    mutationFn: async (fazer: () => Promise<{ error: unknown }>) => {
      const { error } = await fazer();
      if (error) throw error;
    },
    onSuccess: () => {
      setAviso({ texto: "Salvo.", grave: false });
      setEditando(false);
      atualizarTudo(qc);
    },
    onError: (e) => setAviso({ texto: (e as Error).message, grave: true }),
  });
  const rpc = (nome: string, args: Record<string, unknown>) =>
    acao.mutate(() => supabase.rpc(nome as never, args as never) as unknown as Promise<{ error: unknown }>);

  async function recibo(assinaturaid: number) {
    const { data, error } = await supabase.rpc("recibo_ciencia", { p_assinaturaid: assinaturaid });
    if (error || !data) {
      setAviso({ texto: "Não foi possível gerar o recibo.", grave: true });
      return;
    }
    await pdfReciboCiencia(data as never);
  }

  const nome = new Map((pessoas.data ?? []).map((p) => [p.funcionarioid, p.nomecompleto]));
  const jaEstao = new Set(ciencias.map((s) => s.funcionarioid));
  const paraIncluir = (pessoas.data ?? []).filter((p) => p.ativo && !jaEstao.has(p.funcionarioid));
  const botao = "rounded-md border border-border px-3 py-1 text-sm";
  const ordenadas = [...ciencias].sort((a, b) => (nome.get(a.funcionarioid) ?? "").localeCompare(nome.get(b.funcionarioid) ?? ""));

  return (
    <div className="space-y-3 border-t border-border pt-3">
      {editando ? (
        <form
          onSubmit={(e) => {
            e.preventDefault();
            rpc("editar_comunicado", { p_documentoid: c.documentoid, p_titulo: ed.titulo, p_conteudo: ed.conteudo, p_pontos: Number(ed.pontos) });
          }}
          className="space-y-2"
        >
          <input value={ed.titulo} onChange={(e) => setEd({ ...ed, titulo: e.target.value })} className={`${campo} w-full`} />
          <textarea rows={6} value={ed.conteudo} onChange={(e) => setEd({ ...ed, conteudo: e.target.value })} className={`${campo} w-full`} />
          <input type="number" min={0} value={ed.pontos} onChange={(e) => setEd({ ...ed, pontos: e.target.value })} className={`${campo} w-24`} />
          <button type="submit" className="rounded-md bg-primary px-3 py-1 text-sm font-semibold text-primary-foreground">Salvar</button>
        </form>
      ) : (
        <p className="whitespace-pre-wrap text-sm">{c.conteudo}</p>
      )}

      <div className="flex flex-wrap gap-2">
        <button
          onClick={() =>
            pdfComunicado({
              titulo: c.titulo,
              conteudo: c.conteudo,
              publicadoem: c.datacriacao,
              para: c.alvo === "conta" ? "Toda a equipe" : c.alvo === "lojas" ? "Lojas escolhidas" : `${ciencias.length} pessoas`,
            })
          }
          className={botao}
        >
          PDF do comunicado
        </button>
        {publicado && !c.primeiracienciaem && (
          <button onClick={() => setEditando(!editando)} className={botao}>
            {editando ? "Cancelar edição" : "Editar"}
          </button>
        )}
        {publicado && (
          <button
            onClick={() =>
              window.confirm("Arquivar este comunicado? Ele deixa de aceitar ciências e destinatários, mas guarda o histórico e os recibos.") &&
              rpc("arquivar_comunicado", { p_documentoid: c.documentoid })
            }
            className={botao}
          >
            Arquivar
          </button>
        )}
      </div>

      {publicado && (fora.data ?? []).length > 0 && (
        <div className="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-accent px-3 py-2 text-sm text-accent">
          <span>
            {fora.data!.length} {fora.data!.length === 1 ? "funcionário ativo entrou" : "funcionários ativos entraram"} depois e não{" "}
            {fora.data!.length === 1 ? "está" : "estão"} neste comunicado: {fora.data!.map((p) => p.nome).join(", ")}.
          </span>
          <button
            onClick={() => rpc("incluir_destinatarios", { p_documentoid: c.documentoid, p_funcionarios: fora.data!.map((p) => p.funcionarioid) })}
            className="rounded-md bg-primary px-3 py-1 font-semibold text-primary-foreground"
          >
            Incluir
          </button>
        </div>
      )}

      {publicado && paraIncluir.length > 0 && (
        <div className="flex flex-wrap items-center gap-2">
          <select value={incluir} onChange={(e) => setIncluir(e.target.value === "" ? "" : Number(e.target.value))} className={`${campo} py-1`}>
            <option value="">Acrescentar pessoa...</option>
            {paraIncluir.map((p) => (
              <option key={p.funcionarioid} value={p.funcionarioid}>
                {p.nomecompleto}
              </option>
            ))}
          </select>
          <button
            disabled={incluir === ""}
            onClick={() => {
              rpc("incluir_destinatarios", { p_documentoid: c.documentoid, p_funcionarios: [incluir] });
              setIncluir("");
            }}
            className={`${botao} disabled:opacity-50`}
          >
            Acrescentar
          </button>
        </div>
      )}

      {aviso && <p className={`text-sm ${aviso.grave ? "text-destructive" : "text-sucesso"}`}>{aviso.texto}</p>}

      <div className="space-y-1">
        {ordenadas.map((s) => (
          <div key={s.assinaturaid} className="flex flex-wrap items-center justify-between gap-2 rounded-md border border-border px-3 py-2 text-sm">
            <span>
              {nome.get(s.funcionarioid) ?? "—"}
              {s.statusassinatura === "Ciente" ? (
                <span className="ml-2 text-xs text-sucesso">
                  ✓ ciente em {dataHoraBr(s.dataciencia!)} {s.origem === "gestor" ? "(registrado pelo gestor)" : ""}
                  {s.pontospagos > 0 && ` · +${s.pontospagos} pontos`}
                </span>
              ) : (
                <span className="ml-2 text-xs text-accent">
                  pendente{s.motivodesfazer ? ` · ciência desfeita: ${s.motivodesfazer}` : ""}
                </span>
              )}
            </span>
            <span className="flex gap-2">
              {s.statusassinatura === "Pendente" && publicado && (
                <button
                  onClick={() => rpc("registrar_ciencia", { p_assinaturaid: s.assinaturaid })}
                  className="rounded-md bg-primary px-3 py-1 text-xs font-semibold text-primary-foreground"
                >
                  Registrar ciência
                </button>
              )}
              {s.statusassinatura === "Ciente" && (
                <>
                  <button onClick={() => recibo(s.assinaturaid)} className="rounded-md border border-border px-2 py-1 text-xs">
                    Recibo (PDF)
                  </button>
                  {master.data && (
                    <button
                      onClick={() => {
                        const motivo = window.prompt("Por que a ciência está sendo desfeita? (os pontos são estornados)");
                        if (motivo === null) return;
                        if (!motivo.trim()) {
                          setAviso({ texto: "O motivo é obrigatório.", grave: true });
                          return;
                        }
                        rpc("desfazer_ciencia", { p_assinaturaid: s.assinaturaid, p_motivo: motivo.trim() });
                      }}
                      className="rounded-md border border-destructive px-2 py-1 text-xs text-destructive"
                    >
                      Desfazer
                    </button>
                  )}
                </>
              )}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}
