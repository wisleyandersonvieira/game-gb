import { createFileRoute } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Nav } from "@/components/Nav";

export const Route = createFileRoute("/_authenticated/extrato")({
  component: Extrato,
});

const campo =
  "rounded-lg border border-border bg-background px-3 py-2 text-sm placeholder:text-muted-foreground";

const reais = (v: number) =>
  new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(v);

const hoje = () => new Intl.DateTimeFormat("en-CA", { timeZone: "America/Sao_Paulo" }).format(new Date());

const ROTULO_TIPO: Record<string, string> = {
  aprovacao: "Tarefa",
  estorno_entrega: "Estorno",
  bonus: "Bônus",
  estorno_bonus: "Estorno de bônus",
  resgate: "Resgate",
  cancelamento_resgate: "Cancelamento",
  estorno_resgate: "Estorno de resgate",
  ajuste_abertura: "Ajuste",
};

type Movimento = {
  data: string;
  tipo: string;
  descricao: string;
  loja: string | null;
  pontos: number;
  saldoapos: number;
};

type DadosExtrato = {
  nome: string;
  saldoatual: number;
  saldoinicial: number;
  saldofinal: number;
  confere: boolean;
  taxa: number | null;
  movimentos: Movimento[];
};

function Extrato() {
  const [funcionarioid, setFuncionarioid] = useState<number | "">("");
  const [de, setDe] = useState(`${hoje().slice(0, 7)}-01`);
  const [ate, setAte] = useState(hoje());

  const pessoas = useQuery({
    queryKey: ["pessoas-extrato"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("funcionarios")
        .select("funcionarioid, nomecompleto, ativo")
        .order("nomecompleto");
      if (error) throw error;
      return data ?? [];
    },
  });

  const extrato = useQuery({
    queryKey: ["extrato", funcionarioid, de, ate],
    enabled: funcionarioid !== "" && de !== "" && ate !== "",
    queryFn: async () => {
      const { data, error } = await supabase.rpc("extrato_pontos", {
        p_funcionarioid: Number(funcionarioid),
        p_de: de,
        p_ate: ate,
      });
      if (error) throw error;
      return data as unknown as DadosExtrato;
    },
  });

  const x = extrato.data;
  const emReais = (pontos: number) => (x?.taxa ? ` (${reais(pontos * x.taxa)})` : "");

  return (
    <main className="mx-auto min-h-screen max-w-5xl space-y-6 p-6">
      <Nav />
      <h1 className="text-3xl font-bold">Extrato de pontos</h1>

      <div className="flex flex-wrap items-center gap-3 rounded-xl border border-border bg-card p-4">
        <select
          value={funcionarioid}
          onChange={(e) => setFuncionarioid(e.target.value === "" ? "" : Number(e.target.value))}
          className={campo}
        >
          <option value="">Escolha a pessoa...</option>
          {(pessoas.data ?? []).map((p) => (
            <option key={p.funcionarioid} value={p.funcionarioid}>
              {p.nomecompleto}
              {p.ativo ? "" : " (inativo)"}
            </option>
          ))}
        </select>
        <label className="flex items-center gap-2 text-sm text-muted-foreground">
          De
          <input type="date" value={de} onChange={(e) => setDe(e.target.value)} className={campo} />
        </label>
        <label className="flex items-center gap-2 text-sm text-muted-foreground">
          até
          <input type="date" value={ate} onChange={(e) => setAte(e.target.value)} className={campo} />
        </label>
      </div>

      {extrato.isLoading && funcionarioid !== "" && <p className="text-muted-foreground">Carregando...</p>}
      {extrato.isError && <p className="text-sm text-destructive">{(extrato.error as Error).message}</p>}

      {x && (
        <>
          <div className="grid gap-3 sm:grid-cols-3">
            <Resumo titulo="Saldo no início do período" pontos={x.saldoinicial} emReais={emReais(x.saldoinicial)} />
            <Resumo titulo="Saldo no fim do período" pontos={x.saldofinal} emReais={emReais(x.saldofinal)} />
            <Resumo titulo="Saldo atual" pontos={x.saldoatual} emReais={emReais(x.saldoatual)} destaque />
          </div>

          <p className={`text-xs ${x.confere ? "text-muted-foreground" : "text-destructive"}`}>
            {x.confere
              ? "✓ O saldo atual bate com a soma de todos os movimentos."
              : "⚠ O saldo atual NÃO bate com a soma dos movimentos. Avise o suporte."}
            {x.taxa ? ` Valores em R$ pela taxa atual: 1 ponto = ${reais(x.taxa)}.` : ""}
          </p>

          <div className="overflow-x-auto rounded-xl border border-border">
            <table className="w-full text-sm">
              <thead className="bg-card text-left text-muted-foreground">
                <tr>
                  <th className="px-3 py-2 font-medium">Data</th>
                  <th className="px-3 py-2 font-medium">Movimento</th>
                  <th className="px-3 py-2 font-medium">Loja</th>
                  <th className="px-3 py-2 text-right font-medium">Pontos</th>
                  <th className="px-3 py-2 text-right font-medium">Saldo após</th>
                </tr>
              </thead>
              <tbody>
                {x.movimentos.map((m, i) => (
                  <tr key={i} className="border-t border-border">
                    <td className="whitespace-nowrap px-3 py-2 text-muted-foreground">
                      {new Date(m.data).toLocaleString("pt-BR", {
                        timeZone: "America/Sao_Paulo",
                        day: "2-digit",
                        month: "2-digit",
                        year: "numeric",
                        hour: "2-digit",
                        minute: "2-digit",
                      })}
                    </td>
                    <td className="px-3 py-2">
                      <span className="mr-2 text-xs text-muted-foreground">{ROTULO_TIPO[m.tipo] ?? m.tipo}</span>
                      {m.descricao}
                    </td>
                    <td className="px-3 py-2 text-muted-foreground">{m.loja ?? "—"}</td>
                    <td className={`px-3 py-2 text-right font-semibold ${m.pontos > 0 ? "text-primary" : "text-destructive"}`}>
                      {m.pontos > 0 ? `+${m.pontos}` : m.pontos}
                    </td>
                    <td className={`px-3 py-2 text-right ${m.saldoapos < 0 ? "text-destructive" : ""}`}>{m.saldoapos}</td>
                  </tr>
                ))}
                {x.movimentos.length === 0 && (
                  <tr>
                    <td colSpan={5} className="px-3 py-6 text-center text-muted-foreground">
                      Nenhum movimento neste período.
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        </>
      )}
    </main>
  );
}

function Resumo({
  titulo,
  pontos,
  emReais,
  destaque = false,
}: {
  titulo: string;
  pontos: number;
  emReais: string;
  destaque?: boolean;
}) {
  return (
    <div className={`rounded-xl border bg-card p-4 ${destaque ? "border-primary" : "border-border"}`}>
      <p className="text-xs text-muted-foreground">{titulo}</p>
      <p className={`text-2xl font-bold ${pontos < 0 ? "text-destructive" : ""}`}>{pontos} pontos</p>
      <p className="text-sm text-muted-foreground">{emReais.replace(/[()]/g, "").trim() || "—"}</p>
    </div>
  );
}
