import { createFileRoute } from "@tanstack/react-router";
import { useInfiniteQuery, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { AvisoSemLoja, useLojaAtiva } from "@/lojas/loja-ativa";
import { Pagina } from "@/ui/Pagina";
import { rotinaDaTarefa } from "@/tarefas/rotinas";

export const Route = createFileRoute("/_authenticated/tarefas")({
  component: Tarefas,
});

// 1 = domingo ... 7 = sábado, igual ao resto do sistema.
const DIAS_SEMANA = [
  { valor: 1, curto: "Dom", nome: "Domingo" },
  { valor: 2, curto: "Seg", nome: "Segunda" },
  { valor: 3, curto: "Ter", nome: "Terça" },
  { valor: 4, curto: "Qua", nome: "Quarta" },
  { valor: 5, curto: "Qui", nome: "Quinta" },
  { valor: 6, curto: "Sex", nome: "Sexta" },
  { valor: 7, curto: "Sáb", nome: "Sábado" },
];

const campo =
  "rounded-lg border border-border bg-background px-3 py-2 text-sm placeholder:text-muted-foreground";

const hojeEmSaoPaulo = () =>
  new Intl.DateTimeFormat("en-CA", { timeZone: "America/Sao_Paulo" }).format(new Date());

function Tarefas() {
  const { lojas, lojaAtiva, loja, carregando } = useLojaAtiva();
  const [aba, setAba] = useState<"catalogo" | "atribuicoes">("catalogo");

  if (carregando) {
    return (
      <Pagina>
        <p className="text-muted-foreground">Carregando...</p>
      </Pagina>
    );
  }

  if (lojas.length === 0) {
    return (
      <Pagina titulo="Tarefas">
        <AvisoSemLoja />
      </Pagina>
    );
  }

  return (
    <Pagina titulo="Tarefas">

      <div className="flex gap-2 border-b border-border">
        {(
          [
            ["catalogo", "Catálogo"],
            ["atribuicoes", "Atribuições da loja"],
          ] as const
        ).map(([id, rotulo]) => (
          <button
            key={id}
            onClick={() => setAba(id)}
            className={`rounded-t-lg px-4 py-2 text-sm font-medium ${
              aba === id ? "bg-card text-foreground" : "text-muted-foreground"
            }`}
          >
            {rotulo}
          </button>
        ))}
      </div>

      {aba === "catalogo" ? (
        <Catalogo />
      ) : (
        // A chave é a loja: trocar a loja no topo recomeça a aba do zero, e
        // nada (pessoa marcada, filtro de colaborador) sobra da loja anterior.
        <Atribuicoes key={lojaAtiva!} lojaid={lojaAtiva!} nomeDaLoja={loja?.nome ?? ""} />
      )}
    </Pagina>
  );
}

/* ------------------------------------------------------------------ */
/* Catálogo: o que existe para fazer, e em quais lojas cada uma vale   */
/* ------------------------------------------------------------------ */

const TAREFA_VAZIA = { titulo: "", descricao: "", pontos: 10, setor: "" };

type TarefaDoCatalogo = {
  tarefaid: number;
  titulo: string;
  descricao: string | null;
  pontos: number;
  setor: string | null;
  ativa: boolean;
  sistema: string | null;
  lojas: number[];
};

/** Sem filtro: só as 5 mais recentes. Com filtro e no "carregar mais": 50 por vez. */
const PRIMEIRAS_TAREFAS = 5;
const TAREFAS_POR_VEZ = 50;

function Catalogo() {
  const qc = useQueryClient();
  const { lojas, lojaAtiva } = useLojaAtiva();
  // O formulário começa fechado: abre em "Nova tarefa" ou em "Editar".
  const [formAberto, setFormAberto] = useState(false);
  const [form, setForm] = useState(TAREFA_VAZIA);
  const [lojasEscolhidas, setLojasEscolhidas] = useState<number[]>([]);
  const [editando, setEditando] = useState<number | null>(null);
  // O código interno da tarefa em edição: diz se alguma rotina a usa.
  const [codigoEditando, setCodigoEditando] = useState<string | null>(null);

  // Filtros da lista. A loja começa na do topo e ACOMPANHA o topo quando ele
  // muda; "todas" mostra todas as lojas.
  const [lojaFiltro, setLojaFiltro] = useState<number | "todas">(lojaAtiva ?? "todas");
  useEffect(() => {
    if (lojaAtiva !== null) setLojaFiltro(lojaAtiva);
  }, [lojaAtiva]);
  const [inativas, setInativas] = useState(false);
  const [buscaDigitada, setBuscaDigitada] = useState("");
  const [busca, setBusca] = useState("");
  // A busca pergunta ao banco quando a pessoa para de digitar, não a cada letra.
  useEffect(() => {
    const t = setTimeout(() => setBusca(buscaDigitada.trim()), 400);
    return () => clearTimeout(t);
  }, [buscaDigitada]);
  const semFiltro = lojaFiltro === lojaAtiva && !inativas && busca === "";

  // UMA consulta: a lista já filtrada, com as lojas de cada tarefa (antes eram
  // duas — todas as tarefas e todos os vínculos — e o filtro era no aparelho).
  const catalogo = useInfiniteQuery({
    queryKey: ["catalogo-tarefas", lojaFiltro, inativas, busca],
    initialPageParam: 0,
    queryFn: async ({ pageParam }) => {
      const { data, error } = await supabase.rpc("catalogo_de_tarefas", {
        ...(lojaFiltro !== "todas" ? { p_lojaid: lojaFiltro } : {}),
        p_inativas: inativas,
        ...(busca ? { p_busca: busca } : {}),
        p_limite: pageParam === 0 && semFiltro ? PRIMEIRAS_TAREFAS : TAREFAS_POR_VEZ,
        p_offset: pageParam,
      });
      if (error) throw error;
      return data as unknown as { tarefas: TarefaDoCatalogo[]; temmais: boolean };
    },
    getNextPageParam: (ultima, todas) =>
      ultima.temmais ? todas.reduce((n, p) => n + p.tarefas.length, 0) : undefined,
  });

  function limparFiltros() {
    setLojaFiltro(lojaAtiva ?? "todas");
    setInativas(false);
    setBuscaDigitada("");
    setBusca("");
  }

  function limpar() {
    setForm(TAREFA_VAZIA);
    setLojasEscolhidas([]);
    setEditando(null);
    setCodigoEditando(null);
    setFormAberto(false);
  }

  async function sincronizarLojas(tarefaid: number, escolhidas: number[]) {
    if (escolhidas.length > 0) {
      const { error } = await supabase.from("tarefaslojas").upsert(
        escolhidas.map((lojaid) => ({ tarefaid, lojaid, ativo: true })),
        { onConflict: "tarefaid,lojaid" },
      );
      if (error) throw error;
    }
    const desativar = supabase.from("tarefaslojas").update({ ativo: false }).eq("tarefaid", tarefaid);
    const { error } =
      escolhidas.length > 0
        ? await desativar.not("lojaid", "in", `(${escolhidas.join(",")})`)
        : await desativar;
    if (error) throw error;
  }

  const salvar = useMutation({
    mutationFn: async () => {
      // Tarefa que PAGA sozinha: com pontos, só salva depois de você
      // confirmar, lendo a conta com todas as letras.
      const pontosNovos = Number(form.pontos);
      const pagaSozinha = rotinaDaTarefa(codigoEditando)?.pagaSemValidacao;
      if (pagaSozinha && tetoDaConta !== null && pontosNovos > tetoDaConta) {
        throw new Error(`O máximo permitido nesta conta é ${tetoDaConta} pontos por ciência (Configurações).`);
      }
      if (pagaSozinha && pontosNovos > 0) {
        const ok = confirm(
          `ATENÇÃO: ESTA TAREFA PAGA PONTOS SOZINHA.\n\n${pagaSozinha(pontosNovos, tetoDaConta)}\n\nSalvar com ${pontosNovos} pontos?`,
        );
        if (!ok) return false;
      }
      const dados = {
        titulo: form.titulo.trim(),
        descricao: form.descricao.trim() || null,
        pontos: Number(form.pontos),
        setor: form.setor.trim() || null,
      };
      let tarefaid = editando;
      if (tarefaid === null) {
        const { data, error } = await supabase
          .from("tarefas")
          .insert(dados)
          .select("tarefaid")
          .single();
        if (error) throw error;
        tarefaid = data.tarefaid;
      } else {
        const { error } = await supabase.from("tarefas").update(dados).eq("tarefaid", tarefaid);
        if (error) throw error;
      }
      await sincronizarLojas(tarefaid, lojasEscolhidas);
      return true;
    },
    onSuccess: (salvou) => {
      if (!salvou) return;
      limpar();
      qc.invalidateQueries({ queryKey: ["catalogo-tarefas"] });
      qc.invalidateQueries({ queryKey: ["atribuicoes"] });
    },
  });

  const alternarAtiva = useMutation({
    mutationFn: async ({ tarefaid, ativa, codigo }: { tarefaid: number; ativa: boolean; codigo: string | null }) => {
      // Uma rotina usa esta tarefa: você decide com a informação na tela.
      const rotina = rotinaDaTarefa(codigo);
      if (!ativa && rotina) {
        const ok = confirm(
          `Esta tarefa é usada por uma rotina automática.\n\n${rotina.rotina}\n\nSe desativar: ${rotina.aoDesativar}\n\nDesativar mesmo assim?`,
        );
        if (!ok) return;
      }
      const { error } = await supabase.from("tarefas").update({ ativa }).eq("tarefaid", tarefaid);
      if (error) throw error;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["catalogo-tarefas"] });
      qc.invalidateQueries({ queryKey: ["tarefas-da-loja"] });
    },
  });

  const lista = (catalogo.data?.pages ?? []).flatMap((p) => p.tarefas);
  const rotinaEmEdicao = rotinaDaTarefa(codigoEditando);

  // O teto de pontos por ciência da conta: só quando se edita a tarefa que
  // paga sozinha (abrir a tela não ganha consulta nenhuma).
  const teto = useQuery({
    queryKey: ["teto-pontos-ciencia"],
    enabled: !!rotinaEmEdicao?.pagaSemValidacao,
    queryFn: async () => {
      const { data } = await supabase.from("configuracoes").select("valor").eq("chave", "MAX_PONTOS_CIENCIA").maybeSingle();
      return data?.valor ? Number(data.valor) : 50;
    },
  });
  const tetoDaConta = teto.data ?? null;
  const nomeDaLoja = (id: number) => lojas.find((l) => l.lojaid === id)?.nome ?? `Loja ${id}`;

  return (
    <div className="space-y-4">
      {!formAberto && (
        <button
          onClick={() => {
            limpar();
            setFormAberto(true);
          }}
          className="rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground"
        >
          Nova tarefa
        </button>
      )}

      {formAberto && (
      <form
        onSubmit={(e) => {
          e.preventDefault();
          salvar.mutate();
        }}
        className="space-y-3 rounded-xl border border-border bg-card p-4"
      >
        <p className="text-sm font-semibold">
          {editando === null ? "Nova tarefa" : "Editando tarefa"}
        </p>

        {rotinaEmEdicao?.pagaSemValidacao && (
          <div role="alert" className="space-y-2 rounded-xl border-4 border-destructive bg-destructive/10 p-4 text-destructive">
            <p className="text-lg font-bold">⚠ Esta tarefa paga pontos sozinha, sem validação</p>
            <p className="text-base font-semibold">
              {Number(form.pontos) > 0
                ? rotinaEmEdicao.pagaSemValidacao(Number(form.pontos), tetoDaConta)
                : `Com 0 ponto ela não paga nada. Se você colocar pontos, cada ciência de comunicado novo (publicado com o campo de pontos em branco) passa a pagar esses pontos AUTOMATICAMENTE, SEM VALIDAÇÃO de ninguém.${tetoDaConta !== null ? ` O máximo permitido nesta conta é ${tetoDaConta} pontos.` : ""}`}
            </p>
          </div>
        )}

        <div className="grid gap-3 md:grid-cols-3">
          <input
            required
            placeholder="Título"
            value={form.titulo}
            onChange={(e) => setForm({ ...form, titulo: e.target.value })}
            className={`${campo} md:col-span-2`}
          />
          <label className="flex items-center gap-2 text-sm text-muted-foreground">
            Pontos:
            <input
              required
              type="number"
              min={0}
              value={form.pontos}
              onChange={(e) => setForm({ ...form, pontos: Number(e.target.value) })}
              className={`${campo} w-24`}
            />
          </label>
          <input
            placeholder="Setor"
            value={form.setor}
            onChange={(e) => setForm({ ...form, setor: e.target.value })}
            className={campo}
          />
          <input
            placeholder="Descrição"
            value={form.descricao}
            onChange={(e) => setForm({ ...form, descricao: e.target.value })}
            className={`${campo} md:col-span-2`}
          />
        </div>

        {rotinaEmEdicao && (
          <div className="space-y-1 rounded-lg border border-azul/40 bg-azul-soft px-3 py-2 text-xs text-azul">
            <p>{rotinaEmEdicao.rotina}</p>
            <p className="font-medium">{rotinaEmEdicao.pontos(Number(form.pontos) || 0)}</p>
            <p>Pode renomear à vontade: a rotina acha a tarefa pelo código interno, não pelo nome.</p>
          </div>
        )}

        <fieldset className="space-y-2">
          <legend className="text-sm text-muted-foreground">
            Vale em quais lojas? (pode marcar mais de uma)
          </legend>
          <div className="flex flex-wrap gap-3">
            {lojas.map((l) => (
              <label key={l.lojaid} className="flex items-center gap-2 text-sm">
                <input
                  type="checkbox"
                  checked={lojasEscolhidas.includes(l.lojaid)}
                  onChange={(e) =>
                    setLojasEscolhidas((atual) =>
                      e.target.checked
                        ? [...atual, l.lojaid]
                        : atual.filter((id) => id !== l.lojaid),
                    )
                  }
                />
                {l.nome}
              </label>
            ))}
          </div>
        </fieldset>

        <div className="flex flex-wrap gap-2">
          <button
            type="submit"
            disabled={salvar.isPending}
            className="rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground disabled:opacity-60"
          >
            {salvar.isPending ? "Salvando..." : editando === null ? "Adicionar" : "Salvar"}
          </button>
          <button
            type="button"
            onClick={limpar}
            className="rounded-lg border border-border px-4 py-2 text-sm"
          >
            Cancelar
          </button>
        </div>

        {salvar.isError && (
          <p className="text-sm text-destructive">{(salvar.error as Error).message}</p>
        )}
      </form>
      )}

      <div className="flex flex-wrap items-end gap-3 rounded-xl border border-border bg-card p-3">
        <label className="space-y-1 text-sm">
          <span className="block text-muted-foreground">Buscar pelo nome</span>
          <input
            value={buscaDigitada}
            onChange={(e) => setBuscaDigitada(e.target.value)}
            placeholder="Ex.: vitrine"
            className={campo}
          />
        </label>
        <label className="space-y-1 text-sm">
          <span className="block text-muted-foreground">Loja</span>
          <select
            value={lojaFiltro}
            onChange={(e) => setLojaFiltro(e.target.value === "todas" ? "todas" : Number(e.target.value))}
            className={campo}
          >
            <option value="todas">Todas as lojas</option>
            {lojas.map((l) => (
              <option key={l.lojaid} value={l.lojaid}>
                {l.nome}
              </option>
            ))}
          </select>
        </label>
        <label className="flex items-center gap-2 pb-2 text-sm text-muted-foreground">
          <input type="checkbox" checked={inativas} onChange={(e) => setInativas(e.target.checked)} />
          Mostrar também as inativas
        </label>
        <button type="button" onClick={limparFiltros} className="rounded-lg border border-border px-3 py-2 text-sm">
          Limpar filtros
        </button>
        <p className="w-full text-xs text-muted-foreground">
          {semFiltro
            ? `As ${PRIMEIRAS_TAREFAS} tarefas ativas cadastradas por último nesta loja. Busque pelo nome para achar uma mais antiga.`
            : `${TAREFAS_POR_VEZ} por vez, das mais recentes para as mais antigas.`}
        </p>
      </div>

      <div className="space-y-2">
        {catalogo.isLoading && <p className="text-muted-foreground">Carregando...</p>}
        {catalogo.isError && (
          <p className="text-sm text-destructive">{(catalogo.error as Error).message}</p>
        )}

        {lista.map((t) => (
          <div
            key={t.tarefaid}
            className="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-border bg-card px-4 py-3"
          >
            <div className="min-w-0">
              <p className="font-medium">
                {t.titulo}
                {!t.ativa && (
                  <span className="ml-2 rounded-md border border-border px-2 py-0.5 text-xs font-normal text-muted-foreground">
                    desativada
                  </span>
                )}
              </p>
              <p className="text-sm text-muted-foreground">
                {t.pontos} pontos
                {t.setor && ` · ${t.setor}`}
                {t.lojas.length > 0 && ` · ${t.lojas.map(nomeDaLoja).join(", ")}`}
              </p>
            </div>

            <div className="flex items-center gap-2">
              <button
                onClick={() => {
                  setEditando(t.tarefaid);
                  setForm({
                    titulo: t.titulo,
                    descricao: t.descricao ?? "",
                    pontos: t.pontos,
                    setor: t.setor ?? "",
                  });
                  setLojasEscolhidas(t.lojas);
                  setCodigoEditando(t.sistema);
                  setFormAberto(true);
                }}
                className="rounded-md border border-border px-3 py-1 text-sm"
              >
                Editar
              </button>
              <button
                onClick={() => alternarAtiva.mutate({ tarefaid: t.tarefaid, ativa: !t.ativa, codigo: t.sistema })}
                className="rounded-md border border-border px-3 py-1 text-sm"
              >
                {t.ativa ? "Desativar" : "Reativar"}
              </button>
            </div>
          </div>
        ))}

        {catalogo.hasNextPage && (
          <button
            onClick={() => catalogo.fetchNextPage()}
            disabled={catalogo.isFetchingNextPage}
            className="rounded-lg border border-border px-4 py-2 text-sm disabled:opacity-60"
          >
            {catalogo.isFetchingNextPage ? "Carregando..." : `Carregar mais ${TAREFAS_POR_VEZ}`}
          </button>
        )}

        {!catalogo.isLoading && lista.length === 0 && (
          <p className="text-sm text-muted-foreground">
            {semFiltro ? "Nenhuma tarefa ativa nesta loja ainda." : "Nenhuma tarefa com esse filtro."}
          </p>
        )}
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Atribuições: quem faz o quê, nesta loja                             */
/* ------------------------------------------------------------------ */

/** "15:00:00" vira "15h"; "15:30:00" vira "15h30". */
export function horaCurta(hora: string): string {
  const [h, m] = hora.split(":");
  return m && m !== "00" ? `${h}h${m}` : `${h}h`;
}

/** Uma linha da lista, como vem de atribuicoes_da_loja (já agrupada). */
type Linha = {
  ids: number[];
  tarefaid: number;
  titulo: string | null;
  funcionarioid: number | null;
  nome: string | null;
  compartilhada: boolean;
  candidatos: string[] | null;
  horariodisparo: string | null;
  tipofrequencia: string;
  dias: number[];
  valor: number | null;
  dataagendamento: string | null;
  /** Hora local da empresa a partir da qual a tarefa entra na fila. */
  disponivelapartir: string | null;
  datafimvigencia: string | null;
  criadaem: string | null;
  /** dd/mm/aaaa, no fuso da conta (vem do banco). */
  criadaemdia: string | null;
};

type PaginaDeAtribuicoes = { linhas: Linha[]; temmais: boolean };

/** O filtro aplicado. "todos" / "missao" / o id de uma pessoa. */
type Filtro = { de: string; ate: string; tarefaid: string; quem: string };
const SEM_FILTRO: Filtro = { de: "", ate: "", tarefaid: "", quem: "todos" };
const MAXIMO_DE_DIAS = 366;
/** Sem filtro, as 5 mais recentes; "carregar mais" e com filtro, 50 por vez. */
const PRIMEIRAS = 5;
const POR_VEZ = 50;

function quemFaz(l: Linha) {
  if (l.funcionarioid) return l.nome ?? "—";
  if (l.compartilhada) return `👥 ${(l.candidatos ?? []).join(", ")} (a primeira que pegar)`;
  return `🚨 Missão da equipe${l.horariodisparo ? ` · ${l.horariodisparo.slice(0, 5)}` : ""}`;
}

function Atribuicoes({ lojaid, nomeDaLoja }: { lojaid: number; nomeDaLoja: string }) {
  const qc = useQueryClient();
  const [tarefaid, setTarefaid] = useState<number | "">("");
  // Quem faz. Uma pessoa = tarefa com dono, como sempre foi. Várias = UMA
  // tarefa compartilhada, que a primeira a pegar leva. Nenhuma + horário =
  // missão da equipe, aberta a toda a loja.
  const [selecionados, setSelecionados] = useState<number[]>([]);
  const [missao, setMissao] = useState(false);
  const [horarioMissao, setHorarioMissao] = useState("10:00");
  // "Disponível a partir de": vazio = o dia todo, como sempre foi.
  const [disponivelApartir, setDisponivelApartir] = useState("");
  const [frequencia, setFrequencia] = useState("Unica");
  const [data, setData] = useState(hojeEmSaoPaulo());
  const [diasSemana, setDiasSemana] = useState<number[]>([]);
  const [diaMes, setDiaMes] = useState(1);
  const [mostrarEncerradas, setMostrarEncerradas] = useState(false);

  // As tarefas que valem nesta loja, numa ida só (o vínculo traz a tarefa
  // junto). Vêm também as desativadas: servem para FILTRAR a lista; para
  // atribuir, só as ativas.
  const opcoesTarefas = useQuery({
    queryKey: ["tarefas-da-loja", lojaid],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("tarefaslojas")
        .select("tarefas!inner(tarefaid, titulo, pontos, ativa)")
        .eq("lojaid", lojaid)
        .eq("ativo", true);
      if (error) throw error;
      type Tarefa = { tarefaid: number; titulo: string; pontos: number; ativa: boolean };
      const tarefas = (data ?? [])
        .map((v) => (v as unknown as { tarefas: Tarefa }).tarefas)
        .filter((t): t is Tarefa => !!t);
      tarefas.sort((a, b) => a.titulo.localeCompare(b.titulo, "pt-BR"));
      return tarefas;
    },
  });

  // Só quem trabalha nesta loja, com vínculo ativo.
  const opcoesFuncionarios = useQuery({
    queryKey: ["funcionarios-da-loja", lojaid],
    queryFn: async () => {
      // Uma ida só: o vínculo traz a pessoa junto. Antes eram duas em fila
      // (buscar os vínculos, esperar, buscar as pessoas). O "!inner" e o
      // filtro funcionarios.ativo mantêm exatamente a mesma regra de antes:
      // vínculo ativo NESTA loja E pessoa ativa.
      const { data, error } = await supabase
        .from("funcionarioslojas")
        .select("funcionarios!inner(funcionarioid, nomecompleto)")
        .eq("lojaid", lojaid)
        .eq("ativo", true)
        .eq("funcionarios.ativo", true);
      if (error) throw error;

      type Pessoa = { funcionarioid: number; nomecompleto: string };
      const pessoas = (data ?? [])
        .map((v) => (v as unknown as { funcionarios: Pessoa }).funcionarios)
        .filter((p): p is Pessoa => !!p);
      pessoas.sort((a, b) => a.nomecompleto.localeCompare(b.nomecompleto, "pt-BR"));
      return pessoas;
    },
  });

  // O filtro em digitação e o filtro aplicado (só muda no botão).
  const [rascunho, setRascunho] = useState<Filtro>(SEM_FILTRO);
  const [filtro, setFiltro] = useState<Filtro>(SEM_FILTRO);
  const [erroFiltro, setErroFiltro] = useState<string | null>(null);
  const filtrando = filtro.de !== "" || filtro.tarefaid !== "" || filtro.quem !== "todos";

  // Uma consulta só: a lista já vem agrupada, com o nome da tarefa, de quem
  // faz e de quem pode pegar (antes eram 4 idas, 2 em fila).
  const lista = useInfiniteQuery({
    queryKey: ["atribuicoes", lojaid, mostrarEncerradas, filtro],
    initialPageParam: 0,
    queryFn: async ({ pageParam }) => {
      const { data, error } = await supabase.rpc("atribuicoes_da_loja", {
        p_lojaid: lojaid,
        p_encerradas: mostrarEncerradas,
        ...(filtro.de ? { p_de: filtro.de, p_ate: filtro.ate } : {}),
        ...(filtro.tarefaid ? { p_tarefaid: Number(filtro.tarefaid) } : {}),
        ...(filtro.quem === "missao" ? { p_missao: true } : {}),
        ...(filtro.quem !== "todos" && filtro.quem !== "missao" ? { p_funcionarioid: Number(filtro.quem) } : {}),
        p_limite: pageParam === 0 && !filtrando ? PRIMEIRAS : POR_VEZ,
        p_offset: pageParam,
      });
      if (error) throw error;
      return data as unknown as PaginaDeAtribuicoes;
    },
    getNextPageParam: (ultima, todas) =>
      ultima.temmais ? todas.reduce((n, p) => n + p.linhas.length, 0) : undefined,
  });

  function aplicarFiltro() {
    const f = rascunho;
    if ((f.de === "") !== (f.ate === "")) return setErroFiltro("Escolha a data inicial e a final (ou nenhuma das duas).");
    if (f.de && f.de > f.ate) return setErroFiltro("A data final é antes da inicial.");
    if (f.de && (Date.parse(f.ate) - Date.parse(f.de)) / 86_400_000 > MAXIMO_DE_DIAS - 1) {
      return setErroFiltro(`Escolha um período de no máximo ${MAXIMO_DE_DIAS} dias.`);
    }
    setErroFiltro(null);
    setFiltro(f);
  }

  function limparFiltro() {
    setRascunho(SEM_FILTRO);
    setFiltro(SEM_FILTRO);
    setErroFiltro(null);
  }

  const atribuir = useMutation({
    mutationFn: async () => {
      if (tarefaid === "") throw new Error("Escolha a tarefa.");
      if (!missao && selecionados.length === 0) throw new Error("Escolha quem faz a tarefa.");
      if (missao && !horarioMissao) throw new Error("Escolha a hora em que a missão vai para o grupo.");
      if (frequencia === "Semanal" && diasSemana.length === 0) {
        throw new Error("Escolha pelo menos um dia da semana.");
      }

      // O banco decide o formato: 1 pessoa = tarefa com dono; várias = uma
      // tarefa compartilhada com lista; nenhuma = missão da equipe.
      const base = {
        p_tarefaid: Number(tarefaid),
        p_lojaid: lojaid,
        p_funcionarios: missao ? null : selecionados,
        p_tipofrequencia: frequencia,
        p_horariodisparo: missao ? horarioMissao : undefined,
        // Vazio vira null: o banco entende "o dia todo".
        p_disponivelapartir: disponivelApartir || null,
      };

      // Semanal com vários dias vira uma atribuição por dia, como no antigo.
      const pedidos =
        frequencia === "Semanal"
          ? diasSemana.map((d) => ({ ...base, p_valorfrequencia: d }))
          : frequencia === "Mensal"
            ? [{ ...base, p_valorfrequencia: diaMes }]
            : frequencia === "Unica"
              ? [{ ...base, p_dataagendamento: new Date(`${data}T12:00:00-03:00`).toISOString() }]
              : [base];

      // Atribuir NÃO cria entrega. A entrega nasce quando a pessoa envia.
      for (const pedido of pedidos) {
        const { error } = await supabase.rpc("atribuir_tarefa", pedido);
        if (error) throw error;
      }
    },
    onSuccess: () => {
      setTarefaid("");
      setSelecionados([]);
      setMissao(false);
      setDiasSemana([]);
      setDisponivelApartir("");
      qc.invalidateQueries({ queryKey: ["atribuicoes", lojaid] });
    },
  });

  const encerrar = useMutation({
    mutationFn: async (ids: number[]) => {
      // Encerrar não apaga: marca o fim da vigência, e o histórico fica.
      const { error } = await supabase
        .from("tarefasatribuidas")
        .update({ datafimvigencia: hojeEmSaoPaulo() })
        .in("atribuicaoid", ids);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ["atribuicoes", lojaid] }),
  });

  // Mudar a hora sem encerrar e criar de novo: encerrar perderia o histórico.
  const mudarHora = useMutation({
    mutationFn: async ({ ids, hora }: { ids: number[]; hora: string | null }) => {
      // Semanal com vários dias são várias atribuições: todas mudam juntas.
      for (const id of ids) {
        const { error } = await supabase.rpc("alterar_hora_da_atribuicao", {
          p_atribuicaoid: id,
          p_hora: hora,
        });
        if (error) throw error;
      }
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ["atribuicoes", lojaid] }),
  });

  function descrever(l: Linha) {
    if (l.tipofrequencia === "Diaria") return "Todo dia";
    if (l.tipofrequencia === "Semanal") {
      const nomes = DIAS_SEMANA.filter((d) => l.dias.includes(d.valor)).map((d) => d.curto);
      return `Toda ${nomes.join(", ")}`;
    }
    if (l.tipofrequencia === "Mensal") return `Todo dia ${l.valor} do mês`;
    if (l.dataagendamento) {
      return `Uma vez, em ${new Date(l.dataagendamento).toLocaleDateString("pt-BR")}`;
    }
    return "Uma vez";
  }

  /** "Todo dia · a partir das 15h" */
  function descreverComHora(l: Linha) {
    return descrever(l) + (l.disponivelapartir ? ` · a partir das ${horaCurta(l.disponivelapartir)}` : "");
  }

  const todasAsTarefas = opcoesTarefas.data ?? [];
  const tarefas = todasAsTarefas.filter((t) => t.ativa);
  const pessoas = opcoesFuncionarios.data ?? [];
  const linhas = (lista.data?.pages ?? []).flatMap((p) => p.linhas);

  return (
    <div className="space-y-4">
      <p className="text-sm text-muted-foreground">
        Atribuições da loja <strong className="text-foreground">{nomeDaLoja}</strong>. Troque a
        loja no seletor do topo para ver as outras.
      </p>

      <form
        onSubmit={(e) => {
          e.preventDefault();
          atribuir.mutate();
        }}
        className="space-y-3 rounded-xl border border-border bg-card p-4"
      >
        <p className="text-sm font-semibold">Nova atribuição</p>

        <div className="grid gap-3 md:grid-cols-3">
          <select
            required
            value={tarefaid}
            onChange={(e) => setTarefaid(e.target.value === "" ? "" : Number(e.target.value))}
            className={campo}
          >
            <option value="">Escolha a tarefa...</option>
            {tarefas.map((t) => (
              <option key={t.tarefaid} value={t.tarefaid}>
                {t.titulo} ({t.pontos} pts)
              </option>
            ))}
          </select>

          <select
            value={frequencia}
            onChange={(e) => setFrequencia(e.target.value)}
            className={campo}
          >
            <option value="Unica">Uma vez só</option>
            <option value="Diaria">Todo dia</option>
            <option value="Semanal">Toda semana</option>
            <option value="Mensal">Todo mês</option>
          </select>
        </div>

        <div className="space-y-2 rounded-lg border border-border p-3">
          <p className="text-sm font-medium">Quem faz?</p>
          <label className="flex items-center gap-2 text-sm">
            <input
              type="checkbox"
              checked={missao}
              onChange={(e) => {
                setMissao(e.target.checked);
                if (e.target.checked) setSelecionados([]);
              }}
            />
            🚨 Missão da equipe — aberta a qualquer pessoa da loja
          </label>

          {!missao && (
            <>
              <div className="max-h-48 space-y-1 overflow-y-auto">
                {pessoas.map((p) => (
                  <label key={p.funcionarioid} className="flex items-center gap-2 text-sm">
                    <input
                      type="checkbox"
                      checked={selecionados.includes(p.funcionarioid)}
                      onChange={(e) =>
                        setSelecionados((atual) =>
                          e.target.checked
                            ? [...atual, p.funcionarioid]
                            : atual.filter((x) => x !== p.funcionarioid),
                        )
                      }
                    />
                    {p.nomecompleto}
                  </label>
                ))}
              </div>
              <p className="text-xs text-muted-foreground">
                {selecionados.length === 0
                  ? "Marque uma pessoa, ou marque várias para deixar a tarefa aberta entre elas."
                  : selecionados.length === 1
                    ? "Tarefa desta pessoa: só ela faz, e não fazer pesa na nota dela."
                    : `Uma tarefa só, entre ${selecionados.length} pessoas: a primeira que pegar fica com ela e some da lista das outras. Quem não pegou fica neutro na nota.`}
              </p>
            </>
          )}
        </div>

        {missao && (
          <div className="space-y-1 rounded-lg border border-azul/40 bg-azul-soft px-3 py-2">
            <label className="flex flex-wrap items-center gap-2 text-sm text-azul">
              A que horas o bot manda a missão ao grupo da equipe?
              <input
                type="time"
                required
                value={horarioMissao}
                onChange={(e) => setHorarioMissao(e.target.value)}
                className={campo}
              />
            </label>
            <p className="text-xs text-azul">
              A missão não tem dono: a primeira pessoa da equipe que pegar fica com ela no dia. Quem pega assume:
              a tarefa passa a pesar na nota de quem pegou, e em mais ninguém.
            </p>
          </div>
        )}

        {/* Vale para tarefa que repete e para tarefa de data única. */}
        <div className="space-y-1">
          <label className="flex flex-wrap items-center gap-2 text-sm text-muted-foreground">
            Disponível a partir de:
            <input
              type="time"
              value={disponivelApartir}
              onChange={(e) => setDisponivelApartir(e.target.value)}
              className={campo}
            />
            {disponivelApartir && (
              <button
                type="button"
                onClick={() => setDisponivelApartir("")}
                className="text-xs underline underline-offset-2"
              >
                limpar
              </button>
            )}
          </label>
          <p className="text-xs text-muted-foreground">
            Vazio = o dia todo, como é hoje. Com hora, a tarefa só entra na fila do tablet a partir
            dela — útil para a tarefa que só faz sentido depois do almoço. A hora é a da sua
            empresa (o fuso fica em Configurações).
          </p>
        </div>

        {frequencia === "Unica" && (
          <label className="flex items-center gap-2 text-sm text-muted-foreground">
            No dia:
            <input
              type="date"
              required
              value={data}
              onChange={(e) => setData(e.target.value)}
              className={campo}
            />
          </label>
        )}

        {frequencia === "Semanal" && (
          <fieldset className="space-y-1">
            <legend className="text-sm text-muted-foreground">
              Em quais dias? (pode marcar vários)
            </legend>
            <div className="flex flex-wrap gap-3">
              {DIAS_SEMANA.map((d) => (
                <label key={d.valor} className="flex items-center gap-2 text-sm">
                  <input
                    type="checkbox"
                    checked={diasSemana.includes(d.valor)}
                    onChange={(e) =>
                      setDiasSemana((atual) =>
                        e.target.checked
                          ? [...atual, d.valor]
                          : atual.filter((v) => v !== d.valor),
                      )
                    }
                  />
                  {d.nome}
                </label>
              ))}
            </div>
          </fieldset>
        )}

        {frequencia === "Mensal" && (
          <label className="flex items-center gap-2 text-sm text-muted-foreground">
            Todo dia
            <input
              type="number"
              min={1}
              max={31}
              value={diaMes}
              onChange={(e) => setDiaMes(Number(e.target.value))}
              className={`${campo} w-20`}
            />
            do mês. Se o mês não tiver esse dia, cai no último.
          </label>
        )}

        <button
          type="submit"
          disabled={atribuir.isPending}
          className="rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground disabled:opacity-60"
        >
          {atribuir.isPending ? "Atribuindo..." : "Atribuir"}
        </button>

        <p className="text-xs text-muted-foreground">
          Atribuir não registra entrega nenhuma. A entrega nasce quando a pessoa envia o que fez.
        </p>

        {atribuir.isError && (
          <p className="text-sm text-destructive">{(atribuir.error as Error).message}</p>
        )}
        {tarefas.length === 0 && !opcoesTarefas.isLoading && (
          <p className="text-sm text-muted-foreground">
            Nenhuma tarefa vale nesta loja ainda. Cadastre uma no Catálogo e marque esta loja.
          </p>
        )}
        {pessoas.length === 0 && !opcoesFuncionarios.isLoading && (
          <p className="text-sm text-muted-foreground">
            Ninguém trabalha nesta loja ainda. Ajuste isso na tela Equipe.
          </p>
        )}
      </form>

      <div className="space-y-3">
        <div className="space-y-3 rounded-xl border border-border bg-card p-4">
          <p className="text-sm font-semibold">Filtrar as atribuições</p>
          <div className="grid gap-3 md:grid-cols-4">
            <label className="space-y-1 text-sm">
              <span className="block text-muted-foreground">Criadas de</span>
              <input
                type="date"
                value={rascunho.de}
                onChange={(e) => setRascunho({ ...rascunho, de: e.target.value })}
                className={`${campo} w-full`}
              />
            </label>
            <label className="space-y-1 text-sm">
              <span className="block text-muted-foreground">até</span>
              <input
                type="date"
                value={rascunho.ate}
                onChange={(e) => setRascunho({ ...rascunho, ate: e.target.value })}
                className={`${campo} w-full`}
              />
            </label>
            <label className="space-y-1 text-sm">
              <span className="block text-muted-foreground">Tarefa</span>
              <select
                value={rascunho.tarefaid}
                onChange={(e) => setRascunho({ ...rascunho, tarefaid: e.target.value })}
                className={`${campo} w-full`}
              >
                <option value="">Todas</option>
                {todasAsTarefas.map((t) => (
                  <option key={t.tarefaid} value={t.tarefaid}>
                    {t.titulo}
                    {t.ativa ? "" : " (desativada)"}
                  </option>
                ))}
              </select>
            </label>
            <label className="space-y-1 text-sm">
              <span className="block text-muted-foreground">Colaborador</span>
              {/* Só quem está ativo NESTA loja: a lista que a página já busca. */}
              <select
                value={rascunho.quem}
                onChange={(e) => setRascunho({ ...rascunho, quem: e.target.value })}
                className={`${campo} w-full`}
              >
                <option value="todos">Todos</option>
                <option value="missao">🚨 Missão da equipe</option>
                {pessoas.map((p) => (
                  <option key={p.funcionarioid} value={p.funcionarioid}>
                    {p.nomecompleto}
                  </option>
                ))}
              </select>
            </label>
          </div>
          <div className="flex flex-wrap items-center gap-3">
            <button
              type="button"
              onClick={aplicarFiltro}
              className="rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground"
            >
              Filtrar
            </button>
            <button type="button" onClick={limparFiltro} className="rounded-lg border border-border px-4 py-2 text-sm">
              Limpar filtro
            </button>
            <label className="flex items-center gap-2 text-sm text-muted-foreground">
              <input
                type="checkbox"
                checked={mostrarEncerradas}
                onChange={(e) => setMostrarEncerradas(e.target.checked)}
              />
              Mostrar também as encerradas
            </label>
          </div>
          {erroFiltro && <p className="text-sm text-destructive">{erroFiltro}</p>}
          <p className="text-xs text-muted-foreground">
            {filtrando
              ? `Filtro aplicado: ${POR_VEZ} por vez, da mais nova para a mais antiga.`
              : `Sem filtro: as ${PRIMEIRAS} atribuições criadas por último, da mais nova para a mais antiga.`}{" "}
            A data é a de quando a atribuição foi criada (período de até {MAXIMO_DE_DIAS} dias).
          </p>
        </div>

        {lista.isLoading && <p className="text-muted-foreground">Carregando...</p>}
        {lista.isError && (
          <p className="text-sm text-destructive">{(lista.error as Error).message}</p>
        )}

        {linhas.map((l) => (
          <div
            key={l.ids.join("-")}
            className="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-border bg-card px-4 py-3"
          >
            <div className="min-w-0">
              <p className={`font-medium ${l.datafimvigencia ? "text-muted-foreground" : ""}`}>
                {l.titulo ?? `Tarefa ${l.tarefaid}`}
              </p>
              <p className="text-sm text-muted-foreground">
                {quemFaz(l)} · {descreverComHora(l)}
              </p>
              {l.criadaemdia && <p className="text-xs text-muted-foreground">Criada em {l.criadaemdia}</p>}
            </div>
            {l.datafimvigencia ? (
              <span className="rounded-md border border-border px-2 py-0.5 text-xs text-muted-foreground">
                Encerrada em {new Date(`${l.datafimvigencia}T12:00:00`).toLocaleDateString("pt-BR")}
              </span>
            ) : (
              <div className="flex flex-wrap gap-2">
                <button
                  onClick={() => {
                    const atual = l.disponivelapartir ? l.disponivelapartir.slice(0, 5) : "";
                    const digitado = window.prompt(
                      "A partir de que horas esta tarefa fica disponível?\n" +
                        "Use hh:mm (ex.: 15:00). Deixe vazio para o dia todo.",
                      atual,
                    );
                    if (digitado === null) return;
                    const limpo = digitado.trim();
                    if (limpo !== "" && !/^([01][0-9]|2[0-3]):[0-5][0-9]$/.test(limpo)) {
                      window.alert("Horário inválido. Use hh:mm, entre 00:00 e 23:59.");
                      return;
                    }
                    mudarHora.mutate({ ids: l.ids, hora: limpo === "" ? null : limpo });
                  }}
                  disabled={mudarHora.isPending}
                  className="rounded-md border border-border px-3 py-1 text-sm disabled:opacity-60"
                >
                  Mudar horário
                </button>
                <button
                  onClick={() => encerrar.mutate(l.ids)}
                  disabled={encerrar.isPending}
                  className="rounded-md border border-border px-3 py-1 text-sm disabled:opacity-60"
                >
                  Encerrar
                </button>
              </div>
            )}
          </div>
        ))}

        {lista.hasNextPage && (
          <button
            onClick={() => lista.fetchNextPage()}
            disabled={lista.isFetchingNextPage}
            className="rounded-lg border border-border px-4 py-2 text-sm disabled:opacity-60"
          >
            {lista.isFetchingNextPage ? "Carregando..." : `Carregar mais ${POR_VEZ}`}
          </button>
        )}

        {!lista.isLoading && linhas.length === 0 && (
          <p className="text-sm text-muted-foreground">
            {filtrando
              ? "Nenhuma atribuição com esse filtro."
              : mostrarEncerradas
                ? "Nenhuma atribuição nesta loja."
                : "Nenhuma atribuição ativa nesta loja."}
          </p>
        )}

        {encerrar.isError && (
          <p className="text-sm text-destructive">{(encerrar.error as Error).message}</p>
        )}
        {mudarHora.isError && (
          <p className="text-sm text-destructive">{(mudarHora.error as Error).message}</p>
        )}

        <p className="text-xs text-muted-foreground">
          Encerrar não apaga nada: marca a data de fim e a atribuição sai da lista, mas o
          histórico dela continua guardado.
        </p>
      </div>
    </div>
  );
}
