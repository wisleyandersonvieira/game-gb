import { createFileRoute } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { AvisoSemLoja, useLojaAtiva } from "@/lojas/loja-ativa";
import { pdfReciboResgate } from "@/rh/pdf";

export const Route = createFileRoute("/_authenticated/premios")({
  component: Premios,
});

const campo =
  "rounded-lg border border-border bg-background px-3 py-2 text-sm placeholder:text-muted-foreground";

const reais = (v: number) =>
  new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(v);

function dataHora(iso: string | null) {
  if (!iso) return "—";
  return new Date(iso).toLocaleString("pt-BR", {
    timeZone: "America/Sao_Paulo",
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

function Premios() {
  const { lojas, carregando } = useLojaAtiva();
  const [aba, setAba] = useState<"resgatar" | "catalogo" | "resgates">("resgatar");

  if (carregando) {
    return (
      <div className="mx-auto max-w-5xl space-y-6">
        <p className="text-muted-foreground">Carregando...</p>
      </div>
    );
  }

  if (lojas.length === 0) {
    return (
      <div className="mx-auto max-w-5xl space-y-6">
        <h1 className="text-2xl font-bold tracking-tight sm:text-3xl">Prêmios</h1>
        <AvisoSemLoja />
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-5xl space-y-6">
      <h1 className="text-2xl font-bold tracking-tight sm:text-3xl">Prêmios</h1>

      <div className="flex gap-2 border-b border-border">
        {(
          [
            ["resgatar", "Registrar resgate"],
            ["resgates", "Resgates"],
            ["catalogo", "Catálogo"],
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

      {aba === "resgatar" && <RegistrarResgate aoRegistrar={() => setAba("resgates")} />}
      {aba === "resgates" && <ListaDeResgates />}
      {aba === "catalogo" && <Catalogo />}
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Dados comuns                                                        */
/* ------------------------------------------------------------------ */

function usePessoas() {
  return useQuery({
    queryKey: ["pessoas-saldo"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("funcionarios")
        .select("funcionarioid, nomecompleto, saldopontos")
        .eq("ativo", true)
        .order("nomecompleto");
      if (error) throw error;
      return data ?? [];
    },
  });
}

function usePremios() {
  return useQuery({
    queryKey: ["premios"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("produtosloja")
        .select("produtoid, nome, descricao, custoempontos, estoquedisponivel, ativo, sistema")
        .order("custoempontos");
      if (error) throw error;
      return data ?? [];
    },
  });
}

function useTaxa() {
  return useQuery({
    queryKey: ["minha-taxa"],
    queryFn: async () => {
      const { data, error } = await supabase.rpc("minha_taxa");
      if (error) throw error;
      return (data as number | null) ?? null;
    },
  });
}

function atualizarTudo(qc: ReturnType<typeof useQueryClient>) {
  for (const k of ["premios", "resgates", "pessoas-saldo", "equipe", "extrato"]) {
    qc.invalidateQueries({ queryKey: [k] });
  }
}

/* ------------------------------------------------------------------ */
/* Registrar resgate (prêmio do catálogo ou abate na comanda)          */
/* ------------------------------------------------------------------ */

function RegistrarResgate({ aoRegistrar }: { aoRegistrar: () => void }) {
  const qc = useQueryClient();
  const { lojaAtiva, loja } = useLojaAtiva();
  const pessoas = usePessoas();
  const premios = usePremios();
  const taxa = useTaxa();

  const [funcionarioid, setFuncionarioid] = useState<number | "">("");
  const [tipo, setTipo] = useState<"premio" | "comanda">("premio");
  const [produtoid, setProdutoid] = useState<number | "">("");
  const [valor, setValor] = useState("");
  const [entregarDepois, setEntregarDepois] = useState(false);
  const [recado, setRecado] = useState<string | null>(null);

  const pessoa = (pessoas.data ?? []).find((p) => p.funcionarioid === funcionarioid);
  const catalogo = (premios.data ?? []).filter((p) => !p.sistema && p.ativo);
  const premio = catalogo.find((p) => p.produtoid === produtoid);
  const valorNumero = Number(valor.replace(",", "."));
  // Só uma prévia: quem calcula de verdade é o banco, com a taxa dele.
  const pontosComanda =
    taxa.data && valorNumero > 0 ? Math.ceil(Math.round(valorNumero * 100) / 100 / taxa.data - 1e-9) : null;

  const registrar = useMutation({
    mutationFn: async () => {
      if (funcionarioid === "") throw new Error("Escolha a pessoa.");
      if (tipo === "premio") {
        if (produtoid === "") throw new Error("Escolha o prêmio.");
        const { error } = await supabase.rpc("registrar_troca", {
          p_funcionarioid: funcionarioid,
          p_produtoid: produtoid,
          p_lojaid: lojaAtiva ?? undefined,
          p_entregar: !entregarDepois,
        });
        if (error) throw error;
        return `${premio?.nome} resgatado por ${pessoa?.nomecompleto}.`;
      }
      if (!(valorNumero > 0)) throw new Error("Informe o valor em reais.");
      const { error } = await supabase.rpc("registrar_troca_por_valor", {
        p_funcionarioid: funcionarioid,
        p_valorreais: valorNumero,
        p_lojaid: lojaAtiva ?? undefined,
        p_entregar: !entregarDepois,
      });
      if (error) throw error;
      return `Abate de ${reais(valorNumero)} na comanda de ${pessoa?.nomecompleto}.`;
    },
    onSuccess: (texto) => {
      setRecado(texto + (entregarDepois ? " Ficou pendente de entrega." : ""));
      setProdutoid("");
      setValor("");
      atualizarTudo(qc);
      aoRegistrar();
    },
  });

  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        setRecado(null);
        registrar.mutate();
      }}
      className="space-y-4 rounded-xl border border-border bg-card p-4"
    >
      <select
        required
        value={funcionarioid}
        onChange={(e) => setFuncionarioid(e.target.value === "" ? "" : Number(e.target.value))}
        className={`${campo} w-full`}
      >
        <option value="">Quem está resgatando...</option>
        {(pessoas.data ?? []).map((p) => (
          <option key={p.funcionarioid} value={p.funcionarioid}>
            {p.nomecompleto} — {p.saldopontos} pontos
          </option>
        ))}
      </select>

      {pessoa && (
        <p className={`text-sm ${pessoa.saldopontos < 0 ? "text-destructive" : "text-muted-foreground"}`}>
          Saldo de {pessoa.nomecompleto}: <strong>{pessoa.saldopontos} pontos</strong>
          {taxa.data ? ` (${reais(pessoa.saldopontos * taxa.data)})` : ""}
          {pessoa.saldopontos < 0 && " — saldo negativo, não pode resgatar."}
        </p>
      )}

      <div className="flex gap-4 text-sm">
        <label className="flex items-center gap-2">
          <input type="radio" checked={tipo === "premio"} onChange={() => setTipo("premio")} />
          Prêmio do catálogo
        </label>
        <label className="flex items-center gap-2">
          <input type="radio" checked={tipo === "comanda"} onChange={() => setTipo("comanda")} />
          Abate na comanda
        </label>
      </div>

      {tipo === "premio" ? (
        <select
          required
          value={produtoid}
          onChange={(e) => setProdutoid(e.target.value === "" ? "" : Number(e.target.value))}
          className={`${campo} w-full`}
        >
          <option value="">Qual prêmio...</option>
          {catalogo.map((p) => {
            const esgotado = p.estoquedisponivel === 0;
            const semSaldo = pessoa ? pessoa.saldopontos < p.custoempontos : false;
            return (
              <option key={p.produtoid} value={p.produtoid} disabled={esgotado || semSaldo}>
                {p.nome} — {p.custoempontos} pontos
                {esgotado ? " · ESGOTADO" : p.estoquedisponivel !== null ? ` · ${p.estoquedisponivel} em estoque` : ""}
                {!esgotado && semSaldo ? " · saldo insuficiente" : ""}
              </option>
            );
          })}
        </select>
      ) : (
        <div className="space-y-1">
          <label className="flex items-center gap-2 text-sm text-muted-foreground">
            Valor a abater (R$):
            <input
              required
              inputMode="decimal"
              placeholder="15,50"
              value={valor}
              onChange={(e) => setValor(e.target.value)}
              className={`${campo} w-32`}
            />
          </label>
          <p className="text-xs text-muted-foreground">
            {taxa.data === null
              ? "A taxa de conversão não está configurada."
              : pontosComanda !== null
                ? `Vai custar ${pontosComanda} pontos (1 ponto = ${reais(taxa.data ?? 0)}, arredondado para cima).`
                : `1 ponto = ${reais(taxa.data ?? 0)}.`}
          </p>
        </div>
      )}

      <label className="flex items-center gap-2 text-sm">
        <input type="checkbox" checked={entregarDepois} onChange={(e) => setEntregarDepois(e.target.checked)} />
        Entregar depois (os pontos e o estoque ficam reservados)
      </label>

      <button
        type="submit"
        disabled={registrar.isPending}
        className="rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground disabled:opacity-50"
      >
        {registrar.isPending ? "Registrando..." : "Registrar resgate"}
      </button>
      <p className="text-xs text-muted-foreground">Retirado na loja {loja?.nome}.</p>

      {recado && <p className="text-sm text-sucesso">{recado}</p>}
      {registrar.isError && <p className="text-sm text-destructive">{(registrar.error as Error).message}</p>}
    </form>
  );
}

/* ------------------------------------------------------------------ */
/* Lista de resgates: entregar, cancelar, estornar                     */
/* ------------------------------------------------------------------ */

const COR_STATUS: Record<string, string> = {
  Pendente: "border-azul/40 bg-azul-soft text-azul",
  Entregue: "border-sucesso text-sucesso",
  Cancelado: "border-border text-muted-foreground",
  Estornado: "border-destructive text-destructive",
};

type Troca = {
  trocaid: number;
  status: string;
  pontos: number;
  datasolicitacao: string;
  motivocancelamento: string | null;
  motivoestorno: string | null;
  pessoa: string;
  premio: string;
  loja: string | null;
};

function ListaDeResgates() {
  const qc = useQueryClient();
  const [aviso, setAviso] = useState<{ texto: string; grave: boolean } | null>(null);

  // Vem por funcao (listar_trocas), para nenhum endereco do navegador levar
  // palavras que bloqueadores de anuncio costumam barrar.
  const resgates = useQuery({
    queryKey: ["resgates"],
    queryFn: async () => {
      const { data, error } = await supabase.rpc("listar_trocas", { p_limite: 100 });
      if (error) throw error;
      return ((data ?? []) as unknown as Troca[]).map((t) => ({
        resgateid: t.trocaid,
        status: t.status,
        pontosgastos: t.pontos,
        datasolicitacao: t.datasolicitacao,
        motivocancelamento: t.motivocancelamento,
        motivoestorno: t.motivoestorno,
        pessoa: t.pessoa,
        premio: t.premio,
        loja: t.loja,
      }));
    },
  });

  const acao = useMutation({
    mutationFn: async (p: { tipo: "entregar" | "cancelar" | "estornar"; resgateid: number; motivo?: string }) => {
      const { error } =
        p.tipo === "entregar"
          ? await supabase.rpc("concluir_troca", { p_resgateid: p.resgateid })
          : p.tipo === "cancelar"
            ? await supabase.rpc("cancelar_troca", { p_resgateid: p.resgateid, p_motivo: p.motivo ?? "" })
            : await supabase.rpc("estornar_troca", { p_resgateid: p.resgateid, p_motivo: p.motivo ?? "" });
      if (error) throw error;
      return p.tipo;
    },
    onSuccess: (tipo) => {
      setAviso({
        texto:
          tipo === "entregar"
            ? "Marcado como entregue."
            : tipo === "cancelar"
              ? "Resgate cancelado: pontos e estoque devolvidos."
              : "Resgate estornado: pontos e estoque devolvidos.",
        grave: false,
      });
      atualizarTudo(qc);
    },
    onError: (e) => setAviso({ texto: (e as Error).message, grave: true }),
  });

  function comMotivo(tipo: "cancelar" | "estornar", resgateid: number) {
    const motivo = window.prompt(
      tipo === "cancelar" ? "Por que está cancelando este resgate?" : "Por que está estornando este resgate?",
    );
    if (motivo === null) return;
    if (motivo.trim() === "") {
      setAviso({ texto: "O motivo é obrigatório.", grave: true });
      return;
    }
    acao.mutate({ tipo, resgateid, motivo: motivo.trim() });
  }

  const lista = resgates.data ?? [];

  return (
    <div className="space-y-2">
      {aviso && (
        <p
          className={`rounded-lg border bg-card px-4 py-3 text-sm ${
            aviso.grave ? "border-destructive text-destructive" : "border-border"
          }`}
        >
          {aviso.texto}
        </p>
      )}
      {resgates.isLoading && <p className="text-muted-foreground">Carregando...</p>}
      {resgates.isError && <p className="text-sm text-destructive">{(resgates.error as Error).message}</p>}

      {lista.map((r) => (
        <div
          key={r.resgateid}
          className="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-border bg-card px-4 py-3"
        >
          <div className="min-w-0">
            <p className="font-medium">
              {r.premio}
              <span className={`ml-2 rounded-md border px-2 py-0.5 text-xs font-normal ${COR_STATUS[r.status] ?? ""}`}>
                {r.status}
              </span>
            </p>
            <p className="text-sm text-muted-foreground">
              {r.pessoa} · −{r.pontosgastos} pontos · {dataHora(r.datasolicitacao)}
              {r.loja && ` · ${r.loja}`}
            </p>
            {r.motivocancelamento && <p className="text-xs text-muted-foreground">Cancelado: {r.motivocancelamento}</p>}
            {r.motivoestorno && <p className="text-xs text-destructive">Estornado: {r.motivoestorno}</p>}
          </div>
          <div className="flex flex-wrap gap-2">
            <button
              onClick={async () => {
                const { data, error } = await supabase.rpc("recibo_resgate", { p_resgateid: r.resgateid });
                if (error || !data) {
                  setAviso({ texto: "Não foi possível gerar o recibo.", grave: true });
                  return;
                }
                await pdfReciboResgate(data as never);
              }}
              className="rounded-md border border-border px-3 py-1 text-sm"
            >
              Recibo (PDF)
            </button>
            {r.status === "Pendente" && (
              <>
                <button
                  onClick={() => acao.mutate({ tipo: "entregar", resgateid: r.resgateid })}
                  className="rounded-md bg-primary px-3 py-1 text-sm font-semibold text-primary-foreground"
                >
                  Entregar
                </button>
                <button onClick={() => comMotivo("cancelar", r.resgateid)} className="rounded-md border border-border px-3 py-1 text-sm">
                  Cancelar
                </button>
              </>
            )}
            {r.status === "Entregue" && (
              <button
                onClick={() => comMotivo("estornar", r.resgateid)}
                className="rounded-md border border-destructive px-3 py-1 text-sm text-destructive"
              >
                Estornar
              </button>
            )}
          </div>
        </div>
      ))}
      {!resgates.isLoading && lista.length === 0 && (
        <p className="text-sm text-muted-foreground">Nenhum resgate ainda.</p>
      )}
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Catálogo de prêmios                                                 */
/* ------------------------------------------------------------------ */

const PREMIO_VAZIO = { nome: "", descricao: "", custoempontos: 50, estoque: "" };

function Catalogo() {
  const qc = useQueryClient();
  const premios = usePremios();
  const [form, setForm] = useState(PREMIO_VAZIO);
  const [editando, setEditando] = useState<number | null>(null);

  function limpar() {
    setForm(PREMIO_VAZIO);
    setEditando(null);
  }

  const salvar = useMutation({
    mutationFn: async () => {
      const estoque = form.estoque.trim() === "" ? null : Number(form.estoque);
      if (estoque !== null && (!Number.isInteger(estoque) || estoque < 0)) {
        throw new Error("Estoque precisa ser um número inteiro, 0 ou mais. Deixe em branco para ilimitado.");
      }
      const dados = {
        nome: form.nome.trim(),
        descricao: form.descricao.trim() || null,
        custoempontos: Number(form.custoempontos),
        estoquedisponivel: estoque,
      };
      const { error } =
        editando === null
          ? await supabase.from("produtosloja").insert(dados)
          : await supabase.from("produtosloja").update(dados).eq("produtoid", editando);
      if (error) throw error;
    },
    onSuccess: () => {
      limpar();
      qc.invalidateQueries({ queryKey: ["premios"] });
    },
  });

  const alternar = useMutation({
    mutationFn: async ({ produtoid, ativo }: { produtoid: number; ativo: boolean }) => {
      const { error } = await supabase.from("produtosloja").update({ ativo }).eq("produtoid", produtoid);
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ["premios"] }),
  });

  const lista = (premios.data ?? []).filter((p) => !p.sistema);

  return (
    <div className="space-y-4">
      <form
        onSubmit={(e) => {
          e.preventDefault();
          salvar.mutate();
        }}
        className="space-y-3 rounded-xl border border-border bg-card p-4"
      >
        <p className="text-sm font-semibold">{editando === null ? "Novo prêmio" : "Editando prêmio"}</p>
        <div className="grid gap-3 md:grid-cols-4">
          <input
            required
            placeholder="Nome do prêmio"
            value={form.nome}
            onChange={(e) => setForm({ ...form, nome: e.target.value })}
            className={`${campo} md:col-span-2`}
          />
          <label className="flex items-center gap-2 text-sm text-muted-foreground">
            Custo:
            <input
              required
              type="number"
              min={1}
              value={form.custoempontos}
              onChange={(e) => setForm({ ...form, custoempontos: Number(e.target.value) })}
              className={`${campo} w-24`}
            />
          </label>
          <label className="flex items-center gap-2 text-sm text-muted-foreground">
            Estoque:
            <input
              type="number"
              min={0}
              placeholder="ilimitado"
              value={form.estoque}
              onChange={(e) => setForm({ ...form, estoque: e.target.value })}
              className={`${campo} w-28`}
            />
          </label>
          <input
            placeholder="Descrição (opcional)"
            value={form.descricao}
            onChange={(e) => setForm({ ...form, descricao: e.target.value })}
            className={`${campo} md:col-span-4`}
          />
        </div>
        <p className="text-xs text-muted-foreground">Estoque em branco = ilimitado. Estoque 0 = esgotado.</p>
        <div className="flex gap-2">
          <button
            type="submit"
            disabled={salvar.isPending}
            className="rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground disabled:opacity-60"
          >
            {editando === null ? "Adicionar" : "Salvar"}
          </button>
          {editando !== null && (
            <button type="button" onClick={limpar} className="rounded-lg border border-border px-4 py-2 text-sm">
              Cancelar
            </button>
          )}
        </div>
        {salvar.isError && <p className="text-sm text-destructive">{(salvar.error as Error).message}</p>}
      </form>

      <div className="space-y-2">
        {lista.map((p) => {
          const esgotado = p.estoquedisponivel === 0;
          return (
            <div
              key={p.produtoid}
              className="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-border bg-card px-4 py-3"
            >
              <div>
                <p className="font-medium">
                  {p.nome}
                  {esgotado && (
                    <span className="ml-2 rounded-md border border-destructive px-2 py-0.5 text-xs font-normal text-destructive">
                      Esgotado
                    </span>
                  )}
                  {!p.ativo && (
                    <span className="ml-2 rounded-md border border-border px-2 py-0.5 text-xs font-normal text-muted-foreground">
                      desativado
                    </span>
                  )}
                </p>
                <p className="text-sm text-muted-foreground">
                  <strong className="text-azul">{p.custoempontos}</strong> pontos ·{" "}
                  {p.estoquedisponivel === null ? "estoque ilimitado" : `${p.estoquedisponivel} em estoque`}
                  {p.descricao && ` · ${p.descricao}`}
                </p>
              </div>
              <div className="flex gap-2">
                <button
                  onClick={() => {
                    setEditando(p.produtoid);
                    setForm({
                      nome: p.nome,
                      descricao: p.descricao ?? "",
                      custoempontos: p.custoempontos,
                      estoque: p.estoquedisponivel === null ? "" : String(p.estoquedisponivel),
                    });
                  }}
                  className="rounded-md border border-border px-3 py-1 text-sm"
                >
                  Editar
                </button>
                <button
                  onClick={() => alternar.mutate({ produtoid: p.produtoid, ativo: !p.ativo })}
                  className="rounded-md border border-border px-3 py-1 text-sm"
                >
                  {p.ativo ? "Desativar" : "Reativar"}
                </button>
              </div>
            </div>
          );
        })}
        {!premios.isLoading && lista.length === 0 && (
          <p className="text-sm text-muted-foreground">Nenhum prêmio cadastrado ainda.</p>
        )}
      </div>
    </div>
  );
}
