// Meta de faturamento no painel da loja e na TV.
// Os dados vêm do banco (meta_para_painel). Na TV, sem a opção da loja
// "mostrar valores", o banco nem envia os valores em R$: só porcentagens.
import { useState } from "react";

export type MetaPainel = {
  dia: {
    percentual: number;
    bateu: boolean;
    lancado: boolean;
    especial: string | null;
    vendido?: number;
    meta?: number;
  } | null;
  mes: {
    nome: string;
    percentual: number;
    bateu: boolean;
    vendido?: number;
    meta?: number;
    projecao?: number | null;
  } | null;
  valores: boolean;
} | null;

const reais = (v: number) =>
  new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(v);

const pct = (v: number) => `${Number(v).toLocaleString("pt-BR", { maximumFractionDigits: 1 })}%`;

const CHAVE_OCULTAR = "gamegb.meta.ocultarvalores";

function lerOcultar() {
  try {
    return localStorage.getItem(CHAVE_OCULTAR) === "1";
  } catch {
    return false;
  }
}

function Barra({ percentual, bateu, alta }: { percentual: number; bateu: boolean; alta: string }) {
  return (
    <div className={`overflow-hidden rounded-full bg-muted ${alta}`}>
      <div
        className={`h-full transition-all duration-700 ${bateu ? "bg-sucesso" : "bg-accent"}`}
        style={{ width: `${Math.min(100, Math.max(0, percentual))}%` }}
      />
    </div>
  );
}

/** Cartão da meta dentro do painel (logado e TV). */
export function MetaCartao({ meta, tv = false }: { meta: MetaPainel; tv?: boolean }) {
  const [ocultar, setOcultar] = useState(lerOcultar);
  const mostrar = !!meta?.valores && !(ocultar && !tv);

  function alternar() {
    const novo = !ocultar;
    setOcultar(novo);
    try {
      localStorage.setItem(CHAVE_OCULTAR, novo ? "1" : "0");
    } catch {
      /* sem memória: vale só nesta tela */
    }
  }

  const tam = { titulo: tv ? "text-xl" : "text-sm", grande: tv ? "text-4xl" : "text-2xl", sub: tv ? "text-base" : "text-xs" };

  if (!meta) {
    return (
      <div className={`rounded-xl border border-dashed border-border ${tv ? "p-5" : "p-3"} text-center`}>
        <p className={`${tam.titulo} font-medium text-muted-foreground`}>Meta do dia</p>
        <p className={`${tam.sub} text-muted-foreground`}>Nenhuma meta cadastrada para esta loja.</p>
      </div>
    );
  }

  return (
    <section className={`space-y-3 rounded-xl border border-border bg-card ${tv ? "p-5" : "p-3"}`}>
      <div className="flex items-center justify-between gap-2">
        <h2 className={`${tam.titulo} font-semibold`}>
          Meta do dia{meta.dia?.especial ? ` · ${meta.dia.especial}` : ""}
        </h2>
        {!tv && meta.valores && (
          <button
            onClick={alternar}
            title={ocultar ? "Mostrar valores" : "Ocultar valores"}
            aria-label={ocultar ? "Mostrar valores" : "Ocultar valores"}
            className="rounded-md px-2 text-lg"
          >
            {ocultar ? "🙈" : "👁️"}
          </button>
        )}
      </div>

      {meta.dia ? (
        <div className="space-y-1">
          <div className="flex items-baseline justify-between">
            <strong className={`${tam.grande} ${meta.dia.bateu ? "text-sucesso" : ""}`}>
              {meta.dia.bateu ? "🎉 " : ""}
              {pct(meta.dia.percentual)}
            </strong>
            {mostrar && meta.dia.vendido !== undefined && meta.dia.meta !== undefined && (
              <span className={`${tam.sub} text-muted-foreground`}>
                {reais(meta.dia.vendido)} de {reais(meta.dia.meta)}
              </span>
            )}
          </div>
          <Barra percentual={meta.dia.percentual} bateu={meta.dia.bateu} alta={tv ? "h-6" : "h-3"} />
          {!meta.dia.lancado && <p className={`${tam.sub} text-muted-foreground`}>Venda de hoje ainda não lançada.</p>}
        </div>
      ) : (
        <p className={`${tam.sub} text-muted-foreground`}>Sem meta para hoje.</p>
      )}

      {meta.mes && (
        <div className="space-y-1 border-t border-border pt-2">
          <div className="flex items-baseline justify-between">
            <span className={`${tam.sub} text-muted-foreground`}>{meta.mes.nome}</span>
            <strong className={tv ? "text-2xl" : "text-sm"}>{pct(meta.mes.percentual)}</strong>
          </div>
          <Barra percentual={meta.mes.percentual} bateu={meta.mes.bateu} alta={tv ? "h-4" : "h-2"} />
          {mostrar && meta.mes.vendido !== undefined && meta.mes.meta !== undefined && (
            <p className={`${tam.sub} text-muted-foreground`}>
              {reais(meta.mes.vendido)} de {reais(meta.mes.meta)}
              {meta.mes.projecao ? ` · projeção ${reais(meta.mes.projecao)}` : ""}
            </p>
          )}
        </div>
      )}
    </section>
  );
}

/** Tela cheia da meta, usada no rodízio da TV. */
export function TelaDaMeta({ meta }: { meta: NonNullable<MetaPainel> }) {
  return (
    <div className="space-y-12 py-6">
      {meta.dia && (
        <section className="space-y-4 text-center">
          <p className="text-2xl font-semibold text-muted-foreground sm:text-4xl">
            Meta do dia{meta.dia.especial ? ` · ${meta.dia.especial}` : ""}
          </p>
          <p className={`text-6xl font-bold sm:text-9xl ${meta.dia.bateu ? "text-sucesso" : ""}`}>
            {meta.dia.bateu ? "🎉 " : ""}
            {pct(meta.dia.percentual)}
          </p>
          <Barra percentual={meta.dia.percentual} bateu={meta.dia.bateu} alta="h-8 sm:h-12" />
          {meta.valores && meta.dia.vendido !== undefined && meta.dia.meta !== undefined && (
            <p className="text-xl text-muted-foreground sm:text-3xl">
              {reais(meta.dia.vendido)} de {reais(meta.dia.meta)}
            </p>
          )}
          {meta.dia.bateu && <p className="text-2xl font-bold text-sucesso sm:text-4xl">Meta do dia batida! Parabéns, equipe!</p>}
        </section>
      )}
      {meta.mes && (
        <section className="space-y-3 text-center">
          <p className="text-xl text-muted-foreground sm:text-3xl">{meta.mes.nome}</p>
          <p className="text-5xl font-bold sm:text-7xl">{pct(meta.mes.percentual)}</p>
          <Barra percentual={meta.mes.percentual} bateu={meta.mes.bateu} alta="h-6 sm:h-8" />
          {meta.valores && meta.mes.vendido !== undefined && meta.mes.meta !== undefined && (
            <p className="text-lg text-muted-foreground sm:text-2xl">
              {reais(meta.mes.vendido)} de {reais(meta.mes.meta)}
            </p>
          )}
        </section>
      )}
    </div>
  );
}
