// Extrato de pontos do colaborador.
//
// Só PONTOS. Nada de "≈ R$" aqui nem em nenhuma outra tela dela (decisão do
// Wisley, 26/09/2026): o valor em reais aparece uma única vez, na hora de
// abater na comanda.
import { createFileRoute } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { useState } from "react";
import { meuExtrato } from "@/servidor/colaborador";
import { DINHEIRO } from "@/ui/prazos";
import { diaNoFuso, primeiroDoMes, useHojeDaConta } from "@/ui/hoje";

export const Route = createFileRoute("/eu/extrato")({ component: Extrato });

/** "26/09", no fuso da conta (a mesma régua com que o banco filtra o período). */
function dia(iso: string, fuso: string | undefined) {
  const [, mes, dd] = diaNoFuso(iso, fuso || "America/Sao_Paulo").split("-");
  return `${dd}/${mes}`;
}

function Extrato() {
  // O período padrão (do dia 1 até hoje) parte do dia de hoje DA CONTA, dito
  // pelo servidor. Antes era o relógio do celular, em UTC: depois das 21h o
  // extrato já achava que era amanhã.
  const conta = useHojeDaConta();
  const [escolhidoDe, setDe] = useState<string | null>(null);
  const [escolhidoAte, setAte] = useState<string | null>(null);
  const hoje = conta.data?.hoje;
  const de = escolhidoDe ?? (hoje ? primeiroDoMes(hoje) : "");
  const ate = escolhidoAte ?? hoje ?? "";

  const extrato = useQuery({
    queryKey: ["eu-extrato", de, ate],
    queryFn: () => meuExtrato({ data: { de, ate } }),
    enabled: !!de && !!ate,
    ...DINHEIRO,
  });

  const linhas = extrato.data?.linhas ?? [];

  return (
    <div className="space-y-4">
      <h1 className="font-display text-2xl font-semibold">Extrato</h1>

      <section className="rounded-2xl border border-border bg-card p-5">
        <p className="text-sm text-muted-foreground">Saldo atual</p>
        <p className="font-display text-4xl font-semibold tabular-nums">
          {extrato.isLoading ? "—" : (extrato.data?.saldo ?? 0).toLocaleString("pt-BR")}
          <span className="ml-2 text-base font-normal text-muted-foreground">pontos</span>
        </p>
      </section>

      <div className="flex items-end gap-2">
        <label className="flex-1">
          <span className="text-xs text-muted-foreground">De</span>
          <input
            type="date"
            value={de}
            max={ate}
            onChange={(e) => setDe(e.target.value)}
            className="mt-1 w-full rounded-xl border border-border bg-background p-2.5 text-sm"
          />
        </label>
        <label className="flex-1">
          <span className="text-xs text-muted-foreground">Até</span>
          <input
            type="date"
            value={ate}
            min={de}
            onChange={(e) => setAte(e.target.value)}
            className="mt-1 w-full rounded-xl border border-border bg-background p-2.5 text-sm"
          />
        </label>
      </div>

      {extrato.isLoading ? (
        <p className="text-sm text-muted-foreground">Carregando…</p>
      ) : linhas.length === 0 ? (
        <p className="rounded-2xl border border-border bg-card p-5 text-sm text-muted-foreground">
          Nenhum movimento neste período.
        </p>
      ) : (
        <ul className="divide-y divide-border rounded-2xl border border-border bg-card">
          {linhas.map((l, i) => (
            <li key={i} className="flex items-start justify-between gap-3 p-4">
              <div className="min-w-0">
                <p className="truncate text-sm">{l.descricao}</p>
                <p className="text-xs text-muted-foreground">{dia(l.quando, conta.data?.fuso)}</p>
              </div>
              <span
                className={`shrink-0 tabular-nums text-sm font-medium ${
                  l.pontos < 0 ? "text-destructive" : "text-emerald-600 dark:text-emerald-400"
                }`}
              >
                {l.pontos > 0 ? "+" : ""}
                {l.pontos.toLocaleString("pt-BR")}
              </span>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
