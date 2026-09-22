import { createFileRoute } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { AvisoSemLoja, useLojaAtiva } from "@/lojas/loja-ativa";
import { MesesFechados } from "@/ranking/MesesFechados";
import { Pontos } from "@/ui/Pontos";

export const Route = createFileRoute("/_authenticated/ranking")({
  component: Ranking,
});

/** Hoje, no fuso da loja, como AAAA-MM-DD. */
function hojeEmSaoPaulo() {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "America/Sao_Paulo" }).format(new Date());
}

const MEDALHAS = ["🥇", "🥈", "🥉"];

function Ranking() {
  const { lojas, lojaAtiva, loja, carregando } = useLojaAtiva();
  const [periodo, setPeriodo] = useState<"dia" | "mes" | "nota" | "fechados">("dia");
  const [alcance, setAlcance] = useState<"loja" | "conta">("loja");

  const hoje = hojeEmSaoPaulo();
  const de = periodo === "dia" ? hoje : `${hoje.slice(0, 7)}-01`;
  const lojaFiltro = alcance === "loja" ? lojaAtiva : null;

  const ranking = useQuery({
    queryKey: ["ranking", de, hoje, lojaFiltro],
    enabled: lojaAtiva !== null && (periodo === "dia" || periodo === "mes"),
    queryFn: async () => {
      const { data, error } = await supabase.rpc("ranking_pontos", {
        p_de: de,
        p_ate: hoje,
        p_lojaid: lojaFiltro ?? undefined,
      });
      if (error) throw error;
      return data ?? [];
    },
  });

  const master = useQuery({
    queryKey: ["sou-master"],
    queryFn: async () => {
      const { data, error } = await supabase.rpc("sou_master");
      if (error) throw error;
      return data === true;
    },
  });

  if (carregando) {
    return (
      <div className="mx-auto max-w-3xl space-y-6">
        <p className="text-muted-foreground">Carregando...</p>
      </div>
    );
  }

  if (lojas.length === 0) {
    return (
      <div className="mx-auto max-w-3xl space-y-6">
        <h1 className="font-display text-2xl font-semibold tracking-tight sm:text-3xl">Ranking</h1>
        <AvisoSemLoja />
      </div>
    );
  }

  const linhas = ranking.data ?? [];
  const botao = (ativo: boolean) =>
    `rounded-lg px-3 py-1.5 text-sm ${ativo ? "bg-card font-semibold text-foreground" : "text-muted-foreground"}`;

  return (
    <div className="mx-auto max-w-3xl space-y-6">
      <h1 className="font-display text-2xl font-semibold tracking-tight sm:text-3xl">Ranking</h1>

      <div className="flex flex-wrap gap-3 sm:gap-6">
        <div className="flex flex-wrap gap-1 rounded-lg border border-border p-1">
          <button className={botao(periodo === "dia")} onClick={() => setPeriodo("dia")}>
            Hoje
          </button>
          <button className={botao(periodo === "mes")} onClick={() => setPeriodo("mes")}>
            Este mês
          </button>
          <button className={botao(periodo === "nota")} onClick={() => setPeriodo("nota")}>
            Nota do mês
          </button>
          <button className={botao(periodo === "fechados")} onClick={() => setPeriodo("fechados")}>
            Meses fechados
          </button>
        </div>
        <div className="flex gap-1 rounded-lg border border-border p-1">
          <button className={botao(alcance === "loja")} onClick={() => setAlcance("loja")}>
            {loja?.nome ?? "Loja"}
          </button>
          <button className={botao(alcance === "conta")} onClick={() => setAlcance("conta")}>
            Todas as lojas
          </button>
        </div>
      </div>

      {periodo === "fechados" ? (
        <MesesFechados lojaid={lojaFiltro} master={master.data === true} />
      ) : periodo === "nota" ? (
        <NotaDoMes hoje={hoje} lojaid={lojaFiltro} />
      ) : (
        <PontosDoPeriodo
          periodo={periodo}
          alcance={alcance}
          carregando={ranking.isLoading}
          erro={ranking.isError ? (ranking.error as Error).message : null}
          linhas={linhas}
        />
      )}
    </div>
  );
}

type LinhaPontos = { funcionarioid: number; nomecompleto: string; pontos: number; entregas: number };

function PontosDoPeriodo({
  periodo,
  alcance,
  carregando,
  erro,
  linhas,
}: {
  periodo: "dia" | "mes";
  alcance: "loja" | "conta";
  carregando: boolean;
  erro: string | null;
  linhas: LinhaPontos[];
}) {
  return (
    <>
      <p className="text-xs text-muted-foreground">
        Soma dos pontos aprovados {periodo === "dia" ? "hoje" : "neste mês"}, pela data da aprovação.
        {alcance === "conta" && " Quem trabalha em mais de uma loja soma os pontos de todas."}
      </p>

      {carregando && <p className="text-muted-foreground">Carregando...</p>}
      {erro && <p className="text-sm text-destructive">{erro}</p>}

      <ol className="space-y-2">
        {linhas.map((l, i) => (
          <li
            key={l.funcionarioid}
            className="flex items-center justify-between rounded-lg border border-border bg-card px-4 py-3"
          >
            <span className="flex items-center gap-3">
              <span className="w-8 text-center font-mono text-lg tabular-nums">{MEDALHAS[i] ?? `${i + 1}º`}</span>
              <span className="font-medium">{l.nomecompleto}</span>
            </span>
            <span className="text-sm text-muted-foreground">
              <Pontos valor={l.pontos} /> · {l.entregas}{" "}
              {l.entregas === 1 ? "entrega" : "entregas"}
            </span>
          </li>
        ))}
      </ol>

      {!carregando && linhas.length === 0 && (
        <p className="rounded-lg border border-dashed border-border px-4 py-6 text-center text-sm text-muted-foreground">
          Ninguém pontuou {periodo === "dia" ? "hoje" : "neste mês"} ainda.
        </p>
      )}
    </>
  );
}

