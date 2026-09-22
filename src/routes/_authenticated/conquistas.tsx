import { createFileRoute } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";

export const Route = createFileRoute("/_authenticated/conquistas")({
  component: Conquistas,
});

const campo =
  "rounded-lg border border-border bg-background px-3 py-2 text-sm placeholder:text-muted-foreground";

/** Tipos de regra. Os que dependem de módulos futuros ficam cadastráveis, mas só valem quando o módulo existir. */
const TIPOS: { id: string; rotulo: string; disponivel: boolean; modulo?: string }[] = [
  { id: "total_tarefas_aprovadas", rotulo: "Total de tarefas aprovadas", disponivel: true },
  { id: "tarefas_aprovadas_periodo", rotulo: "Tarefas aprovadas em X dias", disponivel: true },
  { id: "sequencia_dias_tarefas", rotulo: "Dias seguidos com tarefa entregue", disponivel: true },
  { id: "sequencia_feedback_diario", rotulo: "Dias seguidos com feedback", disponivel: true },
  { id: "total_comunicados_cientes", rotulo: "Comunicados lidos (com ciência)", disponivel: true },
  { id: "tarefas_grupo_competitivo_aceitas", rotulo: "Tarefas de grupo aceitas", disponivel: false, modulo: "grupos" },
];

function descreverRegra(tipo: string, valor: number, dias: number | null) {
  switch (tipo) {
    case "total_tarefas_aprovadas":
      return `${valor} ${valor === 1 ? "tarefa aprovada" : "tarefas aprovadas"} no total`;
    case "tarefas_aprovadas_periodo":
      return `${valor} tarefas aprovadas em ${dias} ${dias === 1 ? "dia" : "dias"}`;
    case "sequencia_dias_tarefas":
      return `${valor} dias seguidos com tarefa entregue (folga e afastamento não quebram)`;
    case "sequencia_feedback_diario":
      return `${valor} dias seguidos com feedback`;
    case "total_comunicados_cientes":
      return `${valor} comunicados lidos`;
    case "tarefas_grupo_competitivo_aceitas":
      return `${valor} tarefas de grupo aceitas`;
    default:
      return tipo;
  }
}

function data(iso: string | null) {
  if (!iso) return "—";
  return new Date(iso).toLocaleDateString("pt-BR", { timeZone: "America/Sao_Paulo" });
}

