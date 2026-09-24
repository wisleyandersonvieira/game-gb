import { createFileRoute, Link, redirect } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { BarraDoDia, percentual, type DadosPainel } from "@/painel/PainelDaLoja";
import { useLojaAtiva } from "@/lojas/loja-ativa";
import { criarAcessoLoja, fichaDosTablets, redefinirSenhaLoja } from "@/servidor/acesso";
import { GruposTelegram } from "@/telegram/Telegram";
import { Pagina } from "@/ui/Pagina";

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
    <Pagina
      titulo={conta.data?.nome ?? "Lojas e links da TV"}
      acoes={
        conta.data ? (
          <p className="text-sm text-muted-foreground">
            <strong className={noLimite ? "text-azul" : "text-foreground"}>{ativas.length}</strong> de {limite} lojas
            usadas
          </p>
        ) : undefined
      }
    >
      {conta.isLoading && <p className="text-muted-foreground">Carregando...</p>}

      {conta.data && (
        <>

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
          <AcessoDasLojas suspensa={suspensa} />
          <LinksDeTv suspensa={suspensa} />
          <GruposTelegram lojas={ativas} suspensa={suspensa} />
        </>
      )}

      {conta.isError && (
        <p className="text-sm text-destructive">
          Não foi possível carregar: {(conta.error as Error).message}
        </p>
      )}
    </Pagina>
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

