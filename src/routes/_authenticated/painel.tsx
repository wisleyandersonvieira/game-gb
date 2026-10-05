import { CHAVE_MENU } from "@/ui/pendencias";
import { createFileRoute } from "@tanstack/react-router";
import { useInfiniteQuery, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useMinhasPermissoes } from "@/ui/permissoes";
import { AvisoSemLoja, useLojaAtiva } from "@/lojas/loja-ativa";
import { FolgaDeHoje } from "@/painel/FolgaDeHoje";
import { FilaDoDia } from "@/painel/FilaDoDia";
import { Pagina } from "@/ui/Pagina";

export const Route = createFileRoute("/_authenticated/painel")({
  component: Quadro,
});

const BUCKET = "entregas";
/** O maior período do histórico (o banco também recusa acima disto). */
const MAXIMO_DE_DIAS = 93;

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

/** Uma linha como vem de quadro_validacao. */
type LinhaDoQuadro = {
  entregaid: number;
  tarefaid: number;
  statusvalidacao: string;
  dataenvio: string;
  dataaprovacao?: string | null;
  datarecusa?: string | null;
  dataestorno?: string | null;
  pontosganhos: number | null;
  observacao: string | null;
  motivorecusa?: string | null;
  motivoestorno?: string | null;
  pathfotoevidencia: string | null;
  fotoexpiradaem: string | null;
  /** A foto passou do prazo e o arquivo está na fila para ser apagado. */
  fotoaguardaremocaoem?: string | null;
  semhorafoto?: boolean;
  titulo: string | null;
  pontostarefa: number | null;
  nome: string | null;
};

type PaginaDoQuadro = { de: string; ate: string; temmais: boolean; pendentes: Entrega[]; historico: Entrega[] };

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
  /** Foto apagada pelo prazo da conta (a entrega e os pontos continuam valendo). */
  fotoExpirada: boolean;
  /** Passou do prazo e está sendo apagada: não aparece, mas ainda não saiu. */
  fotoSendoApagada: boolean;
  /** O arquivo não trazia a hora em que a foto foi tirada. Quem decide é você. */
  semHoraDaFoto: boolean;
};

function Quadro() {
  const { lojas, lojaAtiva, loja, carregando } = useLojaAtiva();
  // O dia da Fila: null = hoje (ao vivo). Dia que passou é só leitura.
  const [dia, setDia] = useState<string | null>(null);

  if (carregando) {
    return (
      <Pagina>
        <p className="text-muted-foreground">Carregando...</p>
      </Pagina>
    );
  }

  if (lojas.length === 0 || lojaAtiva === null) {
    return (
      <Pagina titulo="Quadro">
        <AvisoSemLoja />
      </Pagina>
    );
  }

  return (
    <Pagina
      titulo="Quadro"
      acoes={
        <p className="text-sm text-muted-foreground">
          Loja <strong className="text-foreground">{loja?.nome}</strong>
        </p>
      }
    >
      <FilaDoDia lojaid={lojaAtiva} dia={dia} aoMudarDia={setDia} />
      {dia === null ? (
        <>
          <RegistrarEntrega lojaid={lojaAtiva} />
          <FolgaDeHoje lojaid={lojaAtiva} />
        </>
      ) : (
        <p className="rounded-xl border border-dashed border-border p-4 text-sm text-muted-foreground">
          "Registrar entrega" e as tarefas de quem está de folga só valem para hoje: não se entrega nem se passa
          tarefa num dia que já passou.{" "}
          <button type="button" className="underline" onClick={() => setDia(null)}>
            Voltar para hoje
          </button>
        </p>
      )}
      <Validacao lojaid={lojaAtiva} />
    </Pagina>
  );
}

/* ------------------------------------------------------------------ */
/* Registrar entrega                                                    */
/* ------------------------------------------------------------------ */

