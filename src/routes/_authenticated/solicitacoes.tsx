import { createFileRoute } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { AvisoSemLoja, useLojaAtiva } from "@/lojas/loja-ativa";
import { Bandeirinha } from "@/ui/Layout";
import { CHAVE_SOLICITACOES, daLoja, useContagemSolicitacoes } from "@/ui/pendencias";
import { Pagina } from "@/ui/Pagina";

export const Route = createFileRoute("/_authenticated/solicitacoes")({
  component: Solicitacoes,
});

/**
 * "2 nesta loja · 3 em outras lojas".
 *
 * A bandeirinha do menu soma todas as lojas; as abas contam só a loja do
 * seletor. Sem esta linha os dois números parecem brigar. Cada loja é um
 * botão: clicar troca o seletor do topo e a tela passa a ser dela.
 */
function Conciliacao({ lojaid }: { lojaid: number }) {
  const { lojas, escolherLoja } = useLojaAtiva();
  const contagem = useContagemSolicitacoes();
  const aqui = daLoja(contagem, lojaid).aResolver;
  const outras = contagem.total - aqui;
  if (outras <= 0) return null;

  const detalhe = lojas
    .filter((l) => l.lojaid !== lojaid)
    .map((l) => ({ loja: l, quantos: daLoja(contagem, l.lojaid).aResolver }))
    .filter((x) => x.quantos > 0);

  return (
    <div className="flex flex-wrap items-center gap-2 text-sm text-muted-foreground">
      <span>
        <strong className="text-foreground">{aqui}</strong> a resolver nesta loja
      </span>
      <span aria-hidden>·</span>
      <span>
        <strong className="text-foreground">{outras}</strong> em outras lojas:
      </span>
      {detalhe.map(({ loja, quantos }) => (
        <button
          key={loja.lojaid}
          onClick={() => escolherLoja(loja.lojaid)}
          className="inline-flex items-center gap-1.5 rounded-lg border border-border px-2 py-1 hover:bg-muted"
        >
          {loja.nome}
          <span className="font-semibold text-foreground">{quantos > 99 ? "99+" : quantos}</span>
        </button>
      ))}
    </div>
  );
}

const campo =
  "rounded-lg border border-border bg-background px-3 py-2 text-sm placeholder:text-muted-foreground";

const CATEGORIAS: Record<string, string[]> = {
  Compra: ["Limpeza", "Escritório", "Cozinha", "Outros"],
  Manutencao: ["Predial", "Equipamento", "Outros"],
};

const SITUACOES = ["Aberta", "Em andamento", "Concluída", "Recusada"] as const;

const COR: Record<string, string> = {
  Aberta: "border-azul/40 bg-azul-soft text-azul",
  "Em andamento": "border-primary text-primary",
  Concluída: "border-border text-muted-foreground",
  Recusada: "border-perigo/40 bg-perigo-soft text-perigo",
};

// Quais abas levam número, e de que cor. VERMELHO é cor de urgência: se tudo
// for vermelho, nada chama atenção. Por isso só "A resolver" é vermelha; as
// outras duas são uma contagem discreta. Para mudar de ideia, troque a linha
// da aba aqui — não há nada espalhado pela tela. Aba fora desta lista não
// mostra número nenhum.
const NUMERO_NA_ABA: Record<string, "vermelho" | "cinza"> = {
  abertas: "vermelho",
  Aberta: "cinza",
  "Em andamento": "cinza",
};

/** A contagem discreta das abas Aberta e Em andamento. Some quando zera. */
function Discreta({ quantos }: { quantos: number }) {
  if (quantos <= 0) return null;
  return (
    <span
      aria-label={`${quantos} nesta situação`}
      className="inline-flex h-5 min-w-5 items-center justify-center rounded-full bg-muted px-1.5 text-xs font-semibold text-muted-foreground"
    >
      {quantos > 99 ? "99+" : quantos}
    </span>
  );
}

