// Ranking: meses já fechados (histórico gravado pela rotina do dia 1).
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Botao } from "@/ui/Botao";
import { TabelaResponsiva } from "@/ui/TabelaResponsiva";

type Fechamento = {
  fechamentoid: number;
  ano: number;
  mes: number;
  versao: number;
  situacao: "provisorio" | "definitivo" | "substituido";
  origem: string;
  motivo: string | null;
  fechadoem: string;
  definitivoem: string | null;
  substituidoem: string | null;
};
type Linha = {
  historicoid: number;
  posicao: number | null;
  nomefuncionario: string | null;
  nota: number;
  confiabilidade: number;
  esforco: number;
  pontosganhos: number | null;
  pontospossiveis: number | null;
};

const MESES = ["janeiro", "fevereiro", "março", "abril", "maio", "junho", "julho", "agosto", "setembro", "outubro", "novembro", "dezembro"];
const MEDALHAS = ["🥇", "🥈", "🥉"];
const dataHora = (iso: string) =>
  new Date(iso).toLocaleString("pt-BR", { timeZone: "America/Sao_Paulo", day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit" });
const num = (v: number) => Number(v).toLocaleString("pt-BR", { maximumFractionDigits: 1 });
const nomeMes = (f: { ano: number; mes: number }) => `${MESES[f.mes - 1]} de ${f.ano}`;

export function MesesFechados({ lojaid, master }: { lojaid: number | null; master: boolean }) {
  const qc = useQueryClient();
  const [escolhido, setEscolhido] = useState<number | null>(null);

  const fechamentos = useQuery({
    queryKey: ["fechamentos"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("fechamentosmensais")
        .select("fechamentoid, ano, mes, versao, situacao, origem, motivo, fechadoem, definitivoem, substituidoem")
        .order("ano", { ascending: false })
        .order("mes", { ascending: false })
        .order("versao", { ascending: false });
      if (error) throw error;
      return (data ?? []) as Fechamento[];
    },
  });

  const todos = fechamentos.data ?? [];
  const valendo = todos.filter((f) => f.situacao !== "substituido");
  useEffect(() => {
    if (escolhido === null && valendo.length > 0) setEscolhido(valendo[0].fechamentoid);
  }, [escolhido, valendo]);
  const atual = todos.find((f) => f.fechamentoid === escolhido) ?? null;
  const versoes = atual ? todos.filter((f) => f.ano === atual.ano && f.mes === atual.mes) : [];

  const linhas = useQuery({
    queryKey: ["fechamento-linhas", escolhido, lojaid],
    enabled: escolhido !== null,
    queryFn: async () => {
      let q = supabase
        .from("historicoranking")
        .select("historicoid, posicao, nomefuncionario, nota, confiabilidade, esforco, pontosganhos, pontospossiveis")
        .eq("fechamentoid", escolhido as number)
        .order("posicao");
      q = lojaid === null ? q.is("lojaid", null) : q.eq("lojaid", lojaid);
      const { data, error } = await q;
      if (error) throw error;
      return (data ?? []) as Linha[];
    },
  });

  const refazer = useMutation({
    mutationFn: async (motivo: string) => {
      if (!atual) return null;
      const { data, error } = await supabase.rpc("refazer_fechamento", { p_ano: atual.ano, p_mes: atual.mes, p_motivo: motivo });
      if (error) throw error;
      return data as number;
    },
    onSuccess: (novo) => {
      if (novo) setEscolhido(novo);
      qc.invalidateQueries({ queryKey: ["fechamentos"] });
      qc.invalidateQueries({ queryKey: ["fechamento-linhas"] });
    },
  });

  function pedirMotivo() {
    const motivo = window.prompt("Por que refazer o fechamento? (fica registrado)");
    if (motivo === null) return;
    if (!motivo.trim()) {
      window.alert("O motivo é obrigatório.");
      return;
    }
    refazer.mutate(motivo.trim());
  }

  if (fechamentos.isLoading) return <p className="text-muted-foreground">Carregando...</p>;
  if (fechamentos.isError) return <p className="text-sm text-destructive">{(fechamentos.error as Error).message}</p>;
  if (valendo.length === 0) {
    return (
      <p className="rounded-xl border border-dashed border-border px-4 py-6 text-center text-sm text-muted-foreground">
        Nenhum mês fechado ainda. O fechamento roda sozinho no dia 1, para o mês anterior.
      </p>
    );
  }

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-2">
        <select
          value={atual && atual.situacao === "substituido" ? versoes.find((v) => v.situacao !== "substituido")?.fechamentoid : escolhido ?? ""}
          onChange={(e) => setEscolhido(Number(e.target.value))}
          className="rounded-lg border border-border bg-background px-3 py-2 text-sm"
          aria-label="Mês"
        >
          {valendo.map((f) => (
            <option key={f.fechamentoid} value={f.fechamentoid}>
              {nomeMes(f)}
            </option>
          ))}
        </select>
        {atual && (
          <span
            className={`rounded-full px-2.5 py-0.5 text-xs font-semibold ${
              atual.situacao === "definitivo"
                ? "bg-sucesso/15 text-sucesso"
                : atual.situacao === "provisorio"
                  ? "bg-azul-soft text-azul"
                  : "bg-muted text-muted-foreground"
            }`}
          >
            {atual.situacao === "definitivo" ? "Definitivo" : atual.situacao === "provisorio" ? "Provisório" : `Versão ${atual.versao} (substituída)`}
          </span>
        )}
        {master && atual && atual.situacao !== "substituido" && (
          <Botao variante="secundario" tamanho="pequeno" disabled={refazer.isPending} onClick={pedirMotivo}>
            Refazer fechamento
          </Botao>
        )}
      </div>

      {atual && (
        <p className="text-xs text-muted-foreground">
          {atual.situacao === "provisorio"
            ? "Provisório: refeito todo dia até o dia 7, com as entregas e justificativas decididas depois. No dia 8 vira definitivo."
            : atual.situacao === "definitivo"
              ? `Definitivo${atual.definitivoem ? ` desde ${dataHora(atual.definitivoem)}` : ""}. Só muda se o responsável refizer, com motivo.`
              : `Esta versão foi substituída em ${atual.substituidoem ? dataHora(atual.substituidoem) : "—"}.`}{" "}
          {lojaid === null
            ? "Geral da conta: soma todas as lojas."
            : "Por loja: cada ponto conta na loja em que a tarefa foi feita."}
        </p>
      )}
      {refazer.isError && <p className="text-sm text-destructive">{(refazer.error as Error).message}</p>}

      <TabelaResponsiva
        linhas={linhas.data ?? []}
        chave={(l) => l.historicoid}
        vazio={linhas.isLoading ? "Carregando..." : "Ninguém pontuou nesse mês, nesta loja."}
        colunas={[
          { titulo: "Posição", valor: (l) => MEDALHAS[(l.posicao ?? 0) - 1] ?? `${l.posicao}º`, classe: () => "w-16" },
          { titulo: "Pessoa", principal: true, valor: (l) => l.nomefuncionario ?? "—" },
          { titulo: "Nota", alinhar: "direita", valor: (l) => num(l.nota), classe: () => "font-semibold" },
          { titulo: "Confiabilidade", alinhar: "direita", valor: (l) => `${num(l.confiabilidade)}%` },
          { titulo: "Esforço", alinhar: "direita", valor: (l) => `${num(l.esforco)}%` },
          { titulo: "Pontos", alinhar: "direita", valor: (l) => `${l.pontosganhos ?? 0} de ${l.pontospossiveis ?? 0} possíveis` },
        ]}
      />

      {versoes.length > 1 && (
        <details className="text-sm">
          <summary className="cursor-pointer text-muted-foreground">Versões deste mês ({versoes.length})</summary>
          <ul className="mt-2 space-y-1">
            {versoes.map((v) => (
              <li key={v.fechamentoid}>
                <button onClick={() => setEscolhido(v.fechamentoid)} className="text-left text-primary hover:underline">
                  Versão {v.versao} · {dataHora(v.fechadoem)} · {v.origem === "master" ? `refeita: ${v.motivo}` : "rotina"}
                  {v.situacao === "substituido" ? " (substituída)" : ""}
                </button>
              </li>
            ))}
          </ul>
        </details>
      )}
    </div>
  );
}
