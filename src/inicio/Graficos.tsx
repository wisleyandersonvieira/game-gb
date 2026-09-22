// Gráficos da tela Início. As cores vêm do tema (CSS), então funcionam no
// claro e no escuro sem mudar nada aqui.
import {
  Bar, BarChart, CartesianGrid, Cell, ComposedChart, Legend, Line, ResponsiveContainer, Tooltip, XAxis, YAxis,
} from "recharts";
import type { ReactNode } from "react";
import { diaMes, reais, reaisCurto, type PainelInicio } from "./tipos";

const COR = {
  primario: "var(--color-primary)",
  sucesso: "var(--color-sucesso)",
  pendente: "var(--color-accent)",
  erro: "var(--color-destructive)",
  grade: "var(--color-border)",
  texto: "var(--color-muted-foreground)",
};

const eixo = { fontSize: 11, fill: COR.texto };
const dica = {
  contentStyle: {
    background: "var(--color-card)",
    border: "1px solid var(--color-border)",
    borderRadius: 8,
    color: "var(--color-foreground)",
    fontSize: 12,
  },
  labelStyle: { color: "var(--color-foreground)", fontWeight: 600 },
  cursor: { fill: "var(--color-muted)", opacity: 0.6 },
};
const legenda = { wrapperStyle: { fontSize: 12, color: COR.texto } };

export function CaixaGrafico({ titulo, descricao, children }: { titulo: string; descricao?: string; children: ReactNode }) {
  return (
    <section className="min-w-0 rounded-xl border border-border bg-card p-4 shadow-sm">
      <h2 className="text-sm font-semibold">{titulo}</h2>
      {descricao && <p className="text-xs text-muted-foreground">{descricao}</p>}
      <div className="mt-3 h-56 sm:h-64">{children}</div>
    </section>
  );
}

export function GraficoVendas({ dados, hoje }: { dados: PainelInicio["vendas"]; hoje: string }) {
  const linhas = dados.map((d) => ({
    dia: Number(d.dia.slice(8, 10)),
    vendido: d.dia <= hoje ? d.vendido : null,
    meta: d.meta && d.meta > 0 ? d.meta : null,
    bateu: d.vendido != null && d.meta != null && d.meta > 0 && d.vendido >= d.meta,
  }));
  return (
    <ResponsiveContainer width="100%" height="100%">
      <ComposedChart data={linhas} margin={{ top: 4, right: 4, left: -8, bottom: 0 }}>
        <CartesianGrid stroke={COR.grade} vertical={false} />
        <XAxis dataKey="dia" tick={eixo} tickLine={false} axisLine={false} interval="preserveStartEnd" minTickGap={8} />
        <YAxis tick={eixo} tickLine={false} axisLine={false} width={56} tickFormatter={(v: number) => reaisCurto(v)} />
        <Tooltip
          {...dica}
          labelFormatter={(d) => `Dia ${d}`}
          formatter={(v, nome) => [v == null ? "—" : reais(Number(v)), nome === "vendido" ? "Vendido" : "Meta"]}
        />
        <Legend {...legenda} formatter={(v) => (v === "vendido" ? "Vendido" : "Meta do dia")} />
        <Bar dataKey="vendido" fill={COR.primario} radius={[3, 3, 0, 0]} maxBarSize={18}>
          {linhas.map((l) => (
            <Cell key={l.dia} fill={l.bateu ? COR.sucesso : COR.primario} />
          ))}
        </Bar>
        <Line dataKey="meta" stroke={COR.pendente} strokeWidth={2} strokeDasharray="5 4" dot={false} connectNulls />
      </ComposedChart>
    </ResponsiveContainer>
  );
}

export function GraficoPontos({ dados }: { dados: PainelInicio["pontos"] }) {
  const linhas = dados.map((d) => ({ ...d, rotulo: diaMes(d.semana) }));
  return (
    <ResponsiveContainer width="100%" height="100%">
      <BarChart data={linhas} margin={{ top: 4, right: 4, left: -16, bottom: 0 }}>
        <CartesianGrid stroke={COR.grade} vertical={false} />
        <XAxis dataKey="rotulo" tick={eixo} tickLine={false} axisLine={false} />
        <YAxis tick={eixo} tickLine={false} axisLine={false} width={48} allowDecimals={false} />
        <Tooltip {...dica} labelFormatter={(r) => `Semana de ${r}`} formatter={(v, nome) => [`${v} pontos`, nome === "entraram" ? "Entraram" : "Saíram"]} />
        <Legend {...legenda} formatter={(v) => (v === "entraram" ? "Entraram" : "Saíram (resgates)")} />
        <Bar dataKey="entraram" fill={COR.sucesso} radius={[3, 3, 0, 0]} maxBarSize={22} />
        <Bar dataKey="sairam" fill={COR.erro} radius={[3, 3, 0, 0]} maxBarSize={22} />
      </BarChart>
    </ResponsiveContainer>
  );
}

export function GraficoEntregas({ dados }: { dados: PainelInicio["entregas"] }) {
  const linhas = dados.map((d) => ({ ...d, rotulo: diaMes(d.semana) }));
  return (
    <ResponsiveContainer width="100%" height="100%">
      <BarChart data={linhas} margin={{ top: 4, right: 4, left: -16, bottom: 0 }}>
        <CartesianGrid stroke={COR.grade} vertical={false} />
        <XAxis dataKey="rotulo" tick={eixo} tickLine={false} axisLine={false} />
        <YAxis tick={eixo} tickLine={false} axisLine={false} width={48} allowDecimals={false} />
        <Tooltip {...dica} labelFormatter={(r) => `Semana de ${r}`} formatter={(v, nome) => [v, nome === "aprovadas" ? "Aprovadas" : "Recusadas"]} />
        <Legend {...legenda} formatter={(v) => (v === "aprovadas" ? "Aprovadas" : "Recusadas")} />
        <Bar dataKey="aprovadas" fill={COR.sucesso} radius={[3, 3, 0, 0]} maxBarSize={28} />
        <Bar dataKey="recusadas" fill={COR.erro} radius={[3, 3, 0, 0]} maxBarSize={28} />
      </BarChart>
    </ResponsiveContainer>
  );
}
