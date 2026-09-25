// Início do celular: o resumo do dia da pessoa.
//
// O saldo aparece SEMPRE em pontos, nunca convertido em reais (decisão do
// Wisley, 26/09/2026): ponto é reconhecimento, não salário. O valor em reais
// só aparece na hora de abater na comanda.
import { createFileRoute, Link } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { meuInicio } from "@/servidor/colaborador";
import { minhasTarefas } from "@/servidor/colaborador";
import { DINHEIRO, OPERACIONAL } from "@/ui/prazos";

export const Route = createFileRoute("/eu/")({ component: Inicio });

function Inicio() {
  // Pontos nunca são reaproveitados: melhor esperar do que mostrar valor velho.
  const eu = useQuery({ queryKey: ["eu-inicio"], queryFn: () => meuInicio(), ...DINHEIRO });
  const tarefas = useQuery({
    queryKey: ["eu-tarefas"],
    queryFn: () => minhasTarefas(),
    staleTime: OPERACIONAL,
  });

  const afazer = (tarefas.data ?? []).filter((t) => t.situacao === "a_fazer").length;

  return (
    <div className="space-y-4">
      <h1 className="font-display text-2xl font-semibold">
        {eu.isLoading ? "Carregando…" : `Olá, ${eu.data?.nome ?? ""}`}
      </h1>

      <section className="rounded-2xl border border-border bg-card p-5">
        <p className="text-sm text-muted-foreground">Seu saldo</p>
        <p className="font-display text-4xl font-semibold tabular-nums">
          {eu.isLoading ? "—" : (eu.data?.saldo ?? 0).toLocaleString("pt-BR")}
          <span className="ml-2 text-base font-normal text-muted-foreground">pontos</span>
        </p>
        <Link to="/eu/extrato" className="mt-3 inline-block text-sm text-primary">
          Ver extrato
        </Link>
      </section>

      <div className="grid grid-cols-2 gap-3">
        <Link to="/eu/tarefas" className="rounded-2xl border border-border bg-card p-4">
          <p className="font-display text-3xl font-semibold tabular-nums">{tarefas.isLoading ? "—" : afazer}</p>
          <p className="text-sm text-muted-foreground">{afazer === 1 ? "tarefa para hoje" : "tarefas para hoje"}</p>
        </Link>
        <div className="rounded-2xl border border-border bg-card p-4">
          <p className="font-display text-3xl font-semibold tabular-nums">
            {eu.isLoading ? "—" : eu.data?.nota === null || eu.data?.nota === undefined ? "—" : eu.data.nota}
          </p>
          <p className="text-sm text-muted-foreground">sua nota do mês</p>
        </div>
      </div>

      {eu.data?.feedbackpendente ? (
        <p className="rounded-2xl border border-border bg-muted/40 p-4 text-sm">
          Você tem um feedback de ontem para responder. Ele entra na próxima etapa do aplicativo.
        </p>
      ) : null}

      {eu.data?.comunicados ? (
        <p className="rounded-2xl border border-border bg-muted/40 p-4 text-sm">
          {eu.data.comunicados === 1 ? "Há 1 comunicado novo" : `Há ${eu.data.comunicados} comunicados novos`} da
          gestão.
        </p>
      ) : null}

      <p className="pt-2 text-center text-xs text-muted-foreground">
        Para PEGAR uma tarefa, use o tablet da loja.
      </p>
    </div>
  );
}
