import { createFileRoute } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { AvisoSemLoja, useLojaAtiva } from "@/lojas/loja-ativa";

export const Route = createFileRoute("/_authenticated/funcionarios")({
  component: Funcionarios,
});

// Mesma codificação do sistema antigo (legado/database.py):
// 0 = sem folga fixa, 1 = domingo ... 7 = sábado.
const DIAS_FOLGA = [
  { valor: 0, nome: "Sem folga fixa" },
  { valor: 1, nome: "Domingo" },
  { valor: 2, nome: "Segunda-feira" },
  { valor: 3, nome: "Terça-feira" },
  { valor: 4, nome: "Quarta-feira" },
  { valor: 5, nome: "Quinta-feira" },
  { valor: 6, nome: "Sexta-feira" },
  { valor: 7, nome: "Sábado" },
];

const FORM_VAZIO = {
  nomecompleto: "",
  cargo: "",
  setor: "",
  telefonewhatsapp: "",
  diadefolga: 0,
};

const campo =
  "rounded-lg border border-border bg-background px-3 py-2 text-sm placeholder:text-muted-foreground";

function Funcionarios() {
  const qc = useQueryClient();
  const { lojas, lojaAtiva, carregando: carregandoLojas } = useLojaAtiva();

  const [form, setForm] = useState(FORM_VAZIO);
  const [lojasEscolhidas, setLojasEscolhidas] = useState<number[]>([]);
  const [editando, setEditando] = useState<number | null>(null);
  const [mostrarInativos, setMostrarInativos] = useState(false);
  const [filtroLoja, setFiltroLoja] = useState<number | "todas">("todas");

  const equipe = useQuery({
    queryKey: ["equipe"],
    queryFn: async () => {
      const { data: pessoas, error } = await supabase
        .from("funcionarios")
        .select(
          "funcionarioid, nomecompleto, cargo, setor, telefonewhatsapp, diadefolga, saldopontos, ativo",
        )
        .order("nomecompleto");
      if (error) throw error;

      const { data: vinculos, error: erroVinculos } = await supabase
        .from("funcionarioslojas")
        .select("funcionarioid, lojaid, ativo");
      if (erroVinculos) throw erroVinculos;

      const porFuncionario = new Map<number, number[]>();
      for (const v of vinculos ?? []) {
        if (!v.ativo) continue;
        porFuncionario.set(v.funcionarioid, [
          ...(porFuncionario.get(v.funcionarioid) ?? []),
          v.lojaid,
        ]);
      }

      return (pessoas ?? []).map((p) => ({
        ...p,
        lojas: porFuncionario.get(p.funcionarioid) ?? [],
      }));
    },
  });

  function limparFormulario() {
    setForm(FORM_VAZIO);
    setLojasEscolhidas(lojaAtiva ? [lojaAtiva] : []);
    setEditando(null);
  }

  /**
   * Acerta em quais lojas a pessoa trabalha.
   * Sair de uma loja é desativar o vínculo, nunca apagar: o histórico de
   * tarefas e entregas daquela loja aponta para ele.
   */
  async function sincronizarLojas(funcionarioid: number, escolhidas: number[]) {
    if (escolhidas.length > 0) {
      const { error } = await supabase.from("funcionarioslojas").upsert(
        escolhidas.map((lojaid) => ({ funcionarioid, lojaid, ativo: true })),
        { onConflict: "funcionarioid,lojaid" },
      );
      if (error) throw error;
    }

    const desativar = supabase
      .from("funcionarioslojas")
      .update({ ativo: false })
      .eq("funcionarioid", funcionarioid);

    const { error } =
      escolhidas.length > 0
        ? await desativar.not("lojaid", "in", `(${escolhidas.join(",")})`)
        : await desativar;
    if (error) throw error;
  }

  const salvar = useMutation({
    mutationFn: async () => {
      const dados = {
        nomecompleto: form.nomecompleto.trim(),
        cargo: form.cargo.trim() || null,
        setor: form.setor.trim() || null,
        telefonewhatsapp: form.telefonewhatsapp.trim() || null,
        diadefolga: form.diadefolga,
      };

      let funcionarioid = editando;
      if (funcionarioid === null) {
        const { data, error } = await supabase
          .from("funcionarios")
          .insert(dados)
          .select("funcionarioid")
          .single();
        if (error) throw error;
        funcionarioid = data.funcionarioid;
      } else {
        const { error } = await supabase
          .from("funcionarios")
          .update(dados)
          .eq("funcionarioid", funcionarioid);
        if (error) throw error;
      }

      await sincronizarLojas(funcionarioid, lojasEscolhidas);
    },
    onSuccess: () => {
      limparFormulario();
      qc.invalidateQueries({ queryKey: ["equipe"] });
    },
  });

  const alternarAtivo = useMutation({
    mutationFn: async ({ funcionarioid, ativo }: { funcionarioid: number; ativo: boolean }) => {
      const { error } = await supabase
        .from("funcionarios")
        .update({ ativo })
        .eq("funcionarioid", funcionarioid);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ["equipe"] }),
  });

  if (carregandoLojas) {
    return (
      <div className="mx-auto max-w-4xl space-y-6">
        <p className="text-muted-foreground">Carregando...</p>
      </div>
    );
  }

  if (lojas.length === 0) {
    return (
      <div className="mx-auto max-w-4xl space-y-6">
        <h1 className="font-display text-2xl font-semibold tracking-tight sm:text-3xl">Equipe</h1>
        <AvisoSemLoja />
      </div>
    );
  }

  const todos = equipe.data ?? [];
  const porLoja =
    filtroLoja === "todas" ? todos : todos.filter((f) => f.lojas.includes(filtroLoja));
  const visiveis = mostrarInativos ? porLoja : porLoja.filter((f) => f.ativo);
  const inativos = porLoja.length - porLoja.filter((f) => f.ativo).length;
  const nomeDaLoja = (id: number) => lojas.find((l) => l.lojaid === id)?.nome ?? `Loja ${id}`;

  return (
    <div className="mx-auto max-w-4xl space-y-6">

      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <h1 className="font-display text-2xl font-semibold tracking-tight sm:text-3xl">Equipe</h1>
        <p className="text-sm text-muted-foreground">
          {porLoja.filter((f) => f.ativo).length} ativos
          {inativos > 0 && ` · ${inativos} inativos`}
        </p>
      </div>

      <form
        onSubmit={(e) => {
          e.preventDefault();
          salvar.mutate();
        }}
        className="space-y-3 rounded-xl border border-border bg-card p-4"
      >
        <p className="text-sm font-semibold">
          {editando === null ? "Adicionar funcionário" : "Editando funcionário"}
        </p>

        <div className="grid gap-3 md:grid-cols-3">
          <input
            required
            placeholder="Nome completo"
            value={form.nomecompleto}
            onChange={(e) => setForm({ ...form, nomecompleto: e.target.value })}
            className={`${campo} md:col-span-2`}
          />
          <input
            placeholder="Cargo"
            value={form.cargo}
            onChange={(e) => setForm({ ...form, cargo: e.target.value })}
            className={campo}
          />
          <input
            placeholder="Setor"
            value={form.setor}
            onChange={(e) => setForm({ ...form, setor: e.target.value })}
            className={campo}
          />
          <input
            placeholder="WhatsApp"
            value={form.telefonewhatsapp}
            onChange={(e) => setForm({ ...form, telefonewhatsapp: e.target.value })}
            className={campo}
          />
          <select
            value={form.diadefolga}
            onChange={(e) => setForm({ ...form, diadefolga: Number(e.target.value) })}
            className={campo}
          >
            {DIAS_FOLGA.map((d) => (
              <option key={d.valor} value={d.valor}>
                {d.nome}
              </option>
            ))}
          </select>
        </div>

        <fieldset className="space-y-2">
          <legend className="text-sm text-muted-foreground">
            Trabalha em quais lojas? (pode marcar mais de uma)
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
          {lojasEscolhidas.length === 0 && (
            <p className="text-xs text-muted-foreground">
              Sem loja marcada, a pessoa fica cadastrada mas não pode receber tarefas.
            </p>
          )}
        </fieldset>

        <div className="flex flex-wrap items-center gap-2">
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
              onClick={limparFormulario}
              className="rounded-lg border border-border px-4 py-2 text-sm"
            >
              Cancelar
            </button>
          )}
        </div>

        {salvar.isError && (
          <p className="text-sm text-destructive">
            Não foi possível salvar: {(salvar.error as Error).message}
          </p>
        )}
      </form>

      <div className="flex flex-wrap items-center gap-4">
        {lojas.length > 1 && (
          <label className="flex items-center gap-2 text-sm text-muted-foreground">
            Loja:
            <select
              value={filtroLoja}
              onChange={(e) =>
                setFiltroLoja(e.target.value === "todas" ? "todas" : Number(e.target.value))
              }
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
        )}

        {inativos > 0 && (
          <label className="flex items-center gap-2 text-sm text-muted-foreground">
            <input
              type="checkbox"
              checked={mostrarInativos}
              onChange={(e) => setMostrarInativos(e.target.checked)}
            />
            Mostrar também os inativos
          </label>
        )}
      </div>

      <div className="space-y-2">
        {equipe.isLoading && <p className="text-muted-foreground">Carregando...</p>}
        {equipe.isError && (
          <p className="text-sm text-destructive">
            Não foi possível carregar a equipe: {(equipe.error as Error).message}
          </p>
        )}

        {visiveis.map((f) => (
          <div
            key={f.funcionarioid}
            className="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-border bg-card px-4 py-3"
          >
            <div className="min-w-0">
              <p className="font-medium">
                {f.nomecompleto}
                {!f.ativo && (
                  <span className="ml-2 rounded-md border border-border px-2 py-0.5 text-xs font-normal text-muted-foreground">
                    Inativo
                  </span>
                )}
              </p>
              <p className="text-sm text-muted-foreground">
                {[f.cargo, f.setor].filter(Boolean).join(" · ") || "Sem cargo nem setor"}
                {f.diadefolga > 0 &&
                  ` · Folga: ${DIAS_FOLGA.find((d) => d.valor === f.diadefolga)?.nome}`}
              </p>
              <p className="text-sm text-muted-foreground">
                {f.lojas.length > 0
                  ? f.lojas.map(nomeDaLoja).join(" · ")
                  : "Nenhuma loja"}
              </p>
            </div>

            <div className="flex items-center gap-3">
              {f.saldopontos < 0 ? (
                <span
                  className="rounded-md border border-destructive px-2 py-0.5 text-sm font-semibold text-destructive"
                  title="Saldo negativo: a pessoa gastou pontos que depois foram estornados."
                >
                  {f.saldopontos} pontos (negativo)
                </span>
              ) : (
                <span className="text-sm text-muted-foreground">
                  <strong className="text-azul">{f.saldopontos}</strong> pontos
                </span>
              )}
              <button
                onClick={() => {
                  setEditando(f.funcionarioid);
                  setForm({
                    nomecompleto: f.nomecompleto,
                    cargo: f.cargo ?? "",
                    setor: f.setor ?? "",
                    telefonewhatsapp: f.telefonewhatsapp ?? "",
                    diadefolga: f.diadefolga,
                  });
                  setLojasEscolhidas(f.lojas);
                }}
                className="rounded-md border border-border px-3 py-1 text-sm"
              >
                Editar
              </button>
              <button
                onClick={() =>
                  alternarAtivo.mutate({ funcionarioid: f.funcionarioid, ativo: !f.ativo })
                }
                className="rounded-md border border-border px-3 py-1 text-sm"
              >
                {f.ativo ? "Desativar" : "Reativar"}
              </button>
            </div>
          </div>
        ))}

        {!equipe.isLoading && visiveis.length === 0 && (
          <p className="text-sm text-muted-foreground">
            {todos.length === 0
              ? "Nenhum funcionário cadastrado ainda. Use o formulário acima para começar."
              : "Nenhum funcionário ativo nesta loja."}
          </p>
        )}
      </div>
    </div>
  );
}
