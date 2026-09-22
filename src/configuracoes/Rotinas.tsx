// Configurações: situação das rotinas automáticas da conta e "Rodar agora".
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { CircleAlert, CircleCheck } from "lucide-react";
import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Botao } from "@/ui/Botao";
import { TabelaResponsiva } from "@/ui/TabelaResponsiva";

type Execucao = {
  execucaoid: number;
  rotina: string;
  referencia: string | null;
  origem: string;
  recuperado: boolean;
  iniciadoem: string;
  terminadoem: string | null;
  resultado: string;
  detalhe: Record<string, unknown> | null;
  erro: string | null;
};

const NOME: Record<string, string> = {
  lista_do_dia: "Lista de tarefas do dia",
  fechamento_mensal: "Fechamento do ranking",
  conferencia_livro: "Conferência do livro de pontos",
  limpeza: "Limpeza do registro",
  expurgo_fotos: "Expurgo das fotos antigas",
};

const FUSO = "America/Sao_Paulo";
const diaHoje = () => new Intl.DateTimeFormat("en-CA", { timeZone: FUSO }).format(new Date());
const dia = (iso: string) => `${iso.slice(8, 10)}/${iso.slice(5, 7)}/${iso.slice(0, 4)}`;

function quando(iso: string) {
  const d = new Date(iso);
  const hora = d.toLocaleTimeString("pt-BR", { timeZone: FUSO, hour: "2-digit", minute: "2-digit" });
  const data = new Intl.DateTimeFormat("en-CA", { timeZone: FUSO }).format(d);
  return data === diaHoje() ? `hoje ${hora}` : `${dia(data)} ${hora}`;
}

function resumo(e: Execucao): string {
  const d = e.detalhe ?? {};
  if (e.resultado === "erro") {
    if (e.rotina === "conferencia_livro" && d.diferencas) return "Diferença encontrada entre saldo e livro de pontos";
    return e.erro ?? "Erro";
  }
  if (e.rotina === "lista_do_dia") {
    const partes = [`${d.devidas ?? 0} tarefas`, `${d.folgas ?? 0} de folga`];
    if (d.ajuste) partes.unshift(`ajuste: +${d.novos ?? 0}, ${d.cancelados ?? 0} canceladas`);
    return partes.join(" · ");
  }
  if (e.rotina === "fechamento_mensal") return `${d.mes ?? ""}: ${d.acao ?? ""}`;
  if (e.rotina === "conferencia_livro") return `${d.pessoas ?? 0} pessoas conferidas, tudo certo`;
  if (e.rotina === "limpeza") return `${d.apagados ?? 0} registros antigos apagados`;
  if (e.rotina === "expurgo_fotos") {
    if (d.fotos === 0) return `Nenhuma foto passou de ${d.dias ?? 180} dias`;
    return `${d.fotos ?? 0} fotos com mais de ${d.dias ?? 180} dias apagadas`;
  }
  return "";
}

