import { createFileRoute } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Nav } from "@/components/Nav";

export const Route = createFileRoute("/_authenticated/funcionarios")({
  component: Funcionarios,
});

function Funcionarios() {
  const qc = useQueryClient();
  const [form, setForm] = useState({ nome: "", setor: "", cargo: "", telefone: "" });

  const lista = useQuery({
    queryKey: ["funcionarios"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("funcionarios")
        .select("id, nome, setor, cargo, telefone, ativo")
        .order("nome");
      if (error) throw error;
      return data ?? [];
    },
  });

  const criar = useMutation({
    mutationFn: async () => {
      const { error } = await supabase.from("funcionarios").insert({
        nome: form.nome,
        setor: form.setor || null,
        cargo: form.cargo || null,
        telefone: form.telefone || null,
      });
      if (error) throw error;
    },
    onSuccess: () => {
      setForm({ nome: "", setor: "", cargo: "", telefone: "" });
      qc.invalidateQueries({ queryKey: ["funcionarios"] });
    },
  });

  const alternarAtivo = useMutation({
    mutationFn: async ({ id, ativo }: { id: string; ativo: boolean }) => {
      const { error } = await supabase
        .from("funcionarios")
        .update({ ativo })
        .eq("id", id);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ["funcionarios"] }),
  });

  return (
    <main className="min-h-screen space-y-6 p-6">
      <Nav />
      <h1 className="text-3xl font-bold">Equipe</h1>

      <form
        onSubmit={(e) => {
          e.preventDefault();
          criar.mutate();
        }}
        className="grid gap-3 rounded-xl border border-border bg-card p-4 md:grid-cols-5"
      >
        <input
          required
          placeholder="Nome"
          value={form.nome}
          onChange={(e) => setForm({ ...form, nome: e.target.value })}
          className="rounded-lg border border-border bg-background px-3 py-2 md:col-span-2"
        />
        <input
          placeholder="Setor"
          value={form.setor}
          onChange={(e) => setForm({ ...form, setor: e.target.value })}
          className="rounded-lg border border-border bg-background px-3 py-2"
        />
        <input
          placeholder="Cargo"
          value={form.cargo}
          onChange={(e) => setForm({ ...form, cargo: e.target.value })}
          className="rounded-lg border border-border bg-background px-3 py-2"
        />
        <button
          type="submit"
          disabled={criar.isPending}
          className="rounded-lg bg-primary px-4 py-2 font-semibold text-primary-foreground"
        >
          Adicionar
        </button>
      </form>

      <div className="space-y-2">
        {lista.isLoading && <p className="text-muted-foreground">Carregando...</p>}
        {(lista.data ?? []).map((f) => (
          <div
            key={f.id}
            className="flex items-center justify-between rounded-lg border border-border bg-card px-4 py-3"
          >
            <div>
              <p className="font-medium">{f.nome}</p>
              <p className="text-sm text-muted-foreground">
                {[f.setor, f.cargo].filter(Boolean).join(" · ") || "—"}
              </p>
            </div>
            <button
              onClick={() => alternarAtivo.mutate({ id: f.id, ativo: !f.ativo })}
              className="rounded-md border border-border px-3 py-1 text-sm"
            >
              {f.ativo ? "Desativar" : "Reativar"}
            </button>
          </div>
        ))}
        {lista.data?.length === 0 && (
          <p className="text-sm text-muted-foreground">Nenhum funcionário cadastrado.</p>
        )}
      </div>
    </main>
  );
}
