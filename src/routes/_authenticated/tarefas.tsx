import { createFileRoute } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { AvisoSemLoja, useLojaAtiva } from "@/lojas/loja-ativa";
import { Pagina } from "@/ui/Pagina";

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
        <Atribuicoes lojaid={lojaAtiva!} nomeDaLoja={loja?.nome ?? ""} />
      )}
    </Pagina>
  );
}

/* ------------------------------------------------------------------ */
/* Catálogo: o que existe para fazer, e em quais lojas cada uma vale   */
/* ------------------------------------------------------------------ */

const TAREFA_VAZIA = { titulo: "", descricao: "", pontos: 10, setor: "" };

function Catalogo() {
  const qc = useQueryClient();
  const { lojas } = useLojaAtiva();
  const [form, setForm] = useState(TAREFA_VAZIA);
  const [lojasEscolhidas, setLojasEscolhidas] = useState<number[]>([]);
  const [editando, setEditando] = useState<number | null>(null);

  const catalogo = useQuery({
    queryKey: ["catalogo-tarefas"],
    queryFn: async () => {
      const { data: tarefas, error } = await supabase
        .from("tarefas")
        .select("tarefaid, titulo, descricao, pontos, setor, ativa, sistema")
        .order("titulo");
      if (error) throw error;

      const { data: vinculos, error: erroVinculos } = await supabase
        .from("tarefaslojas")
        .select("tarefaid, lojaid, ativo");
      if (erroVinculos) throw erroVinculos;

      const porTarefa = new Map<number, number[]>();
      for (const v of vinculos ?? []) {
        if (!v.ativo) continue;
        porTarefa.set(v.tarefaid, [...(porTarefa.get(v.tarefaid) ?? []), v.lojaid]);
      }

      return (tarefas ?? []).map((t) => ({ ...t, lojas: porTarefa.get(t.tarefaid) ?? [] }));
    },
  });

  function limpar() {
    setForm(TAREFA_VAZIA);
    setLojasEscolhidas([]);
    setEditando(null);
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
    },
    onSuccess: () => {
      limpar();
      qc.invalidateQueries({ queryKey: ["catalogo-tarefas"] });
      qc.invalidateQueries({ queryKey: ["atribuicoes"] });
    },
  });

  const alternarAtiva = useMutation({
    mutationFn: async ({ tarefaid, ativa }: { tarefaid: number; ativa: boolean }) => {
      const { error } = await supabase.from("tarefas").update({ ativa }).eq("tarefaid", tarefaid);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ["catalogo-tarefas"] }),
  });

  const lista = catalogo.data ?? [];
  const nomeDaLoja = (id: number) => lojas.find((l) => l.lojaid === id)?.nome ?? `Loja ${id}`;

  return (
    <div className="space-y-4">
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
          {editando !== null && (
            <button
              type="button"
              onClick={limpar}
              className="rounded-lg border border-border px-4 py-2 text-sm"
            >
              Cancelar
            </button>
          )}
        </div>

        {salvar.isError && (
          <p className="text-sm text-destructive">{(salvar.error as Error).message}</p>
        )}
      </form>

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
                {t.sistema && (
                  <span className="ml-2 rounded-md border border-azul/40 bg-azul-soft px-2 py-0.5 text-xs font-normal text-azul">
                    do sistema
                  </span>
                )}
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
              {t.sistema && (
                <p className="text-xs text-muted-foreground">
                  Criada pelo sistema. Não pode ser apagada e não aparece para atribuir à mão.
                </p>
              )}
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
                }}
                className="rounded-md border border-border px-3 py-1 text-sm"
              >
                Editar
              </button>
              {!t.sistema && (
                <button
                  onClick={() => alternarAtiva.mutate({ tarefaid: t.tarefaid, ativa: !t.ativa })}
                  className="rounded-md border border-border px-3 py-1 text-sm"
                >
                  {t.ativa ? "Desativar" : "Reativar"}
                </button>
              )}
            </div>
          </div>
        ))}

        {!catalogo.isLoading && lista.length === 0 && (
          <p className="text-sm text-muted-foreground">Nenhuma tarefa cadastrada ainda.</p>
        )}
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Atribuições: quem faz o quê, nesta loja                             */
/* ------------------------------------------------------------------ */

type Linha = {
  chave: string;
  ids: number[];
  titulo: string;
  nome: string;
  tipofrequencia: string;
  dias: number[];
  valor: number | null;
  dataagendamento: string | null;
  encerradaEm: string | null;
};

