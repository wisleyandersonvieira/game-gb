import { createFileRoute } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import {
  criarContaEConvidar,
  reenviarConvite,
  situacaoDosLogins,
} from "@/servidor/contas";
import { Pagina } from "@/ui/Pagina";

export const Route = createFileRoute("/admin/")({
  component: PainelAdmin,
});

const FORM_VAZIO = {
  nome: "",
  email: "",
  telefone: "",
  cidade: "",
  limitelojas: 1,
  observacoes: "",
};

const campo =
  "rounded-lg border border-border bg-background px-3 py-2 text-sm placeholder:text-muted-foreground";

const CORES_STATUS: Record<string, string> = {
  ativa: "text-sucesso",
  suspensa: "text-azul",
  cancelada: "text-destructive",
};

function PainelAdmin() {
  const qc = useQueryClient();
  const [form, setForm] = useState(FORM_VAZIO);
  const [editando, setEditando] = useState<number | null>(null);
  const [recado, setRecado] = useState<string | null>(null);

  const contas = useQuery({
    queryKey: ["contas"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("contas")
        .select("contaid, nome, email, telefone, cidade, limitelojas, status, observacoes, criadoem")
        .order("nome");
      if (error) throw error;
      return data ?? [];
    },
  });

  // Situação das rotinas automáticas de cada cliente (só ok/erro, sem detalhes).
  const rotinas = useQuery({
    queryKey: ["rotinas-resumo-admin"],
    refetchInterval: 60_000,
    queryFn: async () => {
      const { data, error } = await supabase.rpc("rotinas_resumo_admin");
      if (error) throw error;
      const porConta = new Map<number, { rotina: string; ultimaem: string; situacao: string }[]>();
      for (const r of data ?? []) porConta.set(r.contaid, [...(porConta.get(r.contaid) ?? []), r]);
      return porConta;
    },
  });

  // Quantas lojas cada cliente já usa, para comparar com o limite contratado.
  const lojas = useQuery({
    queryKey: ["lojas-por-conta"],
    queryFn: async () => {
      const { data, error } = await supabase.from("lojas").select("contaid, ativa");
      if (error) throw error;
      const porConta = new Map<number, number>();
      for (const l of data ?? []) {
        if (l.ativa) porConta.set(l.contaid, (porConta.get(l.contaid) ?? 0) + 1);
      }
      return porConta;
    },
  });

  const logins = useQuery({
    queryKey: ["situacao-logins"],
    queryFn: async () => {
      const lista = await situacaoDosLogins();
      return new Map(lista.map((l) => [l.contaid, l.jaEntrou]));
    },
  });

  function limpar() {
    setForm(FORM_VAZIO);
    setEditando(null);
  }

  const salvar = useMutation({
    mutationFn: async () => {
      if (editando === null) {
        return await criarContaEConvidar({ data: { ...form, limitelojas: Number(form.limitelojas) } });
      }
      const { error } = await supabase
        .from("contas")
        .update({
          nome: form.nome.trim(),
          telefone: form.telefone.trim() || null,
          cidade: form.cidade.trim() || null,
          limitelojas: Number(form.limitelojas),
          observacoes: form.observacoes.trim() || null,
        })
        .eq("contaid", editando);
      if (error) throw error;
      return null;
    },
    onSuccess: (r) => {
      setRecado(
        r
          ? `Cliente criado. Convite enviado para ${r.email}.`
          : "Cadastro do cliente atualizado.",
      );
      limpar();
      qc.invalidateQueries({ queryKey: ["contas"] });
      qc.invalidateQueries({ queryKey: ["situacao-logins"] });
    },
  });

  const mudarStatus = useMutation({
    mutationFn: async ({ contaid, status }: { contaid: number; status: string }) => {
      const { error } = await supabase.from("contas").update({ status }).eq("contaid", contaid);
      if (error) throw error;
    },
    onSuccess: () => {
      setRecado(null);
      qc.invalidateQueries({ queryKey: ["contas"] });
    },
  });

  const convidarDeNovo = useMutation({
    mutationFn: async (contaid: number) => await reenviarConvite({ data: { contaid } }),
    onSuccess: (r) => setRecado(`Convite reenviado para ${r.email}.`),
  });

  const lista = contas.data ?? [];

  return (
    <Pagina
      titulo="Clientes"
      descricao="Clientes da plataforma. Você não vê os dados operacionais de nenhum deles."
    >

      {recado && (
        <p className="rounded-lg border border-border bg-card px-4 py-3 text-sm">{recado}</p>
      )}

      <form
        onSubmit={(e) => {
          e.preventDefault();
          setRecado(null);
          salvar.mutate();
        }}
        className="space-y-3 rounded-xl border border-border bg-card p-4"
      >
        <p className="text-sm font-semibold">
          {editando === null ? "Novo cliente" : "Editando cadastro do cliente"}
        </p>

        <div className="grid gap-3 md:grid-cols-3">
          <input
            required
            placeholder="Nome da empresa"
            value={form.nome}
            onChange={(e) => setForm({ ...form, nome: e.target.value })}
            className={`${campo} md:col-span-2`}
          />
          <input
            required
            type="email"
            placeholder="E-mail do responsável"
            value={form.email}
            disabled={editando !== null}
            onChange={(e) => setForm({ ...form, email: e.target.value })}
            className={`${campo} disabled:opacity-50`}
          />
          <input
            placeholder="Telefone"
            value={form.telefone}
            onChange={(e) => setForm({ ...form, telefone: e.target.value })}
            className={campo}
          />
          <input
            placeholder="Cidade"
            value={form.cidade}
            onChange={(e) => setForm({ ...form, cidade: e.target.value })}
            className={campo}
          />
          <label className="flex items-center gap-2 text-sm text-muted-foreground">
            Lojas liberadas:
            <input
              required
              type="number"
              min={1}
              value={form.limitelojas}
              onChange={(e) => setForm({ ...form, limitelojas: Number(e.target.value) })}
              className={`${campo} w-24`}
            />
          </label>
          <input
            placeholder="Observações"
            value={form.observacoes}
            onChange={(e) => setForm({ ...form, observacoes: e.target.value })}
            className={`${campo} md:col-span-3`}
          />
        </div>

        {editando === null && (
          <p className="text-xs text-muted-foreground">
            Ao salvar, enviamos um convite por e-mail para o responsável definir a senha dele.
          </p>
        )}

        <div className="flex flex-wrap items-center gap-2">
          <button
            type="submit"
            disabled={salvar.isPending}
            className="rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground disabled:opacity-60"
          >
            {salvar.isPending
              ? "Salvando..."
              : editando === null
                ? "Cadastrar e convidar"
                : "Salvar"}
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
        {contas.isLoading && <p className="text-muted-foreground">Carregando...</p>}
        {contas.isError && (
          <p className="text-sm text-destructive">
            Não foi possível carregar: {(contas.error as Error).message}
          </p>
        )}

        {lista.map((c) => {
          const usadas = lojas.data?.get(c.contaid) ?? 0;
          const jaEntrou = logins.data?.get(c.contaid);
          return (
            <div
              key={c.contaid}
              className="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-border bg-card px-4 py-3"
            >
              <div className="min-w-0">
                <p className="font-medium">
                  {c.nome}
                  <span className={`ml-2 text-xs font-normal ${CORES_STATUS[c.status] ?? ""}`}>
                    {c.status}
                  </span>
                  {jaEntrou === false && (
                    <span className="ml-2 rounded-md border border-border px-2 py-0.5 text-xs font-normal text-muted-foreground">
                      convite pendente
                    </span>
                  )}
                </p>
                <p className="text-sm text-muted-foreground">
                  {c.email}
                  {c.cidade && ` · ${c.cidade}`}
                  {c.telefone && ` · ${c.telefone}`}
                </p>
                <SituacaoRotinas itens={rotinas.data?.get(c.contaid)} />
              </div>

              <div className="flex flex-wrap items-center gap-2">
                <span className="text-sm text-muted-foreground">
                  <strong className={usadas >= c.limitelojas ? "text-azul" : "text-foreground"}>
                    {usadas}
                  </strong>{" "}
                  de {c.limitelojas} lojas
                </span>

                <button
                  onClick={() => {
                    setRecado(null);
                    setEditando(c.contaid);
                    setForm({
                      nome: c.nome,
                      email: c.email,
                      telefone: c.telefone ?? "",
                      cidade: c.cidade ?? "",
                      limitelojas: c.limitelojas,
                      observacoes: c.observacoes ?? "",
                    });
                  }}
                  className="rounded-md border border-border px-3 py-1 text-sm"
                >
                  Editar
                </button>

                <button
                  onClick={() => convidarDeNovo.mutate(c.contaid)}
                  disabled={convidarDeNovo.isPending}
                  className="rounded-md border border-border px-3 py-1 text-sm disabled:opacity-60"
                >
                  Reenviar convite
                </button>

                <button
                  onClick={() =>
                    mudarStatus.mutate({
                      contaid: c.contaid,
                      status: c.status === "ativa" ? "suspensa" : "ativa",
                    })
                  }
                  className="rounded-md border border-border px-3 py-1 text-sm"
                >
                  {c.status === "ativa" ? "Suspender" : "Reativar"}
                </button>
              </div>
            </div>
          );
        })}

        {!contas.isLoading && lista.length === 0 && (
          <p className="text-sm text-muted-foreground">
            Nenhum cliente cadastrado ainda. Use o formulário acima para criar o primeiro.
          </p>
        )}

        {convidarDeNovo.isError && (
          <p className="text-sm text-destructive">{(convidarDeNovo.error as Error).message}</p>
        )}
        {mudarStatus.isError && (
          <p className="text-sm text-destructive">{(mudarStatus.error as Error).message}</p>
        )}
      </div>
    </Pagina>
  );
}

const NOME_ROTINA: Record<string, string> = {
  lista_do_dia: "lista do dia",
  fechamento_mensal: "fechamento",
  conferencia_livro: "livro de pontos",
  limpeza: "limpeza",
};

function SituacaoRotinas({ itens }: { itens?: { rotina: string; ultimaem: string; situacao: string }[] }) {
  if (!itens || itens.length === 0) {
    return <p className="text-xs text-muted-foreground">Rotinas: ainda não rodaram.</p>;
  }
  const problemas = itens.filter((i) => i.situacao !== "ok");
  const ultima = itens.reduce((a, b) => (a.ultimaem > b.ultimaem ? a : b));
  const quando = new Date(ultima.ultimaem).toLocaleString("pt-BR", {
    timeZone: "America/Sao_Paulo",
    day: "2-digit",
    month: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  });
  return problemas.length === 0 ? (
    <p className="text-xs text-sucesso">Rotinas ok · última {quando}</p>
  ) : (
    <p className="text-xs text-destructive">
      Rotinas com problema:{" "}
      {problemas.map((p) => `${NOME_ROTINA[p.rotina] ?? p.rotina} (${p.situacao === "diferenca" ? "diferença" : "erro"})`).join(", ")}
    </p>
  );
}