/** Nota do mês: 50% confiabilidade + 50% esforço (calculada no banco). */
function NotaDoMes({ hoje, lojaid }: { hoje: string; lojaid: number | null }) {
  const [mes, setMes] = useState(hoje.slice(0, 7));
  const [ano, numeroMes] = mes.split("-").map(Number);
  const mesCorrente = mes === hoje.slice(0, 7);
  // Mesma janela do banco: do dia 1 até o fim do mês, ou até ontem no mês corrente.
  const dd = (iso: string) => `${iso.slice(8, 10)}/${iso.slice(5, 7)}/${iso.slice(0, 4)}`;
  const ontem = new Date(`${hoje}T12:00:00Z`);
  ontem.setUTCDate(ontem.getUTCDate() - 1);
  const ontemIso = ontem.toISOString().slice(0, 10);
  const fimDoMes = ano && numeroMes ? new Date(Date.UTC(ano, numeroMes, 0)).toISOString().slice(0, 10) : "";
  const inicio = `${mes}-01`;
  const fim = mesCorrente ? ontemIso : fimDoMes;
  const semDias = mesCorrente && hoje.slice(8, 10) === "01";

  const nota = useQuery({
    queryKey: ["ranking-mensal", mes, lojaid],
    enabled: Boolean(ano && numeroMes),
    queryFn: async () => {
      const { data, error } = await supabase.rpc("ranking_mensal", {
        p_ano: ano,
        p_mes: numeroMes,
        p_lojaid: lojaid ?? undefined,
      });
      if (error) throw error;
      return data ?? [];
    },
  });

  const linhas = nota.data ?? [];
  const pct = (v: number) => `${Number(v).toLocaleString("pt-BR", { maximumFractionDigits: 1 })}%`;

  return (
    <>
      <div className="flex flex-wrap items-center gap-3">
        <label className="flex items-center gap-2 text-sm text-muted-foreground">
          Mês
          <input
            type="month"
            value={mes}
            max={hoje.slice(0, 7)}
            onChange={(e) => setMes(e.target.value)}
            className="rounded-lg border border-border bg-background px-3 py-1.5 text-sm"
          />
        </label>
      </div>

      <div className="space-y-1 text-xs text-muted-foreground">
        <p>
          <strong>Nota = metade confiabilidade + metade esforço.</strong>{" "}
          {semDias
            ? "Hoje é dia 1: a nota deste mês começa a aparecer amanhã."
            : `Contando de ${dd(inicio)} a ${dd(fim)}${mesCorrente ? " (no mês corrente, até ontem; o que for feito hoje entra amanhã)" : ""}.`}
        </p>
        <p>
          <strong>Confiabilidade:</strong> dos pontos que a pessoa podia fazer nas tarefas dela, quanto fez (pelo dia
          do envio). Folga, domingo de folga e afastamento não contam. Os pontos possíveis de cada dia vêm da lista
          do dia, gravada pela rotina: mudar o cadastro hoje não muda os dias que já passaram.
        </p>
        <p>
          <strong>Esforço:</strong> os pontos aprovados no mês comparados com os de quem mais fez. Bônus de conquista não
          entra. Tarefa recebida de quem estava de folga conta aqui, como esforço extra, e não nos pontos possíveis.
        </p>
      </div>

      {nota.isLoading && <p className="text-muted-foreground">Carregando...</p>}
      {nota.isError && <p className="text-sm text-destructive">{(nota.error as Error).message}</p>}

      <ol className="space-y-2">
        {linhas.map((l, i) => (
          <li key={l.funcionarioid} className="rounded-lg border border-border bg-card px-4 py-3">
            <div className="flex items-center justify-between gap-3">
              <span className="flex items-center gap-3">
                <span className="w-8 text-center font-mono text-lg tabular-nums">{MEDALHAS[i] ?? `${i + 1}º`}</span>
                <span className="font-medium">{l.nomecompleto}</span>
              </span>
              <span className="font-mono text-2xl font-medium tabular-nums text-foreground">
                {Number(l.nota).toLocaleString("pt-BR", { maximumFractionDigits: 1 })}
              </span>
            </div>
            <p className="mt-1 pl-11 text-xs text-muted-foreground">
              Confiabilidade {pct(l.confiabilidade)} ({l.pontosregulares} de {l.pontospossiveis} pontos) · Esforço{" "}
              {pct(l.esforco)} ({l.pontosganhos} pontos no mês)
            </p>
          </li>
        ))}
      </ol>

      {!nota.isLoading && linhas.length === 0 && (
        <p className="rounded-lg border border-dashed border-border px-4 py-6 text-center text-sm text-muted-foreground">
          {mesCorrente
            ? semDias
              ? "A nota deste mês começa a aparecer amanhã."
              : `Ninguém com tarefas entre ${dd(inicio)} e ${dd(fim)}. O que foi feito hoje entra na nota amanhã.`
            : "Ninguém com tarefas neste mês."}
        </p>
      )}
    </>
  );
}
