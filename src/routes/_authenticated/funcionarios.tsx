import { createFileRoute } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Nav } from "@/components/Nav";

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
  const [form, setForm] = useState(FORM_VAZIO);
  const [editando, setEditando] = useState<number | null>(null);
  const [mostrarInativos, setMostrarInativos] = useState(false);

  const lista = useQuery({
    queryKey: ["funcionarios"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("funcionarios")
        .select(
          "funcionarioid, nomecompleto, cargo, setor, telefonewhatsapp, diadefolga, saldopontos, ativo",
        )
        .order("nomecompleto");
      if (error) throw error;
      return data ?? [];
    },
  });

  function limparFormulario() {
    setForm(FORM_VAZIO);
    setEditando(null);
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
      const { error } =
        editando === null
          ? await supabase.from("funcionarios").insert(dados)
          : await supabase.from("funcionarios").update(dados).eq("funcionarioid", editando);
      if (error) throw error;
    },
    onSuccess: () => {
      limparFormulario();
      qc.invalidateQueries({ queryKey: ["funcionarios"] });
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
    onSuccess: () => qc.invalidateQueries({ queryKey: ["funcionarios"] }),
  });

  const todos = lista.data ?? [];
  const visiveis = mostrarInativos ? todos : todos.filter((f) => f.ativo);
  const inativos = todos.length - todos.filter((f) => f.ativo).length;

  return (
    <main className="min-h-screen space-y-6 p-6">
      <Nav />

      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <h1 className="text-3xl font-bold">Equipe</h1>
        <p className="text-sm text-muted-foreground">
          {todos.filter((f) => f.ativo).length} ativos
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

      <div className="space-y-2">
        {lista.isLoading && <p className="text-muted-foreground">Carregando...</p>}

        {lista.isError && (
          <p className="text-sm text-destructive">
            Não foi possível carregar a equipe: {(lista.error as Error).message}
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
            </div>

            <div className="flex items-center gap-3">
              <span className="text-sm text-muted-foreground">
                <strong className="text-accent">{f.saldopontos}</strong> pontos
              </span>
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

        {!lista.isLoading && visiveis.length === 0 && (
          <p className="text-sm text-muted-foreground">
            {todos.length === 0
              ? "Nenhum funcionário cadastrado ainda. Use o formulário acima para começar."
              : "Nenhum funcionário ativo."}
          </p>
        )}
      </div>
    </main>
  );
}