function dataHora(iso: string) {
  return new Date(iso).toLocaleString("pt-BR", {
    timeZone: "America/Sao_Paulo",
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

function Solicitacoes() {
  const { lojas, lojaAtiva, loja, carregando } = useLojaAtiva();

  return (
    <Pagina titulo="Solicitações">
      {carregando ? (
        <p className="text-muted-foreground">Carregando...</p>
      ) : lojas.length === 0 || lojaAtiva === null ? (
        <AvisoSemLoja />
      ) : (
        <>
          <p className="text-sm text-muted-foreground">
            Pedidos de compra e de manutenção da loja <strong>{loja?.nome}</strong>. Por enquanto o gestor registra; com o bot,
            os líderes pedem direto (e a foto da manutenção vem junto).
          </p>
          <Conciliacao lojaid={lojaAtiva} />
          <Abrir lojaid={lojaAtiva} />
          <Lista lojaid={lojaAtiva} />
        </>
      )}
    </Pagina>
  );
}

function Abrir({ lojaid }: { lojaid: number }) {
  const qc = useQueryClient();
  const [tipo, setTipo] = useState<"Compra" | "Manutencao">("Compra");
  const [categoria, setCategoria] = useState("Limpeza");
  const [funcionarioid, setFuncionarioid] = useState<number | "">("");
  const [descricao, setDescricao] = useState("");
  const [quantidade, setQuantidade] = useState("");
  const [unidade, setUnidade] = useState("");
  const [recado, setRecado] = useState<string | null>(null);

  const pessoas = useQuery({
    queryKey: ["pessoas-da-loja-solicitacao", lojaid],
    queryFn: async () => {
      const [{ data: vinculos, error }, { data: gente }] = await Promise.all([
        supabase.from("funcionarioslojas").select("funcionarioid").eq("lojaid", lojaid).eq("ativo", true),
        supabase.from("funcionarios").select("funcionarioid, nomecompleto, ativo"),
      ]);
      if (error) throw error;
      const daLoja = new Set((vinculos ?? []).map((v) => v.funcionarioid));
      return (gente ?? [])
        .filter((p) => p.ativo && daLoja.has(p.funcionarioid))
        .map((p) => ({ funcionarioid: p.funcionarioid, nome: p.nomecompleto }))
        .sort((a, b) => a.nome.localeCompare(b.nome));
    },
  });

  const abrir = useMutation({
    mutationFn: async () => {
      if (funcionarioid === "") throw new Error("Escolha quem pediu.");
      const qtd = quantidade.trim() === "" ? null : Number(quantidade.replace(",", "."));
      if (qtd !== null && !(qtd > 0)) throw new Error("A quantidade precisa ser maior que zero.");
      const { error } = await supabase.rpc("abrir_solicitacao", {
        p_lojaid: lojaid,
        p_funcionarioid: funcionarioid,
        p_tipo: tipo,
        p_categoria: categoria,
        p_descricao: descricao,
        p_quantidade: tipo === "Compra" && qtd !== null ? qtd : undefined,
        p_unidade: tipo === "Compra" ? unidade : undefined,
      });
      if (error) throw error;
    },
    onSuccess: () => {
      setRecado("Solicitação aberta.");
      setDescricao("");
      setQuantidade("");
      setUnidade("");
      qc.invalidateQueries({ queryKey: ["solicitacoes", lojaid] });
      // Abrir, concluir ou recusar muda os números do menu e das abas.
      qc.invalidateQueries({ queryKey: CHAVE_SOLICITACOES });
    },
  });

  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        setRecado(null);
        abrir.mutate();
      }}
      className="space-y-3 rounded-xl border border-border bg-card p-4"
    >
      <p className="text-sm font-semibold">Nova solicitação</p>
      <div className="flex flex-wrap gap-4 text-sm">
        {(["Compra", "Manutencao"] as const).map((t) => (
          <label key={t} className="flex items-center gap-2">
            <input
              type="radio"
              checked={tipo === t}
              onChange={() => {
                setTipo(t);
                setCategoria(CATEGORIAS[t][0]);
              }}
            />
            {t === "Compra" ? "🛒 Compra" : "🔧 Manutenção"}
          </label>
        ))}
      </div>
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
        <select
          required
          value={funcionarioid}
          onChange={(e) => setFuncionarioid(e.target.value === "" ? "" : Number(e.target.value))}
          className={campo}
        >
          <option value="">Quem pediu...</option>
          {(pessoas.data ?? []).map((p) => (
            <option key={p.funcionarioid} value={p.funcionarioid}>
              {p.nome}
            </option>
          ))}
        </select>
        <select value={categoria} onChange={(e) => setCategoria(e.target.value)} className={campo}>
          {CATEGORIAS[tipo].map((c) => (
            <option key={c}>{c}</option>
          ))}
        </select>
        <input
          required
          placeholder={tipo === "Compra" ? "Item (ex.: Detergente)" : "O que precisa de conserto (ex.: pia vazando)"}
          value={descricao}
          onChange={(e) => setDescricao(e.target.value)}
          className={`${campo} sm:col-span-2`}
        />
        {tipo === "Compra" && (
          <div className="flex gap-2 sm:col-span-2">
            <input
              inputMode="decimal"
              placeholder="Quantidade"
              value={quantidade}
              onChange={(e) => setQuantidade(e.target.value)}
              className={`${campo} w-28 shrink-0`}
            />
            <input
              placeholder="Unidade (ex.: litros, caixas)"
              maxLength={20}
              value={unidade}
              onChange={(e) => setUnidade(e.target.value)}
              className={`${campo} min-w-0 flex-1`}
            />
          </div>
        )}
      </div>
      <button
        type="submit"
        disabled={abrir.isPending}
        className="rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground disabled:opacity-60"
      >
        {abrir.isPending ? "Abrindo..." : "Abrir solicitação"}
      </button>
      {recado && <p className="text-sm text-sucesso">{recado}</p>}
      {abrir.isError && <p className="text-sm text-destructive">{(abrir.error as Error).message}</p>}
    </form>
  );
}

