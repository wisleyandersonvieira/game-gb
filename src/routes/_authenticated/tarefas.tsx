import { createFileRoute } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Nav } from "@/components/Nav";

export const Route = createFileRoute("/_authenticated/tarefas")({
  component: Tarefas,
});

function Tarefas() {
  const qc = useQueryClient();
  const [form, setForm] = useState({
    titulo: "",
    descricao: "",
    pontos: 10,
    setor: "",
  });
  const [atrib, setAtrib] = useState({ tarefa_id: "", funcionario_id: "" });

  const tarefas = useQuery({
    queryKey: ["tarefas"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("tarefas")
        .select("id, titulo, descricao, pontos, setor")
        .order("titulo");
      if (error) throw error;
      return data ?? [];
    },
  });

  const funcionarios = useQuery({
    queryKey: ["funcionarios-ativos"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("funcionarios")
        .select("id, nome")
        .eq("ativo", true)
        .order("nome");
      if (error) throw error;
      return data ?? [];
    },
  });

  const criar = useMutation({
    mutationFn: async () => {
      const { error } = await supabase.from("tarefas").insert({
        titulo: form.titulo,
        descricao: form.descricao || null,
        pontos: Number(form.pontos) || 0,
        setor: form.setor || null,
      });
      if (error) throw error;
    },
    onSuccess: () => {
      setForm({ titulo: "", descricao: "", pontos: 10, setor: "" });
      qc.invalidateQueries({ queryKey: ["tarefas"] });
    },
  });

  const atribuir = useMutation({
    mutationFn: async () => {
      const { data: atribuicao, error } = await supabase
        .from("tarefas_atribuidas")
        .insert({
          tarefa_id: atrib.tarefa_id,
          funcionario_id: atrib.funcionario_id,
          tipo_frequencia: "Unica",
        })
        .select("id, tarefa_id, funcionario_id")
        .single();
      if (error) throw error;
      const { error: e2 } = await supabase.from("entregas").insert({
        atribuicao_id: atribuicao.id,
        tarefa_id: atribuicao.tarefa_id,
        funcionario_id: atribuicao.funcionario_id,
        status_validacao: "Pendente",
      });
      if (e2) throw e2;
    },
    onSuccess: () => {
      setAtrib({ tarefa_id: "", funcionario_id: "" });
      qc.invalidateQueries({ queryKey: ["entregas"] });
    },
  });

  return (
    <main className="min-h-screen space-y-6 p-6">
      <Nav />
      <h1 className="text-3xl font-bold">Tarefas</h1>

      <form
        onSubmit={(e) => {
          e.preventDefault();
          criar.mutate();
        }}
        className="grid gap-3 rounded-xl border border-border bg-card p-4 md:grid-cols-5"
      >
        <input
          required
          placeholder="Título da tarefa"
          value={form.titulo}
          onChange={(e) => setForm({ ...form, titulo: e.target.value })}
          className="rounded-lg border border-border bg-background px-3 py-2 md:col-span-2"
        />
        <input
          placeholder="Setor"
          value={form.setor}
          onChange={(e) => setForm({ ...form, setor: e.target.value })}
          className="rounded-lg border border-border bg-background px-3 py-2"
        />
        <input
          type="number"
          min={0}
          placeholder="Pontos"
          value={form.pontos}
          onChange={(e) => setForm({ ...form, pontos: Number(e.target.value) })}
          className="rounded-lg border border-border bg-background px-3 py-2"
        />
        <button
          type="submit"
          disabled={criar.isPending}
          className="rounded-lg bg-primary px-4 py-2 font-semibold text-primary-foreground"
        >
          Criar
        </button>
      </form>

      <form
        onSubmit={(e) => {
          e.preventDefault();
          atribuir.mutate();
        }}
        className="grid gap-3 rounded-xl border border-border bg-card p-4 md:grid-cols-4"
      >
        <h2 className="font-semibold md:col-span-4">Atribuir tarefa</h2>
        <select
          required
          value={atrib.tarefa_id}
          onChange={(e) => setAtrib({ ...atrib, tarefa_id: e.target.value })}
          className="rounded-lg border border-border bg-background px-3 py-2"
        >
          <option value="">Tarefa...</option>
          {(tarefas.data ?? []).map((t) => (
            <option key={t.id} value={t.id}>
              {t.titulo}
            </option>
          ))}
        </select>
        <select
          required
          value={atrib.funcionario_id}
          onChange={(e) => setAtrib({ ...atrib, funcionario_id: e.target.value })}
          className="rounded-lg border border-border bg-background px-3 py-2"
        >
          <option value="">Funcionário...</option>
          {(funcionarios.data ?? []).map((f) => (
            <option key={f.id} value={f.id}>
              {f.nome}
            </option>
          ))}
        </select>
        <button
          type="submit"
          disabled={atribuir.isPending}
          className="rounded-lg bg-accent px-4 py-2 font-semibold text-accent-foreground"
        >
          Enviar para o quadro
        </button>
      </form>

      <div className="space-y-2">
        {(tarefas.data ?? []).map((t) => (
          <div
            key={t.id}
            className="flex items-center justify-between rounded-lg border border-border bg-card px-4 py-3"
          >
            <div>
              <p className="font-medium">{t.titulo}</p>
              <p className="text-sm text-muted-foreground">{t.setor ?? "—"}</p>
            </div>
            <span className="font-semibold">{t.pontos} pts</span>
          </div>
        ))}
        {tarefas.data?.length === 0 && (
          <p className="text-sm text-muted-foreground">Nenhuma tarefa cadastrada.</p>
        )}
      </div>
    </main>
  );
}