function RegistrarEntrega({ lojaid }: { lojaid: number }) {
  const qc = useQueryClient();
  const [atribuicaoid, setAtribuicaoid] = useState<number | "">("");
  const [observacao, setObservacao] = useState("");
  const souMaster = useMinhasPermissoes().data?.master === true;
  const [foto, setFoto] = useState<File | null>(null);
  const [jaAprovada, setJaAprovada] = useState(false);
  const [recado, setRecado] = useState<string | null>(null);
  // Nasce FECHADO. A lista só é buscada quando abre: uma consulta a menos ao
  // abrir o Quadro. Se der erro, fica aberto, com o que foi digitado.
  const [aberto, setAberto] = useState(false);

  const opcoes = useQuery({
    queryKey: ["para-entregar", lojaid],
    enabled: aberto,
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
      // A bolinha do Quadro no menu.
      qc.invalidateQueries({ queryKey: CHAVE_MENU });
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
      <button
        type="button"
        onClick={() => setAberto((v) => !v)}
        className="flex w-full items-center justify-between text-left"
        aria-expanded={aberto}
      >
        <span className="text-sm font-semibold">Registrar entrega</span>
        <span className="text-muted-foreground">{aberto ? "▲" : "▼"}</span>
      </button>
      {aberto && (<>
      <p className="text-xs text-muted-foreground">
        Aparecem só as tarefas que caem hoje ou estão atrasadas, e que ainda não foram entregues.
      </p>

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

        {/* Enviar foto é só do dono da conta (o gerente vê as fotos, decisão 1). */}
        {souMaster && (
        <label className="flex min-w-0 flex-wrap items-center gap-2 text-sm text-muted-foreground">
          Foto (opcional):
          <input
            type="file"
            accept="image/*"
            onChange={(e) => setFoto(e.target.files?.[0] ?? null)}
            className="min-w-0 max-w-full text-sm"
          />
        </label>
        )}

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
      </>)}
    </form>
  );
}

/* ------------------------------------------------------------------ */
/* Validação: Pendentes · Aprovadas · Recusadas                        */
/* ------------------------------------------------------------------ */

function Validacao({ lojaid }: { lojaid: number }) {
  const qc = useQueryClient();
  const [aviso, setAviso] = useState<{ texto: string; grave: boolean } | null>(null);
  // "Só as sem hora da foto": para conferir de uma vez as que pedem atenção.
  const [soSemHora, setSoSemHora] = useState(false);

  // O período do HISTÓRICO. Vazio = o padrão do banco (os 7 dias até ontem).
  const [periodo, setPeriodo] = useState<{ de: string; ate: string } | null>(null);
  const [digitado, setDigitado] = useState<{ de: string; ate: string } | null>(null);
  const [erroPeriodo, setErroPeriodo] = useState<string | null>(null);

  // UMA consulta traz pendentes + a página do histórico, com títulos e nomes
  // (quadro_validacao). Depois, só os links das fotos. Antes eram duas
  // rodadas: as entregas, e depois tarefas, nomes e fotos.
  const quadro = useInfiniteQuery({
    queryKey: ["quadro", lojaid, periodo?.de ?? null, periodo?.ate ?? null],
    initialPageParam: 0,
    getNextPageParam: (ultima: PaginaDoQuadro, todas: PaginaDoQuadro[]) => (ultima.temmais ? todas.length * 50 : undefined),
    queryFn: async ({ pageParam }): Promise<PaginaDoQuadro> => {
      const { data, error } = await supabase.rpc("quadro_validacao", {
        p_lojaid: lojaid,
        p_de: periodo?.de ?? undefined,
        p_ate: periodo?.ate ?? undefined,
        p_offset: pageParam,
      });
      if (error) throw error;
      const r = data as unknown as {
        de: string; ate: string; temmais: boolean;
        pendentes: LinhaDoQuadro[]; historico: LinhaDoQuadro[];
      };
      // Os pendentes vêm só na primeira página: nas seguintes, só o histórico.
      const linhas = [...(pageParam === 0 ? r.pendentes : []), ...r.historico];
      const caminhos = linhas.map((l) => l.pathfotoevidencia).filter((c): c is string => !!c);
      // Link temporário (1 hora). O bucket é privado: não há link público.
      const assinadas = caminhos.length > 0
        ? await supabase.storage.from(BUCKET).createSignedUrls(caminhos, 3600)
        : { data: [] as { path: string | null; signedUrl: string }[] };
      const links = new Map<string, string>();
      for (const a of assinadas.data ?? []) if (a.path && a.signedUrl) links.set(a.path, a.signedUrl);
      const montar = (l: LinhaDoQuadro): Entrega => ({
        ...l,
        dataaprovacao: l.dataaprovacao ?? null,
        datarecusa: l.datarecusa ?? null,
        dataestorno: l.dataestorno ?? null,
        motivorecusa: l.motivorecusa ?? null,
        motivoestorno: l.motivoestorno ?? null,
        titulo: l.titulo ?? `Tarefa ${l.tarefaid}`,
        pontosDaTarefa: l.pontostarefa ?? 0,
        nome: l.nome ?? "—",
        foto: l.pathfotoevidencia ? (links.get(l.pathfotoevidencia) ?? null) : null,
        fotoExpirada: l.fotoexpiradaem !== null,
        fotoSendoApagada: l.fotoexpiradaem === null && !!l.fotoaguardaremocaoem,
        // Só PENDENTE carrega o aviso: nas decididas, a decisão já foi tomada.
        semHoraDaFoto: l.statusvalidacao === "Pendente" && l.semhorafoto === true,
      });
      return {
        de: r.de, ate: r.ate, temmais: r.temmais,
        pendentes: pageParam === 0 ? r.pendentes.map(montar) : [],
        historico: r.historico.map(montar),
      };
    },
  });
  const paginas = quadro.data?.pages ?? [];
  const primeira = paginas[0];

  function carregarPeriodo() {
    const p = digitado ?? (primeira ? { de: primeira.de, ate: primeira.ate } : null);
    if (!p?.de || !p?.ate) return setErroPeriodo("Escolha a data inicial e a final.");
    if (p.de > p.ate) return setErroPeriodo("A data inicial é depois da final.");
    const dias = (Date.parse(`${p.ate}T00:00:00Z`) - Date.parse(`${p.de}T00:00:00Z`)) / 86_400_000;
    if (dias > MAXIMO_DE_DIAS - 1) return setErroPeriodo(`Escolha um período de no máximo ${MAXIMO_DE_DIAS} dias.`);
    setErroPeriodo(null);
    setPeriodo(p);
  }

  function atualizar() {
    qc.invalidateQueries({ queryKey: ["quadro", lojaid] });
    qc.invalidateQueries({ queryKey: ["para-entregar", lojaid] });
    qc.invalidateQueries({ queryKey: ["equipe"] });
    qc.invalidateQueries({ queryKey: ["ranking"] });
    // A bolinha do Quadro no menu: aprovou, recusou ou estornou, ela anda já.
    qc.invalidateQueries({ queryKey: CHAVE_MENU });
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

  const todosPendentes = primeira?.pendentes ?? [];
  const pendentes = todosPendentes.filter((e) => !soSemHora || e.semHoraDaFoto);
  const semHora = todosPendentes.filter((e) => e.semHoraDaFoto).length;
  const historico = paginas.flatMap((p) => p.historico);
  const aprovadas = historico.filter((e) => e.statusvalidacao === "Aprovada");
  const recusadas = historico.filter((e) => e.statusvalidacao === "Recusada" || e.statusvalidacao === "Estornada");
  const deBr = (d?: string) => (d ? d.split("-").reverse().join("/") : "");

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

      {/* O período vale só para Aprovadas e Recusadas. Pendentes é lista de
          coisa a fazer: mostra TUDO o que espera, de qualquer dia. */}
      <div className="flex flex-wrap items-end gap-2 rounded-lg border border-border bg-card px-3 py-2 text-sm">
        <span className="font-medium">Histórico (aprovadas e recusadas), pela data da entrega:</span>
        <label className="flex items-center gap-1">
          de
          <input
            type="date"
            value={digitado?.de ?? primeira?.de ?? ""}
            onChange={(e) => setDigitado({ de: e.target.value, ate: digitado?.ate ?? primeira?.ate ?? "" })}
            className={campo}
          />
        </label>
        <label className="flex items-center gap-1">
          até
          <input
            type="date"
            value={digitado?.ate ?? primeira?.ate ?? ""}
            onChange={(e) => setDigitado({ de: digitado?.de ?? primeira?.de ?? "", ate: e.target.value })}
            className={campo}
          />
        </label>
        <button onClick={carregarPeriodo} className="rounded-md border border-border px-3 py-2">
          Carregar
        </button>
        <span className="text-xs text-muted-foreground">
          Padrão: os 7 dias até ontem (o de hoje está em "Feitas hoje"). Até {MAXIMO_DE_DIAS} dias, 50 por vez.
        </span>
        {erroPeriodo && <span className="w-full text-destructive">{erroPeriodo}</span>}
      </div>

      <div className="grid gap-4 md:grid-cols-3">
        <Coluna titulo="Pendentes (todas)" quantidade={pendentes.length}>
          {semHora > 0 && (
            <label className="flex items-center gap-2 rounded-md border border-border px-3 py-2 text-xs">
              <input type="checkbox" checked={soSemHora} onChange={(ev) => setSoSemHora(ev.target.checked)} />
              Mostrar só as sem hora da foto ({semHora})
            </label>
          )}
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

        <Coluna titulo={`Aprovadas (${deBr(primeira?.de)} a ${deBr(primeira?.ate)})`} quantidade={aprovadas.length}>
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

        <Coluna titulo={`Recusadas e estornadas (${deBr(primeira?.de)} a ${deBr(primeira?.ate)})`} quantidade={recusadas.length}>
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
      {quadro.hasNextPage && (
        <button
          onClick={() => void quadro.fetchNextPage()}
          disabled={quadro.isFetchingNextPage}
          className="w-full rounded-lg border border-border px-4 py-2 text-sm disabled:opacity-50"
        >
          {quadro.isFetchingNextPage ? "Carregando..." : "Carregar mais 50 do histórico"}
        </button>
      )}
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
      {!e.foto && e.fotoSendoApagada && (
        <p className="rounded-md border border-dashed border-border px-3 py-2 text-xs text-muted-foreground">
          Foto vencida: passou do prazo de guarda e está sendo apagada. A entrega e os pontos continuam valendo.
        </p>
      )}
      {!e.foto && e.fotoExpirada && (
        <p className="rounded-md border border-dashed border-border px-3 py-2 text-xs text-muted-foreground">
          Foto removida por tempo. A entrega e os pontos continuam valendo.
        </p>
      )}
      {e.semHoraDaFoto && (
        <p className="rounded-md border border-perigo/40 bg-perigo-soft px-3 py-2 text-xs font-medium text-perigo">
          Sem hora da foto: o celular não gravou quando a foto foi tirada. Confira antes de aprovar.
        </p>
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