type Solicitacao = {
  solicitacaoid: number;
  tipo: string;
  categoria: string | null;
  descricao: string | null;
  quantidade: number | null;
  unidade: string | null;
  status: string;
  motivorecusa: string | null;
  datasolicitacao: string;
  funcionarioid: number | null;
  /** O que a pessoa escreveu junto do pedido. Vazio nos pedidos antigos. */
  observacao: string | null;
};

type Mudanca = {
  historicoid: number;
  solicitacaoid: number;
  statusanterior: string | null;
  statusnovo: string;
  observacao: string | null;
  alteradoem: string;
};

function Lista({ lojaid }: { lojaid: number }) {
  const qc = useQueryClient();
  const [filtro, setFiltro] = useState<"abertas" | (typeof SITUACOES)[number] | "todas">("abertas");
  const [aberta, setAberta] = useState<number | null>(null);
  const [aviso, setAviso] = useState<{ texto: string; grave: boolean } | null>(null);

  // Os números das abas são da loja que está na tela, porque é o que a tela
  // mostra. Saem da mesma resposta que alimenta a bandeirinha do menu.
  const aqui = daLoja(useContagemSolicitacoes(), lojaid);

  const dados = useQuery({
    queryKey: ["solicitacoes", lojaid],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("solicitacoesinternas")
        .select("solicitacaoid, tipo, categoria, descricao, quantidade, unidade, status, motivorecusa, datasolicitacao, funcionarioid, observacao")
        .eq("lojaid", lojaid)
        .order("datasolicitacao", { ascending: false })
        .limit(300);
      if (error) throw error;
      const [{ data: pessoas }, { data: historico }] = await Promise.all([
        supabase.from("funcionarios").select("funcionarioid, nomecompleto"),
        supabase
          .from("solicitacoeshistorico")
          .select("historicoid, solicitacaoid, statusanterior, statusnovo, observacao, alteradoem")
          .eq("lojaid", lojaid)
          .order("historicoid"),
      ]);
      return {
        lista: (data ?? []) as Solicitacao[],
        nome: new Map((pessoas ?? []).map((p) => [p.funcionarioid, p.nomecompleto])),
        historico: (historico ?? []) as Mudanca[],
      };
    },
  });

  const mudar = useMutation({
    mutationFn: async (p: { id: number; status: string; observacao?: string }) => {
      const { error } = await supabase.rpc("mudar_situacao_solicitacao", {
        p_solicitacaoid: p.id,
        p_status: p.status,
        p_observacao: p.observacao,
      });
      if (error) throw error;
      return p.status;
    },
    onSuccess: (status) => {
      setAviso({ texto: `Situação: ${status}.`, grave: false });
      qc.invalidateQueries({ queryKey: ["solicitacoes", lojaid] });
      // Abrir, concluir ou recusar muda os números do menu e das abas.
      qc.invalidateQueries({ queryKey: CHAVE_SOLICITACOES });
    },
    onError: (e) => setAviso({ texto: (e as Error).message, grave: true }),
  });

  function comTexto(id: number, status: string) {
    const recusa = status === "Recusada";
    const texto = window.prompt(recusa ? "Por que está recusando?" : "Observação (opcional):");
    if (texto === null) return;
    if (recusa && !texto.trim()) {
      setAviso({ texto: "Para recusar, informe o motivo.", grave: true });
      return;
    }
    mudar.mutate({ id, status, observacao: texto.trim() || undefined });
  }

  const lista = (dados.data?.lista ?? []).filter((s) =>
    filtro === "todas" ? true : filtro === "abertas" ? ["Aberta", "Em andamento"].includes(s.status) : s.status === filtro,
  );

  return (
    <section className="space-y-3">
      <div className="flex flex-wrap gap-1">
        {(["abertas", ...SITUACOES, "todas"] as const).map((f) => {
          const cor = NUMERO_NA_ABA[f];
          const quantos =
            f === "abertas" ? aqui.aResolver : f === "Aberta" ? aqui.abertas : f === "Em andamento" ? aqui.andamento : 0;
          return (
            <button
              key={f}
              onClick={() => setFiltro(f)}
              className={`inline-flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-sm ${filtro === f ? "bg-card font-semibold" : "text-muted-foreground"}`}
            >
              {f === "abertas" ? "A resolver" : f === "todas" ? "Todas" : f}
              {cor === "vermelho" && <Bandeirinha quantos={quantos} />}
              {cor === "cinza" && <Discreta quantos={quantos} />}
            </button>
          );
        })}
      </div>

      {aviso && (
        <p className={`rounded-lg border bg-card px-4 py-3 text-sm ${aviso.grave ? "border-destructive text-destructive" : "border-border"}`}>
          {aviso.texto}
        </p>
      )}
      {dados.isLoading && <p className="text-muted-foreground">Carregando...</p>}
      {dados.isError && <p className="text-sm text-destructive">{(dados.error as Error).message}</p>}

      {lista.map((s) => {
        const mudancas = (dados.data?.historico ?? []).filter((h) => h.solicitacaoid === s.solicitacaoid);
        return (
          <div key={s.solicitacaoid} className="space-y-2 rounded-lg border border-border bg-card px-4 py-3">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <p className="font-medium">
                {s.tipo === "Compra" ? "🛒" : "🔧"} {s.descricao}
                {s.quantidade !== null && ` — ${Number(s.quantidade).toLocaleString("pt-BR")} ${s.unidade ?? ""}`}
                <span className={`ml-2 rounded-md border px-2 py-0.5 text-xs font-normal ${COR[s.status] ?? ""}`}>{s.status}</span>
              </p>
              <p className="text-sm text-muted-foreground">
                {/* Os pedidos antigos continuam mostrando a categoria; os do
                    tablet vêm sem, porque ele não pergunta. */}
                {s.categoria && `${s.categoria} · `}
                {s.funcionarioid ? dados.data?.nome.get(s.funcionarioid) : "—"} · {dataHora(s.datasolicitacao)}
              </p>
            </div>
            {s.observacao && <p className="text-sm">“{s.observacao}”</p>}
            {s.motivorecusa && <p className="text-xs text-destructive">Recusada: {s.motivorecusa}</p>}
            <div className="flex flex-wrap gap-2">
              {s.status === "Aberta" && (
                <button onClick={() => comTexto(s.solicitacaoid, "Em andamento")} className="rounded-md border border-border px-3 py-1 text-sm">
                  Começar
                </button>
              )}
              {["Aberta", "Em andamento"].includes(s.status) && (
                <>
                  <button
                    onClick={() => comTexto(s.solicitacaoid, "Concluída")}
                    className="rounded-md bg-primary px-3 py-1 text-sm font-semibold text-primary-foreground"
                  >
                    Concluir
                  </button>
                  <button
                    onClick={() => comTexto(s.solicitacaoid, "Recusada")}
                    className="rounded-md border border-destructive px-3 py-1 text-sm text-destructive"
                  >
                    Recusar
                  </button>
                </>
              )}
              <button
                onClick={() => setAberta(aberta === s.solicitacaoid ? null : s.solicitacaoid)}
                className="rounded-md px-3 py-1 text-sm text-muted-foreground underline"
              >
                {aberta === s.solicitacaoid ? "Esconder histórico" : "Histórico"}
              </button>
            </div>
            {aberta === s.solicitacaoid && (
              <ol className="space-y-1 border-l border-border pl-3 text-xs text-muted-foreground">
                {mudancas.map((m) => (
                  <li key={m.historicoid}>
                    {dataHora(m.alteradoem)} · {m.statusanterior ? `${m.statusanterior} → ` : "Aberta por "}
                    {m.statusanterior ? m.statusnovo : "gestor"}
                    {m.observacao && ` · “${m.observacao}”`}
                  </li>
                ))}
              </ol>
            )}
          </div>
        );
      })}
      {!dados.isLoading && lista.length === 0 && <p className="text-sm text-muted-foreground">Nenhuma solicitação aqui.</p>}
    </section>
  );
}