/* Acesso do tablet de cada loja (Etapa 1.12, partes A e B1)           */
/*                                                                      */
/* A senha NAO pode ser exibida de novo: o banco guarda so o resumo dela */
/* (PBKDF2 com sal). Quem perdeu usa "Gerar nova senha". O usuario, sim, */
/* fica sempre a vista — era ele que sumia e deixava o gestor sem saida. */
function AcessoDasLojas({ suspensa }: { suspensa: boolean }) {
  const qc = useQueryClient();
  const { lojas } = useLojaAtiva();
  const [senhaNova, setSenhaNova] = useState<{ usuario: string; senha: string; loja: string } | null>(null);

  const conta = useQuery({
    queryKey: ["codigo-da-empresa"],
    queryFn: async () => {
      const { data, error } = await supabase.from("contas").select("codigo, nome").single();
      if (error) throw error;
      return data;
    },
  });

  const ficha = useQuery({
    queryKey: ["ficha-dos-tablets"],
    queryFn: () => fichaDosTablets(),
  });

  const criar = useMutation({
    mutationFn: async (loja: { lojaid: number; nome: string }) => ({
      ...(await criarAcessoLoja({ data: { lojaid: loja.lojaid } })),
      loja: loja.nome,
    }),
    onSuccess: (r) => {
      setSenhaNova(r);
      qc.invalidateQueries({ queryKey: ["ficha-dos-tablets"] });
    },
  });

  const redefinir = useMutation({
    mutationFn: async (loja: { lojaid: number; nome: string }) => ({
      ...(await redefinirSenhaLoja({ data: { lojaid: loja.lojaid } })),
      loja: loja.nome,
    }),
    onSuccess: (r) => {
      setSenhaNova(r);
      qc.invalidateQueries({ queryKey: ["ficha-dos-tablets"] });
    },
  });

  const endereco = conta.data?.codigo ? `${window.location.origin}/e/${conta.data.codigo}` : null;
  const porLoja = new Map((ficha.data ?? []).map((f) => [f.lojaid, f]));

  return (
    <section className="space-y-3">
      <style>{`
        #ficha-impressa { position: absolute; left: -10000px; top: 0; }
        @media print {
          body * { visibility: hidden !important; }
          #ficha-impressa, #ficha-impressa * { visibility: visible !important; }
          #ficha-impressa { position: fixed; inset: 0; left: 0; padding: 24mm; background: #fff; color: #000; }
        }
      `}</style>

      <div>
        <h2 className="text-sm font-semibold">Acesso da loja (tablet) e da equipe</h2>
        <p className="text-xs text-muted-foreground">
          O tablet do balcão entra com um acesso por loja. O usuário fica sempre aqui; a senha aparece
          uma vez só, porque é guardada embaralhada e não há como mostrá-la de novo. Perdeu a senha?
          Gere outra.
        </p>
      </div>

      {conta.data?.codigo && (
        <div className="space-y-2 rounded-lg border border-border bg-card p-3 text-sm">
          <p className="font-medium">Código da empresa</p>
          <p className="font-mono text-2xl tracking-widest">{conta.data.codigo}</p>
          <p className="text-xs text-muted-foreground">
            É o que a equipe digita no primeiro campo da tela de entrada. Pode mostrar para quem quiser:
            sozinho ele não abre nada — sem CPF e senha ninguém entra.
          </p>
          <p className="pt-1 font-medium">Link da equipe</p>
          <p className="text-xs text-muted-foreground">
            Imprima e cole no mural. Quem abrir este link já entra com o código da empresa preenchido:
            depois é só CPF e senha.
          </p>
          <p className="mt-1 break-all font-mono text-xs">{endereco}</p>
        </div>
      )}

      {senhaNova && (
        <div className="space-y-2 rounded-lg border-2 border-primary bg-card p-3 text-sm">
          <p className="font-semibold">Acesso do tablet — {senhaNova.loja}</p>
          <p className="flex flex-wrap items-center gap-2">
            Usuário: <span className="font-mono">{senhaNova.usuario}</span>
            <Copiar texto={senhaNova.usuario} />
          </p>
          <p className="flex flex-wrap items-center gap-2">
            Senha: <span className="font-mono text-lg">{senhaNova.senha}</span>
            <Copiar texto={senhaNova.senha} />
          </p>
          <p className="text-xs text-destructive">
            Anote ou imprima agora: esta senha não aparece de novo. Se perder, é só gerar outra.
          </p>
          <div className="flex flex-wrap gap-2">
            <button onClick={() => window.print()} className="rounded-md border border-border px-3 py-1 text-sm">
              Imprimir ficha da loja
            </button>
            <button onClick={() => setSenhaNova(null)} className="rounded-md border border-border px-3 py-1 text-sm">
              Guardei
            </button>
          </div>
        </div>
      )}

      {senhaNova && (
        <div id="ficha-impressa">
          <h1 style={{ fontSize: "20pt", marginBottom: "4mm" }}>Ficha de acesso — {senhaNova.loja}</h1>
          <p style={{ fontSize: "10pt", marginBottom: "8mm" }}>
            {conta.data?.nome ?? ""} · gerada em {new Date().toLocaleString("pt-BR")}
          </p>
          <h2 style={{ fontSize: "12pt", marginTop: "6mm" }}>Tablet do balcão</h2>
          <p style={{ fontSize: "12pt" }}>
            Usuário: <strong style={{ fontFamily: "monospace" }}>{senhaNova.usuario}</strong>
          </p>
          <p style={{ fontSize: "12pt" }}>
            Senha: <strong style={{ fontFamily: "monospace" }}>{senhaNova.senha}</strong>
          </p>
          <h2 style={{ fontSize: "12pt", marginTop: "6mm" }}>Equipe (celular de cada pessoa)</h2>
          <p style={{ fontSize: "12pt" }}>
            Código da empresa: <strong style={{ fontFamily: "monospace" }}>{conta.data?.codigo ?? ""}</strong>
          </p>
          <p style={{ fontSize: "12pt" }}>
            Link da equipe: <strong style={{ fontFamily: "monospace" }}>{endereco ?? ""}</strong>
          </p>
          <p style={{ fontSize: "10pt", marginTop: "10mm" }}>
            Guarde esta ficha no cofre ou na gaveta. A senha do tablet não pode ser consultada depois:
            se esta folha se perder, gere outra senha no sistema.
          </p>
        </div>
      )}

      {(criar.isError || redefinir.isError) && (
        <p className="text-sm text-destructive">{((criar.error ?? redefinir.error) as Error).message}</p>
      )}
      {ficha.isError && <p className="text-sm text-destructive">{(ficha.error as Error).message}</p>}

      <ul className="space-y-2">
        {lojas.map((l) => {
          const f = porLoja.get(l.lojaid);
          return (
            <li key={l.lojaid} className="space-y-2 rounded-lg border border-border bg-card p-3">
              <div className="flex flex-wrap items-start justify-between gap-2">
                <div className="min-w-0 space-y-1">
                  <p className="font-medium">{l.nome}</p>
                  {f ? (
                    <>
                      <p className="flex flex-wrap items-center gap-2 text-sm">
                        <span className="text-muted-foreground">Usuário:</span>
                        <span className="break-all font-mono text-xs">{f.usuario ?? "—"}</span>
                        {f.usuario && <Copiar texto={f.usuario} />}
                      </p>
                      <p className="text-xs text-muted-foreground">
                        Último uso: {quando(f.ultimoacesso)} ·{" "}
                        {f.aparelhos === 0
                          ? "nenhum aparelho aberto agora"
                          : `${f.aparelhos} ${f.aparelhos === 1 ? "aparelho aberto" : "aparelhos abertos"}`}
                      </p>
                      {f.historico.length > 0 && (
                        <ul className="text-xs text-muted-foreground">
                          {f.historico.slice(0, 3).map((h, i) => (
                            <li key={i}>
                              {h.evento === "criado" ? "Acesso criado" : "Senha nova gerada"} em{" "}
                              {new Date(h.em).toLocaleString("pt-BR")}
                              {h.quem ? ` por ${h.quem}` : ""}
                            </li>
                          ))}
                        </ul>
                      )}
                    </>
                  ) : (
                    <p className="text-xs text-muted-foreground">Sem acesso de tablet</p>
                  )}
                </div>

                {f ? (
                  <button
                    disabled={suspensa || redefinir.isPending}
                    onClick={() => {
                      if (
                        confirm(
                          `Gerar uma senha nova para o tablet da ${l.nome}?\n\n` +
                            "Os tablets dessa loja que estiverem abertos vão precisar entrar de novo, " +
                            "com a senha nova. A senha atual deixa de valer na hora.",
                        )
                      ) {
                        redefinir.mutate({ lojaid: l.lojaid, nome: l.nome });
                      }
                    }}
                    className="shrink-0 rounded-md border border-border px-3 py-1 text-sm disabled:opacity-40"
                  >
                    {redefinir.isPending ? "Gerando..." : "Gerar nova senha"}
                  </button>
                ) : (
                  <button
                    disabled={suspensa || criar.isPending}
                    onClick={() => criar.mutate({ lojaid: l.lojaid, nome: l.nome })}
                    className="shrink-0 rounded-md border border-border px-3 py-1 text-sm disabled:opacity-40"
                  >
                    {criar.isPending ? "Criando..." : "Criar acesso"}
                  </button>
                )}
              </div>
            </li>
          );
        })}
      </ul>
    </section>
  );
}

/** "hoje 14:02", "ontem 09:30" ou a data inteira. */
function quando(iso: string | null) {
  if (!iso) return "nunca entrou";
  const d = new Date(iso);
  const hora = d.toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" });
  const dia = d.toLocaleDateString("pt-BR");
  const hoje = new Date().toLocaleDateString("pt-BR");
  const ontem = new Date(Date.now() - 86400000).toLocaleDateString("pt-BR");
  if (dia === hoje) return `hoje ${hora}`;
  if (dia === ontem) return `ontem ${hora}`;
  return `${dia} ${hora}`;
}

function Copiar({ texto }: { texto: string }) {
  const [feito, setFeito] = useState(false);
  return (
    <button
      onClick={async () => {
        try {
          await navigator.clipboard.writeText(texto);
          setFeito(true);
          setTimeout(() => setFeito(false), 2000);
        } catch {
          setFeito(false);
        }
      }}
      className="rounded-md border border-border px-2 py-0.5 text-xs"
    >
      {feito ? "Copiado!" : "Copiar"}
    </button>
  );
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