function Conquistas() {
  const [aba, setAba] = useState<"cadastro" | "ganhadores">("cadastro");

  return (
    <div className="mx-auto max-w-5xl space-y-6">
      <h1 className="font-display text-2xl font-semibold tracking-tight sm:text-3xl">Conquistas</h1>

      <div className="flex gap-2 border-b border-border">
        {(
          [
            ["cadastro", "Conquistas"],
            ["ganhadores", "Quem ganhou"],
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

      {aba === "cadastro" ? <Cadastro /> : <Ganhadores />}
    </div>
  );
}

function useConquistas() {
  return useQuery({
    queryKey: ["conquistas"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("conquistas")
        .select("conquistaid, nome, descricao, icone, criteriotipo, criteriovalor, criteriodias, pontosbonus, ativa, contardesde, criadoem")
        .order("criadoem");
      if (error) throw error;
      return data ?? [];
    },
  });
}

function atualizarTudo(qc: ReturnType<typeof useQueryClient>) {
  for (const k of ["conquistas", "ganhadores", "pessoas-saldo", "equipe", "extrato"]) {
    qc.invalidateQueries({ queryKey: [k] });
  }
}

/* ------------------------------------------------------------------ */
/* Cadastro                                                            */
/* ------------------------------------------------------------------ */

const NOVA = {
  nome: "",
  descricao: "",
  icone: "🏆",
  tipo: "total_tarefas_aprovadas",
  valor: 10,
  dias: 7,
  bonus: 0,
  retroativa: null as boolean | null,
};

function Cadastro() {
  const qc = useQueryClient();
  const conquistas = useConquistas();
  const [form, setForm] = useState(NOVA);
  const [recado, setRecado] = useState<string | null>(null);
  const [editando, setEditando] = useState<number | null>(null);
  const [edicao, setEdicao] = useState({ nome: "", descricao: "", icone: "", bonus: 0 });

  const tipoEscolhido = TIPOS.find((t) => t.id === form.tipo);

  const criar = useMutation({
    mutationFn: async () => {
      if (form.retroativa === null) throw new Error("Escolha se vale para o histórico ou só a partir de hoje.");
      const { data, error } = await supabase.rpc("criar_conquista", {
        p_nome: form.nome,
        p_descricao: form.descricao,
        p_icone: form.icone,
        p_tipo: form.tipo,
        p_valor: form.valor,
        p_dias: form.dias,
        p_bonus: form.bonus,
        p_retroativa: form.retroativa,
      });
      if (error) throw error;
      return data as { conquistaid: number; concedidas: number };
    },
    onSuccess: (r) => {
      setRecado(
        form.retroativa
          ? `Conquista criada. ${r.concedidas === 0 ? "Ninguém cumpre ainda." : `${r.concedidas} ${r.concedidas === 1 ? "pessoa ganhou" : "pessoas ganharam"} agora, pelo histórico.`}`
          : "Conquista criada. Só contam as tarefas enviadas a partir de agora.",
      );
      setForm(NOVA);
      atualizarTudo(qc);
    },
  });

  const salvarEdicao = useMutation({
    mutationFn: async (conquistaid: number) => {
      if (!edicao.nome.trim()) throw new Error("Dê um nome à conquista.");
      if (!Number.isInteger(edicao.bonus) || edicao.bonus < 0) throw new Error("Bônus precisa ser 0 ou mais.");
      const { error } = await supabase
        .from("conquistas")
        .update({
          nome: edicao.nome.trim(),
          descricao: edicao.descricao.trim() || edicao.nome.trim(),
          icone: edicao.icone.trim() || null,
          pontosbonus: edicao.bonus,
        })
        .eq("conquistaid", conquistaid);
      if (error) throw error;
    },
    onSuccess: () => {
      setEditando(null);
      atualizarTudo(qc);
    },
  });

  const alternar = useMutation({
    mutationFn: async ({ conquistaid, ativa }: { conquistaid: number; ativa: boolean }) => {
      const { error } = await supabase.from("conquistas").update({ ativa }).eq("conquistaid", conquistaid);
      if (error) throw error;
    },
    onSuccess: () => atualizarTudo(qc),
  });

  const lista = conquistas.data ?? [];

  return (
    <div className="space-y-4">
      <form
        onSubmit={(e) => {
          e.preventDefault();
          setRecado(null);
          criar.mutate();
        }}
        className="space-y-3 rounded-xl border border-border bg-card p-4"
      >
        <p className="text-sm font-semibold">Nova conquista</p>
        <div className="grid gap-3 md:grid-cols-6">
          <input
            placeholder="🏆"
            value={form.icone}
            maxLength={4}
            onChange={(e) => setForm({ ...form, icone: e.target.value })}
            className={`${campo} text-center`}
            aria-label="Ícone"
          />
          <input
            required
            placeholder="Nome (ex.: Maratonista)"
            maxLength={100}
            value={form.nome}
            onChange={(e) => setForm({ ...form, nome: e.target.value })}
            className={`${campo} md:col-span-5`}
          />
          <input
            placeholder="Descrição (opcional)"
            maxLength={255}
            value={form.descricao}
            onChange={(e) => setForm({ ...form, descricao: e.target.value })}
            className={`${campo} md:col-span-6`}
          />
        </div>

        <div className="flex flex-wrap items-center gap-3 text-sm">
          <select value={form.tipo} onChange={(e) => setForm({ ...form, tipo: e.target.value })} className={campo}>
            {TIPOS.map((t) => (
              <option key={t.id} value={t.id}>
                {t.rotulo}
                {t.disponivel ? "" : " (em breve)"}
              </option>
            ))}
          </select>
          <label className="flex items-center gap-2 text-muted-foreground">
            Quantidade:
            <input
              required
              type="number"
              min={1}
              value={form.valor}
              onChange={(e) => setForm({ ...form, valor: Number(e.target.value) })}
              className={`${campo} w-24`}
            />
          </label>
          {form.tipo === "tarefas_aprovadas_periodo" && (
            <label className="flex items-center gap-2 text-muted-foreground">
              em quantos dias:
              <input
                required
                type="number"
                min={1}
                max={366}
                value={form.dias}
                onChange={(e) => setForm({ ...form, dias: Number(e.target.value) })}
                className={`${campo} w-24`}
              />
            </label>
          )}
          <label className="flex items-center gap-2 text-muted-foreground">
            Bônus:
            <input
              type="number"
              min={0}
              value={form.bonus}
              onChange={(e) => setForm({ ...form, bonus: Number(e.target.value) })}
              className={`${campo} w-24`}
            />
            pontos
          </label>
        </div>

        {tipoEscolhido && !tipoEscolhido.disponivel && (
          <p className="text-xs text-azul">
            Esta regra depende do módulo de {tipoEscolhido.modulo}, que ainda não existe. Ela fica cadastrada e começa a
            valer quando o módulo estiver pronto.
          </p>
        )}

        <fieldset className="space-y-1 text-sm">
          <legend className="mb-1 font-medium">Vale para quê? (não dá para mudar depois)</legend>
          <label className="flex items-center gap-2">
            <input
              type="radio"
              name="retroativa"
              checked={form.retroativa === true}
              onChange={() => setForm({ ...form, retroativa: true })}
            />
            Para o histórico: quem já cumpre ganha agora
          </label>
          <label className="flex items-center gap-2">
            <input
              type="radio"
              name="retroativa"
              checked={form.retroativa === false}
              onChange={() => setForm({ ...form, retroativa: false })}
            />
            Só a partir de hoje: conta só as tarefas enviadas depois de criar
          </label>
        </fieldset>

        <p className="text-xs text-muted-foreground">
          Cada pessoa ganha cada conquista uma vez só. O bônus entra no saldo e aparece no extrato. Estornar uma tarefa
          não tira a conquista. A regra não muda depois de criada: para outra regra, crie outra conquista.
        </p>

        <button
          type="submit"
          disabled={criar.isPending}
          className="rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground disabled:opacity-60"
        >
          {criar.isPending ? "Criando..." : "Criar conquista"}
        </button>
        {recado && <p className="text-sm text-sucesso">{recado}</p>}
        {criar.isError && <p className="text-sm text-destructive">{(criar.error as Error).message}</p>}
      </form>

      {conquistas.isLoading && <p className="text-muted-foreground">Carregando...</p>}
      {conquistas.isError && <p className="text-sm text-destructive">{(conquistas.error as Error).message}</p>}

      <div className="space-y-2">
        {lista.map((c) => {
          const tipo = TIPOS.find((t) => t.id === c.criteriotipo);
          return (
            <div key={c.conquistaid} className="rounded-lg border border-border bg-card px-4 py-3">
              {editando === c.conquistaid ? (
                <form
                  onSubmit={(e) => {
                    e.preventDefault();
                    salvarEdicao.mutate(c.conquistaid);
                  }}
                  className="space-y-2"
                >
                  <div className="grid gap-2 md:grid-cols-6">
                    <input
                      value={edicao.icone}
                      maxLength={4}
                      onChange={(e) => setEdicao({ ...edicao, icone: e.target.value })}
                      className={`${campo} text-center`}
                      aria-label="Ícone"
                    />
                    <input
                      required
                      value={edicao.nome}
                      maxLength={100}
                      onChange={(e) => setEdicao({ ...edicao, nome: e.target.value })}
                      className={`${campo} md:col-span-3`}
                    />
                    <label className="flex items-center gap-2 text-sm text-muted-foreground md:col-span-2">
                      Bônus:
                      <input
                        type="number"
                        min={0}
                        value={edicao.bonus}
                        onChange={(e) => setEdicao({ ...edicao, bonus: Number(e.target.value) })}
                        className={`${campo} w-24`}
                      />
                    </label>
                    <input
                      value={edicao.descricao}
                      maxLength={255}
                      onChange={(e) => setEdicao({ ...edicao, descricao: e.target.value })}
                      className={`${campo} md:col-span-6`}
                    />
                  </div>
                  <p className="text-xs text-muted-foreground">
                    O bônus novo vale para quem ganhar daqui para frente. A regra não muda.
                  </p>
                  <div className="flex gap-2">
                    <button
                      type="submit"
                      disabled={salvarEdicao.isPending}
                      className="rounded-md bg-primary px-3 py-1 text-sm font-semibold text-primary-foreground"
                    >
                      Salvar
                    </button>
                    <button
                      type="button"
                      onClick={() => setEditando(null)}
                      className="rounded-md border border-border px-3 py-1 text-sm"
                    >
                      Cancelar
                    </button>
                  </div>
                  {salvarEdicao.isError && (
                    <p className="text-sm text-destructive">{(salvarEdicao.error as Error).message}</p>
                  )}
                </form>
              ) : (
                <div className="flex flex-wrap items-center justify-between gap-3">
                  <div className="min-w-0">
                    <p className="font-medium">
                      <span className="mr-2 text-lg">{c.icone ?? "🏆"}</span>
                      {c.nome}
                      {!c.ativa && (
                        <span className="ml-2 rounded-md border border-border px-2 py-0.5 text-xs font-normal text-muted-foreground">
                          desativada
                        </span>
                      )}
                      {tipo && !tipo.disponivel && (
                        <span className="ml-2 rounded-md border border-azul/40 bg-azul-soft px-2 py-0.5 text-xs font-normal text-azul">
                          aguarda o módulo de {tipo.modulo}
                        </span>
                      )}
                    </p>
                    <p className="text-sm text-muted-foreground">
                      {descreverRegra(c.criteriotipo, c.criteriovalor, c.criteriodias)} ·{" "}
                      <strong className="text-azul">+{c.pontosbonus ?? 0}</strong> pontos de bônus
                    </p>
                    <p className="text-xs text-muted-foreground">
                      {c.contardesde
                        ? `Conta a partir de ${data(c.contardesde)}`
                        : "Vale para o histórico"}
                      {c.descricao && c.descricao !== c.nome && ` · ${c.descricao}`}
                    </p>
                  </div>
                  <div className="flex gap-2">
                    <button
                      onClick={() => {
                        setEditando(c.conquistaid);
                        setEdicao({
                          nome: c.nome,
                          descricao: c.descricao ?? "",
                          icone: c.icone ?? "",
                          bonus: c.pontosbonus ?? 0,
                        });
                      }}
                      className="rounded-md border border-border px-3 py-1 text-sm"
                    >
                      Editar
                    </button>
                    <button
                      onClick={() => alternar.mutate({ conquistaid: c.conquistaid, ativa: !c.ativa })}
                      className="rounded-md border border-border px-3 py-1 text-sm"
                    >
                      {c.ativa ? "Desativar" : "Reativar"}
                    </button>
                  </div>
                </div>
              )}
            </div>
          );
        })}
        {!conquistas.isLoading && lista.length === 0 && (
          <p className="text-sm text-muted-foreground">Nenhuma conquista cadastrada ainda.</p>
        )}
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Quem ganhou                                                         */
/* ------------------------------------------------------------------ */

function Ganhadores() {
  const ganhadores = useQuery({
    queryKey: ["ganhadores"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("conquistasfuncionarios")
        .select("conquistafuncionarioid, funcionarioid, conquistaid, dataconquista, pontosbonus")
        .order("dataconquista", { ascending: false })
        .limit(200);
      if (error) throw error;
      const linhas = data ?? [];
      if (linhas.length === 0) return [];
      const [{ data: pessoas }, { data: conquistas }] = await Promise.all([
        supabase.from("funcionarios").select("funcionarioid, nomecompleto"),
        supabase.from("conquistas").select("conquistaid, nome, icone"),
      ]);
      const nome = new Map((pessoas ?? []).map((p) => [p.funcionarioid, p.nomecompleto]));
      const conquista = new Map((conquistas ?? []).map((c) => [c.conquistaid, c]));
      return linhas.map((l) => ({
        ...l,
        pessoa: nome.get(l.funcionarioid) ?? "—",
        conquista: conquista.get(l.conquistaid)?.nome ?? "—",
        icone: conquista.get(l.conquistaid)?.icone ?? "🏆",
      }));
    },
  });

  const lista = ganhadores.data ?? [];

  return (
    <div className="space-y-2">
      {ganhadores.isLoading && <p className="text-muted-foreground">Carregando...</p>}
      {ganhadores.isError && <p className="text-sm text-destructive">{(ganhadores.error as Error).message}</p>}
      {lista.map((g) => (
        <div
          key={g.conquistafuncionarioid}
          className="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-border bg-card px-4 py-3"
        >
          <p>
            <span className="mr-2 text-lg">{g.icone}</span>
            <strong>{g.pessoa}</strong> ganhou <strong>{g.conquista}</strong>
          </p>
          <p className="text-sm text-muted-foreground">
            {data(g.dataconquista)}
            {g.pontosbonus > 0 && (
              <>
                {" "}
                · <strong className="text-azul">+{g.pontosbonus}</strong> pontos
              </>
            )}
          </p>
        </div>
      ))}
      {!ganhadores.isLoading && lista.length === 0 && (
        <p className="text-sm text-muted-foreground">Ninguém ganhou conquista ainda.</p>
      )}
    </div>
  );
}
