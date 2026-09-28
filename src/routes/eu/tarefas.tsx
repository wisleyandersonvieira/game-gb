// "Minhas tarefas" no celular: o que é dela hoje, e a entrega com foto.
//
// Só aparece o que JÁ É DELA — a tarefa que ela pegou no tablet ou que foi
// atribuída ao nome dela. A fila da loja não vem para cá: pegar é no tablet.
import { createFileRoute } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useRef, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import {
  autorizacaoDeFotoDoCelular,
  entregarPeloCelular,
  minhasTarefas,
  type MinhaTarefa,
} from "@/servidor/colaborador";
import { autorizacaoDeFotoDoCelularAntiga, entregarPeloCelularAntigo } from "@/servidor/colaboradorAntigo";
import { modoDeMedicao, montarDetalhes, montarEtapas, type CaminhoMedido, type TemposDoTablet } from "@/painel/medicaoDoTablet";
import { registrarMedidaDoCelular } from "@/painel/medidasDoCelular";
import { reduzirFoto, type FotoPreparada } from "@/painel/reduzirFoto";
import { OPERACIONAL } from "@/ui/prazos";

export const Route = createFileRoute("/eu/tarefas")({ component: Tarefas });

const FAIXA: Record<MinhaTarefa["situacao"], { texto: string; cor: string }> = {
  a_fazer: { texto: "A fazer", cor: "bg-primary/15 text-primary" },
  esperando: { texto: "Esperando o gestor", cor: "bg-amber-500/15 text-amber-600 dark:text-amber-400" },
  aprovada: { texto: "Aprovada", cor: "bg-emerald-500/15 text-emerald-600 dark:text-emerald-400" },
  recusada: { texto: "Recusada", cor: "bg-destructive/15 text-destructive" },
};

function hora(iso: string | null) {
  if (!iso) return "";
  return new Date(iso).toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" });
}

function Tarefas() {
  const [entregando, setEntregando] = useState<MinhaTarefa | null>(null);
  const [recado, setRecado] = useState<string | null>(null);

  const tarefas = useQuery({
    queryKey: ["eu-tarefas"],
    queryFn: () => minhasTarefas(),
    staleTime: OPERACIONAL,
    refetchOnWindowFocus: true,
  });

  const lista = tarefas.data ?? [];

  // A internet caiu depois de a entrega chegar ao servidor (a resposta se
  // perdeu no caminho): a lista recarregada já mostra a tarefa esperando o
  // gestor. A janela fecha e a pessoa sabe que chegou — em vez de tentar de
  // novo e ouvir que já foi entregue.
  useEffect(() => {
    if (!entregando) return;
    const agora = lista.find((t) => t.atribuicaoid === entregando.atribuicaoid);
    if (agora && (agora.situacao === "esperando" || agora.situacao === "aprovada")) {
      setEntregando(null);
      setRecado("Sua entrega chegou. Agora é com o gestor.");
    }
  }, [lista, entregando]);

  return (
    <div className="space-y-4">
      <h1 className="font-display text-2xl font-semibold">Minhas tarefas</h1>
      {recado && (
        <p className="rounded-xl bg-emerald-500/15 p-3 text-sm text-emerald-700 dark:text-emerald-300">{recado}</p>
      )}

      {tarefas.isLoading ? (
        <p className="text-sm text-muted-foreground">Carregando…</p>
      ) : lista.length === 0 ? (
        <p className="rounded-2xl border border-border bg-card p-5 text-sm text-muted-foreground">
          Nenhuma tarefa sua hoje. Pegue uma no tablet da loja.
        </p>
      ) : (
        <ul className="space-y-3">
          {lista.map((t) => {
            const f = FAIXA[t.situacao];
            return (
              <li key={t.atribuicaoid} className="rounded-2xl border border-border bg-card p-4">
                <div className="flex items-start justify-between gap-3">
                  <p className="font-medium leading-snug">{t.titulo}</p>
                  <span className="shrink-0 tabular-nums text-sm text-muted-foreground">+{t.pontos}</span>
                </div>
                <p className="mt-1 text-xs text-muted-foreground">
                  {t.loja}
                  {t.pegaem ? ` · você pegou às ${hora(t.pegaem)}` : ""}
                </p>
                <div className="mt-3 flex items-center justify-between gap-3">
                  <span className={`rounded-full px-2.5 py-1 text-xs font-medium ${f.cor}`}>
                    {/* Antes da hora, a tarefa aparece mas ainda não dá para entregar. */}
                    {t.liberada ? f.texto : `a partir das ${hora(t.liberaas)}`}
                  </span>
                  {/* Sem aceite no tablet, nao ha o que entregar: o banco
                      recusa, e a tela diz por que. */}
                  {t.liberada && !t.pegaem && (t.situacao === "a_fazer" || t.situacao === "recusada") ? (
                    <span className="text-xs text-muted-foreground">Aceite no tablet da loja</span>
                  ) : t.liberada && t.pegaem && (t.situacao === "a_fazer" || t.situacao === "recusada") ? (
                    <button
                      onClick={() => {
                        setRecado(null);
                        setEntregando(t);
                      }}
                      className="rounded-xl bg-primary px-4 py-2.5 text-sm font-medium text-primary-foreground"
                    >
                      Entregar
                    </button>
                  ) : null}
                </div>
              </li>
            );
          })}
        </ul>
      )}

      {entregando ? <Entregar tarefa={entregando} fechar={() => setEntregando(null)} /> : null}
    </div>
  );
}

