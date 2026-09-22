import { createFileRoute, Link, redirect } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { BarraDoDia, percentual, type DadosPainel } from "@/painel/PainelDaLoja";
import { useLojaAtiva } from "@/lojas/loja-ativa";

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
        .select("lojaid, nome, cidade, endereco, ativa, gestorid, responsavelagendamentosid, mostrarvalorestv")
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

  // Na TV, por padrão, a meta aparece só em porcentagem (os clientes veem a TV).
  const alternarValoresTv = useMutation({
    mutationFn: async ({ lojaid, mostrar }: { lojaid: number; mostrar: boolean }) => {
      const { error } = await supabase.from("lojas").update({ mostrarvalorestv: mostrar }).eq("lojaid", lojaid);
      if (error) throw error;
    },
    onSuccess: atualizarListas,
  });

  const alternarAtiva = useMutation({
    mutationFn: async ({ lojaid, ativa }: { lojaid: number; ativa: boolean }) => {
      const { error } = await supabase.from("lojas").update({ ativa }).eq("lojaid", lojaid);
      if (error) throw error;
    },
    onSuccess: atualizarListas,
  });

  return (
    <div className="mx-auto max-w-4xl space-y-6">

      {conta.isLoading && <p className="text-muted-foreground">Carregando...</p>}

      {conta.data && (
        <>
          <div className="flex flex-wrap items-baseline justify-between gap-2">
            <h1 className="font-display text-2xl font-semibold tracking-tight sm:text-3xl">{conta.data.nome}</h1>
            <p className="text-sm text-muted-foreground">
              <strong className={noLimite ? "text-azul" : "text-foreground"}>
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
            <p className="rounded-lg border border-azul/40 bg-azul-soft px-4 py-3 text-sm text-azul">
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
              <p className="rounded-lg border border-border bg-card px-4 py-3 text-sm text-azul">
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
                  <label className="mt-1 flex items-center gap-2 text-xs text-muted-foreground">
                    <input
                      type="checkbox"
                      checked={l.mostrarvalorestv}
                      disabled={suspensa || alternarValoresTv.isPending}
                      onChange={(e) => alternarValoresTv.mutate({ lojaid: l.lojaid, mostrar: e.target.checked })}
                    />
                    Mostrar valores em R$ da meta na TV (desligado: a TV mostra só a porcentagem)
                  </label>
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

            {alternarValoresTv.isError && (
              <p className="text-sm text-destructive">{(alternarValoresTv.error as Error).message}</p>
            )}
            {alternarAtiva.isError && (
              <p className="text-sm text-destructive">{(alternarAtiva.error as Error).message}</p>
            )}

            <p className="text-xs text-muted-foreground">
              Desativar uma loja não apaga nada: o histórico dela continua guardado e ela pode
              ser reativada. Uma loja desativada não ocupa vaga no seu plano.
            </p>
          </section>

          <ResumoDasLojas />
          <LinksDeTv suspensa={suspensa} />
        </>
      )}

      {conta.isError && (
        <p className="text-sm text-destructive">
          Não foi possível carregar: {(conta.error as Error).message}
        </p>
      )}
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Resumo de todas as lojas, lado a lado                               */
/* ------------------------------------------------------------------ */

type Resumo = {
  lojaid: number;
  nome: string;
  progresso: DadosPainel["progresso"];
  pendentes: number;
  lider: { pessoa: string; pontos: number } | null;
};

function ResumoDasLojas() {
  const { escolherLoja } = useLojaAtiva();
  const resumo = useQuery({
    queryKey: ["resumo-lojas"],
    refetchInterval: 60_000,
    queryFn: async () => {
      const { data, error } = await supabase.rpc("resumo_das_lojas");
      if (error) throw error;
      return (data ?? []) as unknown as Resumo[];
    },
  });

  const lojas = resumo.data ?? [];

  return (
    <section className="space-y-2">
      <h2 className="text-sm font-semibold">Hoje em cada loja</h2>
      {resumo.isError && <p className="text-sm text-destructive">{(resumo.error as Error).message}</p>}
      {lojas.length === 0 && !resumo.isLoading && (
        <p className="text-sm text-muted-foreground">Nenhuma loja ativa.</p>
      )}
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        {lojas.map((l) => (
          <Link
            key={l.lojaid}
            to="/operacional"
            onClick={() => escolherLoja(l.lojaid)}
            className="space-y-3 rounded-xl border border-border bg-card p-4 transition hover:border-primary"
          >
            <div className="flex items-baseline justify-between gap-2">
              <p className="font-semibold">{l.nome}</p>
              <p className="text-2xl font-bold">{percentual(l.progresso)}%</p>
            </div>
            <BarraDoDia progresso={l.progresso} compacta />
            <div className="space-y-1 text-sm text-muted-foreground">
              <p>
                {l.progresso.aprovadas} de {l.progresso.total} tarefas concluídas
              </p>
              <p className={l.pendentes > 0 ? "text-azul" : undefined}>
                {l.pendentes} {l.pendentes === 1 ? "entrega esperando" : "entregas esperando"} validação
              </p>
              <p>
                Líder do dia:{" "}
                {l.lider ? (
                  <strong className="text-foreground">
                    🥇 {l.lider.pessoa} ({l.lider.pontos})
                  </strong>
                ) : (
                  "ninguém pontuou ainda"
                )}
              </p>
            </div>
          </Link>
        ))}
      </div>
    </section>
  );
}

/* ------------------------------------------------------------------ */
/* Links de TV                                                         */
/* ------------------------------------------------------------------ */

function quandoFoi(iso: string | null) {
  if (!iso) return "nunca usado";
  const minutos = Math.floor((Date.now() - new Date(iso).getTime()) / 60000);
  if (minutos < 2) return "no ar agora";
  if (minutos < 60) return `usado há ${minutos} min`;
  return `usado em ${new Date(iso).toLocaleString("pt-BR", {
    timeZone: "America/Sao_Paulo",
    day: "2-digit",
    month: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  })}`;
}

function LinksDeTv({ suspensa }: { suspensa: boolean }) {
  const qc = useQueryClient();
  const { lojas } = useLojaAtiva();
  const [lojaid, setLojaid] = useState<number | "">("");
  const [nome, setNome] = useState("");
  const [novoLink, setNovoLink] = useState<string | null>(null);
  const [copiado, setCopiado] = useState(false);

  const links = useQuery({
    queryKey: ["links-tv"],
    refetchInterval: 60_000,
    queryFn: async () => {
      const { data, error } = await supabase
        .from("linkstv")
        .select("linktvid, lojaid, nome, criadoem, revogadoem, ultimouso")
        .order("criadoem", { ascending: false });
      if (error) throw error;
      return data ?? [];
    },
  });

  const criar = useMutation({
    mutationFn: async () => {
      if (lojaid === "") throw new Error("Escolha a loja.");
      const { data, error } = await supabase.rpc("criar_link_tv", { p_lojaid: lojaid, p_nome: nome });
      if (error) throw error;
      return `${window.location.origin}/tv/${data as string}`;
    },
    onSuccess: (endereco) => {
      setNovoLink(endereco);
      setCopiado(false);
      setNome("");
      qc.invalidateQueries({ queryKey: ["links-tv"] });
    },
  });

  const revogar = useMutation({
    mutationFn: async (linktvid: number) => {
      const { error } = await supabase.rpc("revogar_link_tv", { p_linktvid: linktvid });
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ["links-tv"] }),
  });

  const nomeDaLoja = (id: number) => lojas.find((l) => l.lojaid === id)?.nome ?? "loja desativada";
  const lista = links.data ?? [];

  return (
    <section className="space-y-3">
      <div>
        <h2 className="text-sm font-semibold">Links de TV</h2>
        <p className="text-xs text-muted-foreground">
          Abra o link no navegador da TV da loja. Ele mostra só o painel daquela loja, sem login e
          sem poder mudar nada. Se a TV sair da loja, revogue o link.
        </p>
      </div>

      <form
        onSubmit={(e) => {
          e.preventDefault();
          criar.mutate();
        }}
        className="flex flex-wrap items-center gap-2 rounded-xl border border-border bg-card p-4"
      >
        <select
          required
          value={lojaid}
          onChange={(e) => setLojaid(e.target.value === "" ? "" : Number(e.target.value))}
          className={campo}
        >
          <option value="">Loja...</option>
          {lojas.map((l) => (
            <option key={l.lojaid} value={l.lojaid}>
              {l.nome}
            </option>
          ))}
        </select>
        <input
          required
          placeholder="Nome (ex.: TV do balcão)"
          value={nome}
          onChange={(e) => setNome(e.target.value)}
          className={campo}
        />
        <button
          type="submit"
          disabled={criar.isPending || suspensa}
          className="rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground disabled:opacity-50"
        >
          Criar link de TV
        </button>
        {criar.isError && <p className="w-full text-sm text-destructive">{(criar.error as Error).message}</p>}
      </form>

      {novoLink && (
        <div className="space-y-2 rounded-xl border border-azul/40 bg-azul-soft p-4">
          <p className="text-sm font-semibold text-azul">
            Copie agora: este link aparece uma única vez.
          </p>
          <p className="break-all rounded-md bg-background px-3 py-2 font-mono text-xs">{novoLink}</p>
          <div className="flex flex-wrap gap-2">
            <button
              onClick={async () => {
                try {
                  await navigator.clipboard.writeText(novoLink);
                  setCopiado(true);
                } catch {
                  setCopiado(false);
                }
              }}
              className="rounded-md border border-border px-3 py-1 text-sm"
            >
              {copiado ? "Copiado!" : "Copiar link"}
            </button>
            <a href={novoLink} target="_blank" rel="noreferrer" className="rounded-md border border-border px-3 py-1 text-sm">
              Abrir numa aba nova
            </a>
            <button onClick={() => setNovoLink(null)} className="rounded-md border border-border px-3 py-1 text-sm">
              Já copiei, fechar
            </button>
          </div>
          <p className="text-xs text-muted-foreground">
            Por segurança, guardamos só uma "impressão digital" do link. Se perdê-lo, crie outro.
          </p>
        </div>
      )}

      <div className="space-y-2">
        {lista.map((k) => (
          <div
            key={k.linktvid}
            className="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-border bg-card px-4 py-3"
          >
            <div>
              <p className={`font-medium ${k.revogadoem ? "text-muted-foreground line-through" : ""}`}>{k.nome}</p>
              <p className="text-sm text-muted-foreground">
                {nomeDaLoja(k.lojaid)} ·{" "}
                {k.revogadoem ? (
                  "revogado"
                ) : (
                  <span className={quandoFoi(k.ultimouso) === "no ar agora" ? "text-sucesso" : undefined}>
                    {quandoFoi(k.ultimouso)}
                  </span>
                )}
              </p>
            </div>
            {!k.revogadoem && (
              <button
                onClick={() => {
                  if (window.confirm(`Revogar "${k.nome}"? A TV mostra "Painel indisponível" em até 30 segundos.`)) {
                    revogar.mutate(k.linktvid);
                  }
                }}
                disabled={suspensa}
                className="rounded-md border border-destructive px-3 py-1 text-sm text-destructive disabled:opacity-50"
              >
                Revogar
              </button>
            )}
          </div>
        ))}
        {lista.length === 0 && !links.isLoading && (
          <p className="text-sm text-muted-foreground">Nenhum link de TV criado ainda.</p>
        )}
        {revogar.isError && <p className="text-sm text-destructive">{(revogar.error as Error).message}</p>}
      </div>
    </section>
  );
}

