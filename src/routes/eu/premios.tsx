// Solicitar resgate, pelo celular do colaborador.
//
// O pedido nasce PENDENTE e cai na tela do gestor, idêntico ao que o
// "Entregar depois" dele já cria: pontos e estoque ficam reservados na hora.
//
// O saldo e o estoque são conferidos no SERVIDOR, no momento do pedido. O que
// esta tela mostra é só para a pessoa se orientar.
import { createFileRoute } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import {
  desistirDoResgate,
  meusPremios,
  meusResgates,
  pedirResgate,
  type PremioParaMim,
} from "@/servidor/colaborador";
import { DINHEIRO } from "@/ui/prazos";

export const Route = createFileRoute("/eu/premios")({ component: Premios });

const COR: Record<string, string> = {
  Pendente: "bg-amber-500/15 text-amber-600 dark:text-amber-400",
  Entregue: "bg-emerald-500/15 text-emerald-600 dark:text-emerald-400",
  Cancelado: "bg-muted text-muted-foreground",
  Estornado: "bg-destructive/15 text-destructive",
};

function dia(iso: string) {
  return new Date(iso).toLocaleDateString("pt-BR", { day: "2-digit", month: "2-digit" });
}

function Premios() {
  const qc = useQueryClient();
  const [aba, setAba] = useState<"catalogo" | "abate">("catalogo");
  const [valor, setValor] = useState("");

  // Pontos nunca são reaproveitados: melhor esperar do que mostrar valor velho.
  const catalogo = useQuery({ queryKey: ["eu-premios"], queryFn: () => meusPremios(), ...DINHEIRO });
  const pedidos = useQuery({ queryKey: ["eu-resgates"], queryFn: () => meusResgates(), ...DINHEIRO });

  function atualizar() {
    qc.invalidateQueries({ queryKey: ["eu-premios"] });
    qc.invalidateQueries({ queryKey: ["eu-resgates"] });
    qc.invalidateQueries({ queryKey: ["eu-inicio"] });
  }

  const pedir = useMutation({
    mutationFn: (d: { produtoid?: number; valorreais?: number }) => pedirResgate({ data: d }),
    onSuccess: () => {
      setValor("");
      atualizar();
    },
  });

  const desistir = useMutation({
    mutationFn: (resgateid: number) => desistirDoResgate({ data: { resgateid } }),
    onSuccess: atualizar,
  });

  const saldo = catalogo.data?.saldo ?? 0;
  const lista = catalogo.data?.premios ?? [];

  return (
    <div className="space-y-4">
      <h1 className="font-display text-2xl font-semibold">Solicitar resgate</h1>

      <section className="rounded-2xl border border-border bg-card p-4">
        <p className="text-sm text-muted-foreground">Seu saldo</p>
        <p className="font-display text-3xl font-semibold tabular-nums">
          {catalogo.isLoading ? "—" : saldo.toLocaleString("pt-BR")}
          <span className="ml-2 text-base font-normal text-muted-foreground">pontos</span>
        </p>
      </section>

      <div className="flex gap-2">
        {(["catalogo", "abate"] as const).map((v) => (
          <button
            key={v}
            onClick={() => setAba(v)}
            className={`flex-1 rounded-xl px-3 py-2.5 text-sm font-medium ${
              aba === v ? "bg-primary text-primary-foreground" : "border border-border"
            }`}
          >
            {v === "catalogo" ? "Prêmio do catálogo" : "Abater na comanda"}
          </button>
        ))}
      </div>

      {pedir.isError && (
        <p className="rounded-xl bg-destructive/10 p-3 text-sm text-destructive">
          {(pedir.error as Error).message}
        </p>
      )}

      {aba === "catalogo" ? (
        <ul className="space-y-2">
          {lista.map((p: PremioParaMim) => (
            <li
              key={p.produtoid}
              className="flex items-center justify-between gap-3 rounded-2xl border border-border bg-card p-4"
            >
              <div className="min-w-0">
                <p className="truncate font-medium">{p.nome}</p>
                <p className="text-xs text-muted-foreground">
                  {p.custo} pontos
                  {p.estoque !== null && ` · ${p.estoque} disponíveis`}
                </p>
              </div>
              <button
                onClick={() => pedir.mutate({ produtoid: p.produtoid })}
                disabled={!p.cabe || pedir.isPending}
                className="shrink-0 rounded-xl bg-primary px-4 py-2.5 text-sm font-medium text-primary-foreground disabled:opacity-40"
              >
                {p.cabe ? "Pedir" : "Falta saldo"}
              </button>
            </li>
          ))}
          {lista.length === 0 && !catalogo.isLoading && (
            <li className="rounded-2xl border border-border bg-card p-5 text-sm text-muted-foreground">
              Nenhum prêmio disponível agora.
            </li>
          )}
        </ul>
      ) : (
        <div className="space-y-3 rounded-2xl border border-border bg-card p-4">
          <label className="block">
            <span className="text-sm text-muted-foreground">Quanto abater na comanda</span>
            <input
              inputMode="decimal"
              value={valor}
              onChange={(e) => setValor(e.target.value)}
              placeholder="10,00"
              className="mt-1.5 w-full rounded-xl border border-border bg-background p-3 text-lg"
            />
          </label>
          <button
            onClick={() => pedir.mutate({ valorreais: Number(valor.replace(",", ".")) })}
            disabled={pedir.isPending || valor.trim() === ""}
            className="w-full rounded-xl bg-primary px-4 py-3 text-sm font-medium text-primary-foreground disabled:opacity-60"
          >
            {pedir.isPending ? "Pedindo..." : "Pedir abate"}
          </button>
          <p className="text-xs text-muted-foreground">
            O sistema converte em pontos pela taxa da sua empresa e confere o seu saldo.
          </p>
        </div>
      )}

      <section className="space-y-2">
        <h2 className="text-sm font-semibold">Meus pedidos</h2>
        {(pedidos.data ?? []).map((r) => (
          <div
            key={r.resgateid}
            className="flex items-center justify-between gap-3 rounded-2xl border border-border bg-card p-4"
          >
            <div className="min-w-0">
              <p className="truncate text-sm font-medium">{r.nome}</p>
              <p className="text-xs text-muted-foreground">
                {r.pontos} pontos · {dia(r.quando)}
              </p>
            </div>
            <div className="flex shrink-0 items-center gap-2">
              <span className={`rounded-full px-2.5 py-1 text-xs font-medium ${COR[r.status] ?? ""}`}>
                {r.status}
              </span>
              {r.status === "Pendente" && (
                <button
                  onClick={() => desistir.mutate(r.resgateid)}
                  disabled={desistir.isPending}
                  className="rounded-xl border border-border px-3 py-2 text-xs"
                >
                  Desistir
                </button>
              )}
            </div>
          </div>
        ))}
        {(pedidos.data ?? []).length === 0 && !pedidos.isLoading && (
          <p className="text-sm text-muted-foreground">Você ainda não pediu nenhum resgate.</p>
        )}
        {desistir.isError && (
          <p className="text-sm text-destructive">{(desistir.error as Error).message}</p>
        )}
      </section>
    </div>
  );
}
