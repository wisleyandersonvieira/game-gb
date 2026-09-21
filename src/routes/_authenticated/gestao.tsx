import { createFileRoute, redirect } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Nav } from "@/components/Nav";

export const Route = createFileRoute("/_authenticated/gestao")({
  ssr: false,
  beforeLoad: async () => {
    const { data: conta } = await supabase.rpc("minha_conta");
    if (conta === null || conta === undefined) throw redirect({ to: "/sem-acesso" });
  },
  component: Gestao,
});

const FORM_VAZIO = {
  nome: "",
  cidade: "",
  endereco: "",
  gestorid: "" as number | "",
  responsavelagendamentosid: "" as number | "",
};

const campo =
  "rounded-lg border border-border bg-background px-3 py-2 text-sm placeholder:text-muted-foreground";

function Gestao() {
  const qc = useQueryClient();
  const [form, setForm] = useState(FORM_VAZIO);
  const [editando, setEditando] = useState<number | null>(null);
  const [abrirFormulario, setAbrirFormulario] = useState(false);

  const conta = useQuery({
    queryKey: ["minha-conta"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("contas")
        .select("contaid, nome, email, telefone, cidade, limitelojas, status")
        .single();
      if (error) throw error;
      return data;
    },
  });

  const lojas = useQuery({
    queryKey: ["lojas-todas"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("lojas")
        .select("lojaid, nome, cidade, endereco, ativa, gestorid, responsavelagendamentosid")
        .order("nome");
      if (error) throw error;
      return data ?? [];
    },
  });

  // Nomes, para mostrar quem é o gestor de cada loja.
  const nomes = useQuery({
    queryKey: ["nomes-funcionarios"],
    queryFn: async () => {
      const { data, error } = await supabase.from("funcionarios").select("funcionarioid, nomecompleto");
      if (error) throw error;
      return new Map((data ?? []).map((f) => [f.funcionarioid, f.nomecompleto]));
    },
  });

  // Só quem trabalha na loja em edição pode ser o gestor ou o responsável dela.
  // O banco confere isso de novo (chave composta pessoa + loja).
  const pessoasDaLoja = useQuery({
    queryKey: ["pessoas-da-loja", editando],
    enabled: editando !== null,
    queryFn: async () => {
      const { data: vinculos, error } = await supabase
        .from("funcionarioslojas")
        .select("funcionarioid")
        .eq("lojaid", editando!)
        .eq("ativo", true);
      if (error) throw error;
      const ids = (vinculos ?? []).map((v) => v.funcionarioid);
      if (ids.length === 0) return [];
      const { data, error: erroNomes } = await supabase
        .from("funcionarios")
        .select("funcionarioid, nomecompleto")
        .in("funcionarioid", ids)
        .order("nomecompleto");
      if (erroNomes) throw erroNomes;
      return data ?? [];
    },
  });

  const todas = lojas.data ?? [];
  const ativas = todas.filter((l) => l.ativa);
  const limite = conta.data?.limitelojas ?? 0;
  const noLimite = ativas.length >= limite;
  const suspensa = conta.data?.status !== "ativa";

  function fechar() {
    setForm(FORM_VAZIO);
    setEditando(null);
    setAbrirFormulario(false);
  }

  function atualizarListas() {
    qc.invalidateQueries({ queryKey: ["lojas-todas"] });
    qc.invalidateQueries({ queryKey: ["lojas-ativas"] });
  }

  const salvar = useMutation({
    mutationFn: async () => {
      const dados = {
        nome: form.nome.trim(),
        cidade: form.cidade.trim() || null,
        endereco: form.endereco.trim() || null,
      };
      const { error } =
        editando === null
          ? await supabase.from("lojas").insert(dados)
          : await supabase
              .from("lojas")
              .update({
                ...dados,
                gestorid: form.gestorid === "" ? null : form.gestorid,
                responsavelagendamentosid:
                  form.responsavelagendamentosid === "" ? null : form.responsavelagendamentosid,
              })
              .eq("lojaid", editando);
      if (error) throw error;
    },
    onSuccess: () => {
      fechar();
      atualizarListas();
    },
  });

  const alternarAtiva = useMutation({
    mutationFn: async ({ lojaid, ativa }: { lojaid: number; ativa: boolean }) => {
      const { error } = await supabase.from("lojas").update({ ativa }).eq("lojaid", lojaid);
      if (error) throw error;
    },
    onSuccess: atualizarListas,
  });

  return (
    <main className="mx-auto min-h-screen max-w-4xl space-y-6 p-6">
      <Nav />

      {conta.isLoading && <p className="text-muted-foreground">Carregando...</p>}

      {conta.data && (
        <>
          <div className="flex flex-wrap items-baseline justify-between gap-2">
            <h1 className="text-3xl font-bold">{conta.data.nome}</h1>
            <p className="text-sm text-muted-foreground">
              <strong className={noLimite ? "text-accent" : "text-foreground"}>
                {ativas.length}
              </strong>{" "}
              de {limite} lojas usadas
            </p>
          </div>

          <p className="text-sm text-muted-foreground">
            {conta.data.email}
            {conta.data.cidade && ` · ${conta.data.cidade}`}
            {conta.data.telefone && ` · ${conta.data.telefone}`}
          </p>

          {suspensa && (
            <p className="rounded-lg border border-accent bg-card px-4 py-3 text-sm text-accent">
              <strong>Conta {conta.data.status}.</strong> Você continua consultando tudo, mas o
              sistema não aceita cadastrar nem alterar nada. Fale com o suporte para reativar.
            </p>
          )}

          <section className="space-y-3">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <h2 className="text-sm font-semibold">Suas lojas</h2>
              {!abrirFormulario && (
                <button
                  onClick={() => {
                    setForm(FORM_VAZIO);
                    setEditando(null);
                    setAbrirFormulario(true);
                  }}
                  disabled={noLimite || suspensa}
                  className="rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground disabled:opacity-50"
                >
                  Nova loja
                </button>
              )}
            </div>

            {noLimite && !suspensa && (
              <p className="rounded-lg border border-border bg-card px-4 py-3 text-sm text-accent">
                Você atingiu o limite do seu plano. Fale com o suporte para ampliar.
              </p>
            )}

            {abrirFormulario && (
              <form
                onSubmit={(e) => {
                  e.preventDefault();
                  salvar.mutate();
                }}
                className="space-y-3 rounded-xl border border-border bg-card p-4"
              >
                <p className="text-sm font-semibold">
                  {editando === null ? "Nova loja" : "Editando loja"}
                </p>
                <div className="grid gap-3 md:grid-cols-3">
                  <input
                    required
                    autoFocus
                    placeholder="Nome da loja"
                    value={form.nome}
                    onChange={(e) => setForm({ ...form, nome: e.target.value })}
                    className={campo}
                  />
                  <input
                    placeholder="Cidade"
                    value={form.cidade}
                    onChange={(e) => setForm({ ...form, cidade: e.target.value })}
                    className={campo}
                  />
                  <input
                    placeholder="Endereço"
                    value={form.endereco}
                    onChange={(e) => setForm({ ...form, endereco: e.target.value })}
                    className={campo}
                  />
                </div>

                {editando !== null && (
                  <div className="grid gap-3 md:grid-cols-2">
                    <label className="space-y-1 text-sm text-muted-foreground">
                      <span>Gestor da loja</span>
                      <select
                        value={form.gestorid}
                        onChange={(e) =>
                          setForm({ ...form, gestorid: e.target.value === "" ? "" : Number(e.target.value) })
                        }
                        className={`${campo} w-full`}
                      >
                        <option value="">Ninguém definido</option>
                        {(pessoasDaLoja.data ?? []).map((p) => (
                          <option key={p.funcionarioid} value={p.funcionarioid}>
                            {p.nomecompleto}
                          </option>
                        ))}
                      </select>
                    </label>
                    <label className="space-y-1 text-sm text-muted-foreground">
                      <span>Responsável pelos agendamentos</span>
                      <select
                        value={form.responsavelagendamentosid}
                        onChange={(e) =>
                          setForm({
                            ...form,
                            responsavelagendamentosid: e.target.value === "" ? "" : Number(e.target.value),
                          })
                        }
                        className={`${campo} w-full`}
                      >
                        <option value="">Ninguém definido</option>
                        {(pessoasDaLoja.data ?? []).map((p) => (
                          <option key={p.funcionarioid} value={p.funcionarioid}>
                            {p.nomecompleto}
                          </option>
                        ))}
                      </select>
                    </label>
                    {(pessoasDaLoja.data ?? []).length === 0 && !pessoasDaLoja.isLoading && (
                      <p className="text-xs text-muted-foreground md:col-span-2">
                        Ninguém trabalha nesta loja ainda. Ligue pessoas a ela na tela Equipe.
                      </p>
                    )}
                  </div>
                )}

                <div className="flex flex-wrap gap-2">
                  <button
                    type="submit"
                    disabled={salvar.isPending}
                    className="rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground disabled:opacity-60"
                  >
                    {salvar.isPending ? "Salvando..." : "Salvar"}
                  </button>
                  <button
                    type="button"
                    onClick={fechar}
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

            {todas.length === 0 && !abrirFormulario && (
              <p className="rounded-lg border border-border bg-card px-4 py-3 text-sm text-muted-foreground">
                Nenhuma loja cadastrada ainda. Use o botão "Nova loja" para começar.
              </p>
            )}

            {todas.map((l) => (
              <div
                key={l.lojaid}
                className="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-border bg-card px-4 py-3"
              >
                <div className="min-w-0">
                  <p className="font-medium">
                    {l.nome}
                    {!l.ativa && (
                      <span className="ml-2 rounded-md border border-border px-2 py-0.5 text-xs font-normal text-muted-foreground">
                        desativada
                      </span>
                    )}
                  </p>
                  <p className="text-sm text-muted-foreground">
                    {[l.cidade, l.endereco].filter(Boolean).join(" · ") || "Sem endereço"}
                  </p>
                  <p className="text-xs text-muted-foreground">
                    Gestor: {l.gestorid ? (nomes.data?.get(l.gestorid) ?? "—") : "não definido"}
                    {" · "}
                    Agendamentos:{" "}
                    {l.responsavelagendamentosid
                      ? (nomes.data?.get(l.responsavelagendamentosid) ?? "—")
                      : "não definido"}
                  </p>
                </div>

                <div className="flex flex-wrap items-center gap-2">
                  <button
                    onClick={() => {
                      setEditando(l.lojaid);
                      setForm({
                        nome: l.nome,
                        cidade: l.cidade ?? "",
                        endereco: l.endereco ?? "",
                        gestorid: l.gestorid ?? "",
                        responsavelagendamentosid: l.responsavelagendamentosid ?? "",
                      });
                      setAbrirFormulario(true);
                    }}
                    disabled={suspensa}
                    className="rounded-md border border-border px-3 py-1 text-sm disabled:opacity-50"
                  >
                    Editar
                  </button>
                  <button
                    onClick={() => alternarAtiva.mutate({ lojaid: l.lojaid, ativa: !l.ativa })}
                    disabled={suspensa || (!l.ativa && noLimite)}
                    title={
                      !l.ativa && noLimite
                        ? "Reativar passaria do limite do seu plano."
                        : undefined
                    }
                    className="rounded-md border border-border px-3 py-1 text-sm disabled:opacity-50"
                  >
                    {l.ativa ? "Desativar" : "Reativar"}
                  </button>
                </div>
              </div>
            ))}

            {alternarAtiva.isError && (
              <p className="text-sm text-destructive">{(alternarAtiva.error as Error).message}</p>
            )}

            <p className="text-xs text-muted-foreground">
              Desativar uma loja não apaga nada: o histórico dela continua guardado e ela pode
              ser reativada. Uma loja desativada não ocupa vaga no seu plano.
            </p>
          </section>

          {/* Preenchido na Fase 6, com progresso do dia, pódio e Kanban por loja. */}
          <section className="space-y-2">
            <h2 className="text-sm font-semibold">Resumo das lojas</h2>
            <div className="rounded-xl border border-dashed border-border bg-card px-4 py-8 text-center">
              <p className="text-sm text-muted-foreground">
                Aqui vai aparecer o resumo de cada loja: progresso do dia, pódio e entregas
                esperando validação.
              </p>
              <p className="mt-1 text-xs text-muted-foreground">Em construção (Fase 6).</p>
            </div>
          </section>
        </>
      )}

      {conta.isError && (
        <p className="text-sm text-destructive">
          Não foi possível carregar: {(conta.error as Error).message}
        </p>
      )}
    </main>
  );
}