export function Rotinas({ podeRodar }: { podeRodar: boolean }) {
  const qc = useQueryClient();
  const [recado, setRecado] = useState<string | null>(null);

  const execucoes = useQuery({
    queryKey: ["rotinas-execucoes"],
    refetchInterval: 60_000,
    queryFn: async () => {
      const { data, error } = await supabase
        .from("rotinasexecucoes")
        .select("execucaoid, rotina, referencia, origem, recuperado, iniciadoem, terminadoem, resultado, detalhe, erro")
        .order("iniciadoem", { ascending: false })
        .limit(40);
      if (error) throw error;
      return (data ?? []) as unknown as Execucao[];
    },
  });

  const rodar = useMutation({
    mutationFn: async () => {
      const { data, error } = await supabase.rpc("rodar_geracao_hoje");
      if (error) throw error;
      return data as unknown as { hoje: Record<string, number> | null };
    },
    onSuccess: (r) => {
      const h = r?.hoje ?? {};
      setRecado(`Lista de hoje pronta: ${h.devidas ?? 0} tarefas, ${h.folgas ?? 0} de quem está de folga.`);
      for (const k of ["rotinas-execucoes", "painel-inicio", "folga-hoje"]) qc.invalidateQueries({ queryKey: [k] });
    },
  });

  const lista = execucoes.data ?? [];
  const ultima = (rotina: string) => lista.find((e) => e.rotina === rotina);
  const ultimaLista = ultima("lista_do_dia");

  return (
    <section className="space-y-3 rounded-xl border border-border bg-card p-4">
      <div className="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <h2 className="text-lg font-semibold">Rotinas automáticas</h2>
          <p className="text-xs text-muted-foreground">
            Rodam sozinhas no servidor, a cada 5 minutos, no horário de cada rotina (fuso de São Paulo). Nenhuma
            manda mensagem: isso chega com o bot.
          </p>
        </div>
        {podeRodar && (
          <Botao variante="secundario" className="shrink-0 whitespace-nowrap" disabled={rodar.isPending} onClick={() => rodar.mutate()}>
            {rodar.isPending ? "Rodando..." : "Rodar agora"}
          </Botao>
        )}
      </div>
      {podeRodar && (
        <p className="text-xs text-muted-foreground">
          "Rodar agora" gera ou ajusta só a lista de tarefas de hoje. Pode apertar sem medo: nunca duplica nada.
        </p>
      )}
      {recado && <p className="text-sm text-sucesso">{recado}</p>}
      {rodar.isError && <p className="text-sm text-destructive">{(rodar.error as Error).message}</p>}

      <div className="grid gap-2 sm:grid-cols-2">
        {(["lista_do_dia", "fechamento_mensal", "conferencia_livro", "limpeza", "expurgo_fotos"] as const).map((r) => {
          const e = ultima(r);
          const ok = e?.resultado === "ok";
          return (
            <div key={r} className="flex items-start gap-2 rounded-lg border border-border px-3 py-2 text-sm">
              {e ? (
                ok ? (
                  <CircleCheck className="mt-0.5 h-4 w-4 shrink-0 text-sucesso" aria-label="ok" />
                ) : (
                  <CircleAlert className="mt-0.5 h-4 w-4 shrink-0 text-destructive" aria-label="erro" />
                )
              ) : (
                <span className="mt-0.5 h-4 w-4 shrink-0 rounded-full border border-border" aria-hidden />
              )}
              <div className="min-w-0">
                <p className="font-medium">{NOME[r]}</p>
                <p className={`text-xs ${e && !ok ? "text-destructive" : "text-muted-foreground"}`}>
                  {e ? `${quando(e.terminadoem ?? e.iniciadoem)} · ${resumo(e)}` : "Ainda não rodou."}
                </p>
              </div>
            </div>
          );
        })}
      </div>
      {!ultimaLista && (
        <p className="text-xs text-muted-foreground">A lista do dia é gerada a partir do horário escolhido abaixo.</p>
      )}

      <details className="text-sm">
        <summary className="cursor-pointer text-muted-foreground">Ver o registro completo (últimas 40)</summary>
        <div className="mt-2">
          <TabelaResponsiva
            linhas={lista}
            chave={(e) => e.execucaoid}
            vazio={execucoes.isLoading ? "Carregando..." : "Nenhuma execução ainda."}
            colunas={[
              { titulo: "Rotina", principal: true, valor: (e) => NOME[e.rotina] ?? e.rotina },
              { titulo: "Quando", valor: (e) => quando(e.terminadoem ?? e.iniciadoem), classe: () => "whitespace-nowrap" },
              { titulo: "Dia", valor: (e) => (e.referencia ? dia(e.referencia) : "—"), classe: () => "whitespace-nowrap" },
              {
                titulo: "Como",
                valor: (e) => (e.recuperado ? "Recuperado" : e.origem === "manual" ? "Rodar agora" : "Automática"),
                classe: (e) => (e.recuperado ? "text-azul" : "text-muted-foreground"),
              },
              {
                titulo: "Resultado",
                valor: (e) => (e.resultado === "ok" ? "✓ " : "✗ ") + resumo(e),
                classe: (e) => (e.resultado === "ok" ? "" : "text-destructive"),
              },
            ]}
          />
        </div>
      </details>
    </section>
  );
}