function Atribuicoes({ lojaid, nomeDaLoja }: { lojaid: number; nomeDaLoja: string }) {
  const qc = useQueryClient();
  const [tarefaid, setTarefaid] = useState<number | "">("");
  // Quem faz. Uma pessoa = tarefa com dono, como sempre foi. Várias = UMA
  // tarefa compartilhada, que a primeira a pegar leva. Nenhuma + horário =
  // missão da equipe, aberta a toda a loja.
  const [selecionados, setSelecionados] = useState<number[]>([]);
  const [missao, setMissao] = useState(false);
  const [horarioMissao, setHorarioMissao] = useState("10:00");
  const [frequencia, setFrequencia] = useState("Unica");
  const [data, setData] = useState(hojeEmSaoPaulo());
  const [diasSemana, setDiasSemana] = useState<number[]>([]);
  const [diaMes, setDiaMes] = useState(1);
  const [mostrarEncerradas, setMostrarEncerradas] = useState(false);

  // Só tarefas que valem nesta loja, e nunca as do sistema.
  const opcoesTarefas = useQuery({
    queryKey: ["tarefas-da-loja", lojaid],
    queryFn: async () => {
      const { data: vinculos, error } = await supabase
        .from("tarefaslojas")
        .select("tarefaid")
        .eq("lojaid", lojaid)
        .eq("ativo", true);
      if (error) throw error;
      const ids = (vinculos ?? []).map((v) => v.tarefaid);
      if (ids.length === 0) return [];

      const { data: tarefas, error: erroTarefas } = await supabase
        .from("tarefas")
        .select("tarefaid, titulo, pontos, sistema")
        .in("tarefaid", ids)
        .eq("ativa", true)
        .is("sistema", null)
        .order("titulo");
      if (erroTarefas) throw erroTarefas;
      return tarefas ?? [];
    },
  });

  // Só quem trabalha nesta loja, com vínculo ativo.
  const opcoesFuncionarios = useQuery({
    queryKey: ["funcionarios-da-loja", lojaid],
    queryFn: async () => {
      const { data: vinculos, error } = await supabase
        .from("funcionarioslojas")
        .select("funcionarioid")
        .eq("lojaid", lojaid)
        .eq("ativo", true);
      if (error) throw error;
      const ids = (vinculos ?? []).map((v) => v.funcionarioid);
      if (ids.length === 0) return [];

      const { data: pessoas, error: erroPessoas } = await supabase
        .from("funcionarios")
        .select("funcionarioid, nomecompleto")
        .in("funcionarioid", ids)
        .eq("ativo", true)
        .order("nomecompleto");
      if (erroPessoas) throw erroPessoas;
      return pessoas ?? [];
    },
  });

  const lista = useQuery({
    queryKey: ["atribuicoes", lojaid, mostrarEncerradas],
    queryFn: async () => {
      let consulta = supabase
        .from("tarefasatribuidas")
        .select(
          "atribuicaoid, tarefaid, funcionarioid, tipofrequencia, valorfrequencia, dataagendamento, datafimvigencia, horariodisparo, compartilhada",
        )
        .eq("lojaid", lojaid)
        .order("atribuicaoid");
      if (!mostrarEncerradas) consulta = consulta.is("datafimvigencia", null);
      const { data, error } = await consulta;
      if (error) throw error;

      const linhas = data ?? [];
      if (linhas.length === 0) return [] as Linha[];

      const { data: tarefas } = await supabase
        .from("tarefas")
        .select("tarefaid, titulo")
        .in("tarefaid", [...new Set(linhas.map((l) => l.tarefaid))]);
      const { data: pessoas } = await supabase
        .from("funcionarios")
        .select("funcionarioid, nomecompleto")
        .in(
          "funcionarioid",
          [...new Set(linhas.map((l) => l.funcionarioid).filter((v): v is number => v !== null))],
        );

      // Quem pode pegar cada tarefa compartilhada.
      const idsCompartilhadas = linhas.filter((l) => l.compartilhada).map((l) => l.atribuicaoid);
      const { data: candidatos } = idsCompartilhadas.length
        ? await supabase
            .from("tarefascandidatos")
            .select("atribuicaoid, funcionarioid")
            .in("atribuicaoid", idsCompartilhadas)
        : { data: [] };
      const { data: maisPessoas } = candidatos?.length
        ? await supabase
            .from("funcionarios")
            .select("funcionarioid, nomecompleto")
            .in("funcionarioid", [...new Set(candidatos.map((c) => c.funcionarioid))])
        : { data: [] };

      const titulo = new Map((tarefas ?? []).map((t) => [t.tarefaid, t.titulo]));
      const nome = new Map(
        [...(pessoas ?? []), ...(maisPessoas ?? [])].map((p) => [p.funcionarioid, p.nomecompleto]),
      );
      const daTarefa = new Map<number, string[]>();
      for (const c of candidatos ?? []) {
        const atual = daTarefa.get(c.atribuicaoid) ?? [];
        atual.push(nome.get(c.funcionarioid) ?? "—");
        daTarefa.set(c.atribuicaoid, atual);
      }

      // A Semanal com vários dias vira várias linhas no banco, mas uma só na
      // tela: mesma tarefa, mesma pessoa, mesma frequência.
      const agrupadas = new Map<string, Linha>();
      for (const l of linhas) {
        const chave = `${l.tarefaid}|${l.funcionarioid ?? `c${l.atribuicaoid}`}|${l.tipofrequencia}|${l.datafimvigencia ?? "ativa"}`;
        const atual = agrupadas.get(chave);
        if (atual) {
          atual.ids.push(l.atribuicaoid);
          if (l.valorfrequencia !== null) atual.dias.push(l.valorfrequencia);
        } else {
          agrupadas.set(chave, {
            chave,
            ids: [l.atribuicaoid],
            titulo: titulo.get(l.tarefaid) ?? `Tarefa ${l.tarefaid}`,
            nome: l.funcionarioid
              ? (nome.get(l.funcionarioid) ?? "—")
              : l.compartilhada
                ? `👥 ${(daTarefa.get(l.atribuicaoid) ?? []).sort().join(", ")} (a primeira que pegar)`
                : `🚨 Missão da equipe${l.horariodisparo ? ` · ${l.horariodisparo.slice(0, 5)}` : ""}`,
            tipofrequencia: l.tipofrequencia,
            dias: l.valorfrequencia !== null ? [l.valorfrequencia] : [],
            valor: l.valorfrequencia,
            dataagendamento: l.dataagendamento,
            encerradaEm: l.datafimvigencia,
          });
        }
      }
      // Ativas primeiro; as encerradas vêm depois.
      return [...agrupadas.values()].sort(
        (a, b) => Number(a.encerradaEm !== null) - Number(b.encerradaEm !== null),
      );
    },
  });

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

  const tarefas = opcoesTarefas.data ?? [];
  const pessoas = opcoesFuncionarios.data ?? [];
  const linhas = lista.data ?? [];

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

      <div className="space-y-2">
        <label className="flex items-center gap-2 text-sm text-muted-foreground">
          <input
            type="checkbox"
            checked={mostrarEncerradas}
            onChange={(e) => setMostrarEncerradas(e.target.checked)}
          />
          Mostrar também as encerradas
        </label>

        {lista.isLoading && <p className="text-muted-foreground">Carregando...</p>}
        {lista.isError && (
          <p className="text-sm text-destructive">{(lista.error as Error).message}</p>
        )}

        {linhas.map((l) => (
          <div
            key={l.chave}
            className="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-border bg-card px-4 py-3"
          >
            <div className="min-w-0">
              <p className={`font-medium ${l.encerradaEm ? "text-muted-foreground" : ""}`}>{l.titulo}</p>
              <p className="text-sm text-muted-foreground">
                {l.nome} · {descrever(l)}
              </p>
            </div>
            {l.encerradaEm ? (
              <span className="rounded-md border border-border px-2 py-0.5 text-xs text-muted-foreground">
                Encerrada em {new Date(`${l.encerradaEm}T12:00:00`).toLocaleDateString("pt-BR")}
              </span>
            ) : (
              <button
                onClick={() => encerrar.mutate(l.ids)}
                disabled={encerrar.isPending}
                className="rounded-md border border-border px-3 py-1 text-sm disabled:opacity-60"
              >
                Encerrar
              </button>
            )}
          </div>
        ))}

        {!lista.isLoading && linhas.length === 0 && (
          <p className="text-sm text-muted-foreground">
            {mostrarEncerradas ? "Nenhuma atribuição nesta loja." : "Nenhuma atribuição ativa nesta loja."}
          </p>
        )}

        {encerrar.isError && (
          <p className="text-sm text-destructive">{(encerrar.error as Error).message}</p>
        )}

        <p className="text-xs text-muted-foreground">
          Encerrar não apaga nada: marca a data de fim e a atribuição sai da lista, mas o
          histórico dela continua guardado.
        </p>
      </div>
    </div>
  );
}