/** A internet caiu no meio: o navegador nem recebeu resposta do servidor. */
function ehErroDeRede(e: unknown) {
  const m = e instanceof Error ? e.message : String(e);
  return e instanceof TypeError || /failed to fetch|networkerror|load failed|network|conex/i.test(m);
}

const SEM_INTERNET =
  "A internet caiu no meio do envio. A foto e o que você escreveu continuam aqui: quando a conexão voltar, toque em “Enviar entrega” de novo.";

type Autorizacao = Awaited<ReturnType<typeof autorizacaoDeFotoDoCelular>>;

/**
 * A janela de entrega — o MESMO caminho do tablet (29/09/2026): a autorização
 * de envio é pedida quando a janela abre, a foto é reduzida quando é escolhida
 * (1600 px, qualidade 80, alvo de 400 KB, o mesmo reduzirFoto), e a resposta
 * da entrega já traz a lista atualizada. Com `?medir=antigo`, faz como antes
 * (foto inteira, autorização depois do toque, recarga da lista à parte), para
 * comparar no mesmo aparelho.
 */
function Entregar({ tarefa, fechar }: { tarefa: MinhaTarefa; fechar: () => void }) {
  const qc = useQueryClient();
  const [arquivo, setArquivo] = useState<File | null>(null);
  const [observacao, setObservacao] = useState("");
  const [etapa, setEtapa] = useState<string | null>(null);
  const [medicao] = useState<CaminhoMedido | null>(() => modoDeMedicao(undefined, "celular"));
  const antigo = medicao === "antigo";

  // Adiantar o que não depende do toque: a autorização quando a janela abre,
  // a redução quando a foto é escolhida. Nada disso sobe a foto nem grava.
  const preparo = useRef<{ autorizacao: Promise<Autorizacao | null> | null; pedidaEm: number; arquivo: File | null; foto: Promise<FotoPreparada> | null }>({
    autorizacao: null,
    pedidaEm: 0,
    arquivo: null,
    foto: null,
  });
  useEffect(() => {
    if (antigo) return;
    preparo.current.autorizacao = autorizacaoDeFotoDoCelular({ data: { atribuicaoid: tarefa.atribuicaoid } }).catch(() => null);
    preparo.current.pedidaEm = Date.now();
  }, [tarefa.atribuicaoid, antigo]);
  useEffect(() => {
    if (antigo || !arquivo || preparo.current.arquivo === arquivo) return;
    preparo.current.arquivo = arquivo;
    preparo.current.foto = reduzirFoto(arquivo);
  }, [arquivo, antigo]);

  const enviar = useMutation({
    mutationFn: async () => {
      const inicio = performance.now();
      const cliente: Omit<TemposDoTablet, "desenho"> = { chamada: 0 };
      let caminho: string | null = null;
      let bilhete: string | null = null;

      if (arquivo) {
        setEtapa("enviando a foto…");
        let t = performance.now();
        const p = preparo.current;
        const foto: FotoPreparada = antigo
          ? { arquivo, reduzida: false, original: arquivo.size, enviada: arquivo.size }
          : await (p.arquivo === arquivo && p.foto ? p.foto : reduzirFoto(arquivo));
        cliente.fotoReducao = performance.now() - t;
        cliente.fotoOriginalKb = Math.round(foto.original / 1024);
        cliente.fotoEnviadaKb = Math.round(foto.enviada / 1024);

        // A autorização pedida antes, se ainda estiver no prazo (o bilhete vale
        // 10 minutos). Cada uma serve para UM envio: a próxima tentativa pede
        // outra.
        t = performance.now();
        const adiantada = !antigo && p.autorizacao && Date.now() - p.pedidaEm < 8 * 60_000 ? p.autorizacao : null;
        p.autorizacao = null;
        const a =
          (adiantada && (await adiantada)) ||
          (antigo
            ? await autorizacaoDeFotoDoCelularAntiga({ data: { atribuicaoid: tarefa.atribuicaoid } })
            : await autorizacaoDeFotoDoCelular({ data: { atribuicaoid: tarefa.atribuicaoid } }));
        cliente.fotoAutorizacao = performance.now() - t;

        t = performance.now();
        const { error } = await supabase.storage.from("entregas").uploadToSignedUrl(a.caminho, a.token, foto.arquivo);
        cliente.fotoEnvio = performance.now() - t;
        if (error) throw new Error("A foto não subiu. Confira a internet e toque em “Enviar entrega” de novo.");
        caminho = a.caminho;
        bilhete = a.bilhete;
      }

      setEtapa("registrando…");
      const dados = { atribuicaoid: tarefa.atribuicaoid, caminho, bilhete, observacao: observacao.trim() || null };
      const t = performance.now();
      if (antigo) {
        const r = await entregarPeloCelularAntigo({ data: dados });
        cliente.chamada = performance.now() - t;
        const tr = performance.now();
        const tarefas = await minhasTarefas();
        cliente.recarga = performance.now() - tr;
        return { tarefas, tempos: r.tempos, onde: r.onde, cliente, inicio };
      }
      const r = await entregarPeloCelular({ data: dados });
      cliente.chamada = performance.now() - t;
      return { tarefas: r.tarefas, tempos: r.tempos, onde: r.onde, cliente, inicio };
    },
    onSuccess: (r) => {
      // A lista já veio na resposta: a tela muda AGORA, sem outra ida.
      qc.setQueryData(["eu-tarefas"], r.tarefas);
      qc.invalidateQueries({ queryKey: ["eu-inicio"] });
      setEtapa(null);
      fechar();
      if (medicao) {
        const aposResposta = performance.now();
        requestAnimationFrame(() =>
          requestAnimationFrame(() => {
            const fim = performance.now();
            const cliente = { ...r.cliente, desenho: fim - aposResposta };
            registrarMedidaDoCelular({
              quando: Date.now(),
              acao: "entrega",
              caminho: medicao,
              total: Math.round(fim - r.inicio),
              etapas: montarEtapas("entrega", cliente, r.tempos, "celular"),
              detalhes: montarDetalhes(cliente, r.onde, "celular"),
            });
          }),
        );
      }
    },
    onError: () => {
      setEtapa(null);
      // A lista vem de novo: se a entrega chegou e só a resposta se perdeu, a
      // tela mostra (e a janela fecha, lá em cima).
      qc.invalidateQueries({ queryKey: ["eu-tarefas"] });
    },
  });

  const erro = enviar.isError ? (ehErroDeRede(enviar.error) ? SEM_INTERNET : (enviar.error as Error).message) : null;

  return (
    <div className="fixed inset-0 z-20 flex items-end bg-black/50" onClick={enviar.isPending ? undefined : fechar}>
      <div
        className="max-h-[92vh] w-full overflow-y-auto rounded-t-3xl bg-background p-5 pb-[max(1.25rem,env(safe-area-inset-bottom))]"
        onClick={(e) => e.stopPropagation()}
      >
        <h2 className="font-display text-xl font-semibold">{tarefa.titulo}</h2>

        <p className="mt-3 text-sm text-muted-foreground">
          Tire a foto <strong className="text-foreground">agora</strong>, com a tarefa pronta na sua frente. Foto tirada
          antes, ou escolhida da galeria, pode ser recusada.
        </p>

        <label className="mt-4 block">
          <span className="text-sm font-medium">Foto</span>
          <input
            type="file"
            accept="image/*"
            capture="environment"
            disabled={enviar.isPending}
            onChange={(e) => setArquivo(e.target.files?.[0] ?? null)}
            className="mt-1.5 block w-full rounded-xl border border-border p-3 text-sm file:mr-3 file:rounded-lg file:border-0 file:bg-muted file:px-3 file:py-2 file:text-sm"
          />
        </label>

        <label className="mt-4 block">
          <span className="text-sm font-medium">Observação (opcional)</span>
          <textarea
            value={observacao}
            onChange={(e) => setObservacao(e.target.value)}
            disabled={enviar.isPending}
            rows={3}
            className="mt-1.5 w-full rounded-xl border border-border bg-background p-3 text-sm"
            placeholder="Algo que o gestor precise saber"
          />
        </label>

        {erro ? <p className="mt-3 rounded-xl bg-destructive/10 p-3 text-sm text-destructive">{erro}</p> : null}

        <div className="mt-5 flex gap-3">
          <button
            onClick={fechar}
            disabled={enviar.isPending}
            className="flex-1 rounded-xl border border-border px-4 py-3 text-sm disabled:opacity-60"
          >
            Cancelar
          </button>
          <button
            onClick={() => enviar.mutate()}
            disabled={enviar.isPending}
            className="flex-1 rounded-xl bg-primary px-4 py-3 text-sm font-medium text-primary-foreground disabled:opacity-60"
          >
            {enviar.isPending ? (etapa ?? "enviando…") : "Enviar entrega"}
          </button>
        </div>
      </div>
    </div>
  );
}
