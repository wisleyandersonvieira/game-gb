import { createFileRoute, Link } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useLojaAtiva } from "@/lojas/loja-ativa";
import { CartaoNumero } from "@/ui/CartaoNumero";
import { Carregando, ErroTela } from "@/ui/Estados";
import { CaixaGrafico, GraficoEntregas, GraficoPontos, GraficoVendas } from "@/inicio/Graficos";
import { Guia, guiaCompleto } from "@/inicio/Guia";
import { Avisos, SituacaoRotina } from "@/inicio/Avisos";
import { pct, quando, reais, type PainelInicio } from "@/inicio/tipos";
import { Pontos } from "@/ui/Pontos";
import { AvisosDoSistema } from "@/telegram/Telegram";
import { Pagina } from "@/ui/Pagina";

export const Route = createFileRoute("/_authenticated/inicio")({
  component: Inicio,
});

const CHAVE_ALCANCE = "gamegb.inicioAlcance";
const CHAVE_GUIA = "gamegb.guiaFechado";

function ler(chave: string) {
  try {
    return localStorage.getItem(chave);
  } catch {
    return null;
  }
}
function gravar(chave: string, valor: string) {
  try {
    localStorage.setItem(chave, valor);
  } catch {
    /* sem memória no navegador */
  }
}

function Inicio() {
  const { lojas, lojaAtiva, loja } = useLojaAtiva();
  const [alcance, setAlcance] = useState<"todas" | "loja">("todas");
  const [guiaFechado, setGuiaFechado] = useState(false);

  useEffect(() => {
    setAlcance(ler(CHAVE_ALCANCE) === "loja" ? "loja" : "todas");
    setGuiaFechado(ler(CHAVE_GUIA) === "1");
  }, []);

  // Uma loja só: "todas" e "a loja" dão no mesmo.
  const lojaid = alcance === "loja" && lojas.length > 1 ? lojaAtiva : null;

  const painel = useQuery({
    queryKey: ["painel-inicio", lojaid],
    refetchInterval: 60_000,
    refetchOnWindowFocus: true,
    queryFn: async () => {
      const { data, error } = await supabase.rpc("painel_inicio", lojaid === null ? {} : { p_lojaid: lojaid });
      if (error) throw error;
      return data as unknown as PainelInicio;
    },
  });

  function escolher(a: "todas" | "loja") {
    setAlcance(a);
    gravar(CHAVE_ALCANCE, a);
  }

  const p = painel.data;
  const temDados =
    !!p &&
    (p.vendas.some((v) => (v.vendido ?? 0) > 0) ||
      p.pontos.some((s) => s.entraram !== 0 || s.sairam !== 0) ||
      p.entregas.some((s) => s.aprovadas + s.recusadas > 0));
  const podeFecharGuia = !!p && p.guia.loja && p.guia.equipe && temDados;
  const mostrarGuia = !!p && !guiaCompleto(p.guia) && !(guiaFechado && podeFecharGuia);

  return (
    <Pagina
      titulo="Início"
      descricao={
        p
          ? `Resumo de hoje, ${new Date(`${p.hoje}T12:00:00Z`).toLocaleDateString("pt-BR", { timeZone: "UTC", weekday: "long", day: "2-digit", month: "long" })}. Atualiza sozinho a cada minuto.`
          : "Resumo de hoje."
      }
      acoes={
        lojas.length > 1 && (
          <div className="flex w-fit gap-1 rounded-lg border border-border bg-card p-1" role="group" aria-label="Quais lojas">
            {(
              [
                ["todas", "Todas as lojas"],
                ["loja", loja?.nome ?? "Loja ativa"],
              ] as const
            ).map(([id, rotulo]) => (
              <button
                key={id}
                onClick={() => escolher(id)}
                aria-pressed={alcance === id}
                className={`rounded-md px-3 py-1.5 text-sm ${
                  alcance === id ? "bg-azul-soft font-semibold text-azul" : "text-muted-foreground hover:bg-muted"
                }`}
              >
                {rotulo}
              </button>
            ))}
          </div>
        )
      }
    >

      <AvisosDoSistema />
      {painel.isLoading && <Carregando />}
      {painel.isError && <ErroTela erro={painel.error} />}

      {p && (
        <>
          <div className="-mt-3">
            <SituacaoRotina rotina={p.rotina ?? null} />
          </div>
          <Avisos avisos={p.avisos} />
          {mostrarGuia && (
            <Guia
              guia={p.guia}
              aoFechar={
                podeFecharGuia
                  ? () => {
                      setGuiaFechado(true);
                      gravar(CHAVE_GUIA, "1");
                    }
                  : undefined
              }
            />
          )}
          <Cartoes p={p} />
          {temDados ? (
            <Graficos p={p} />
          ) : (
            !mostrarGuia && (
              <p className="rounded-xl border border-dashed border-border px-4 py-6 text-center text-sm text-muted-foreground">
                Os gráficos aparecem quando houver vendas lançadas, entregas ou pontos neste mês.
              </p>
            )
          )}
          <Listas p={p} />
        </>
      )}
    </Pagina>
  );
}

function CartaoMeta({ titulo, meta }: { titulo: string; meta: PainelInicio["cartoes"]["metadia"] }) {
  if (!meta) {
    return <CartaoNumero titulo={titulo} valor="—" detalhe="Definir meta" tom="primario" para="/metas" />;
  }
  const bateu = meta.percentual >= 100;
  return (
    <CartaoNumero
      titulo={titulo}
      valor={pct(meta.percentual)}
      detalhe={`${reais(meta.vendido)} de ${reais(meta.meta)}`}
      tom={bateu ? "sucesso" : "primario"}
      progresso={meta.percentual}
      etiqueta={bateu ? "batida" : undefined}
      para="/metas"
    />
  );
}

function Cartoes({ p }: { p: PainelInicio }) {
  const c = p.cartoes;
  const t = c.tarefas;
  return (
    <div className="grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-5">
      <CartaoMeta titulo="Meta do dia" meta={c.metadia} />
      <CartaoMeta titulo="Meta do mês" meta={c.metames} />
      <CartaoNumero
        titulo="Tarefas de hoje"
        valor={`${t.feitas}/${t.total}`}
        detalhe={t.total === 0 ? "Nenhuma tarefa hoje" : `${t.aprovadas} aprovadas · ${t.emvalidacao} em validação`}
        tom={t.total > 0 && t.feitas === t.total ? "sucesso" : "neutro"}
        progresso={t.total > 0 ? (t.feitas * 100) / t.total : undefined}
        para="/operacional"
      />
      <CartaoNumero
        titulo="Aguardando validação"
        valor={c.validar}
        detalhe={c.validar === 0 ? "Tudo validado" : "Entregas para aprovar ou recusar"}
        tom={c.validar > 0 ? "pendente" : "sucesso"}
        para="/painel"
      />
      <CartaoNumero titulo="Agendamentos hoje" valor={c.agendahoje} detalhe="Confirmados e realizados" para="/agenda" />
      <CartaoNumero
        titulo="Comunicados sem ciência"
        valor={c.comunicados.comunicados}
        detalhe={c.comunicados.pessoas === 0 ? "Todos cientes" : `${c.comunicados.pessoas} ${c.comunicados.pessoas === 1 ? "pessoa falta" : "pessoas faltam"}`}
        tom={c.comunicados.comunicados > 0 ? "pendente" : "neutro"}
        para="/comunicados"
      />
      <CartaoNumero titulo="Onboarding em andamento" valor={c.onboarding} detalhe="Pessoas em integração" para="/onboarding" />
      <CartaoNumero
        titulo="Solicitações abertas"
        valor={c.solicitacoes}
        detalhe="Compras e manutenção"
        tom={c.solicitacoes > 0 ? "pendente" : "neutro"}
        para="/solicitacoes"
      />
      <CartaoNumero
        titulo="Justificativas pendentes"
        valor={c.justificativas}
        detalhe='"Não se aplica" para decidir'
        tom={c.justificativas > 0 ? "pendente" : "neutro"}
        para="/justificativas"
      />
    </div>
  );
}

function Graficos({ p }: { p: PainelInicio }) {
  return (
    <div className="grid gap-4 lg:grid-cols-2">
      <div className="lg:col-span-2">
        <CaixaGrafico titulo="Vendas do mês" descricao="Vendido por dia contra a meta do dia. Verde: meta batida.">
          <GraficoVendas dados={p.vendas} hoje={p.hoje} />
        </CaixaGrafico>
      </div>
      <CaixaGrafico titulo="Pontos por semana" descricao="Entraram (aprovações e bônus, já sem estornos) e saíram (resgates).">
        <GraficoPontos dados={p.pontos} />
      </CaixaGrafico>
      <CaixaGrafico titulo="Entregas no mês" descricao="Aprovadas e recusadas, por semana.">
        <GraficoEntregas dados={p.entregas} />
      </CaixaGrafico>
    </div>
  );
}

function Lista({ titulo, para, vazio, children, n }: { titulo: string; para: string; vazio: string; n: number; children: React.ReactNode }) {
  return (
    <section className="min-w-0 rounded-xl border border-border bg-card p-4 shadow-card">
      <div className="mb-2 flex items-center justify-between gap-2">
        <h2 className="text-sm font-semibold">{titulo}</h2>
        <Link to={para} className="shrink-0 whitespace-nowrap text-xs font-medium text-primary hover:underline">
          Ver tudo
        </Link>
      </div>
      {n === 0 ? <p className="py-4 text-center text-sm text-muted-foreground">{vazio}</p> : <ul className="divide-y divide-border">{children}</ul>}
    </section>
  );
}

function Listas({ p }: { p: PainelInicio }) {
  const variasLojas = new Set([...p.agenda.map((a) => a.loja), ...p.validar.map((v) => v.loja)]).size > 1;
  return (
    <div className="grid gap-4 lg:grid-cols-3">
      <Lista titulo="Top 5 do mês" para="/ranking" vazio="Ninguém pontuou neste mês ainda." n={p.ranking.length}>
        {p.ranking.map((r, i) => (
          <li key={r.nome + i} className="flex items-center gap-3 py-2 text-sm">
            <span className={`w-6 text-center font-mono font-medium tabular-nums ${i === 0 ? "text-ouro-ink" : "text-muted-foreground"}`}>{i + 1}º</span>
            <span className="min-w-0 flex-1 truncate">{r.nome}</span>
            <Pontos valor={r.pontos} sufixo="pts" />
          </li>
        ))}
      </Lista>
      <Lista titulo="Próximos agendamentos" para="/agenda" vazio="Nenhum agendamento confirmado pela frente." n={p.agenda.length}>
        {p.agenda.map((a, i) => (
          <li key={a.quando + i} className="py-2 text-sm">
            <p className="font-medium">{quando(a.quando, p.hoje)} · {a.tipo}</p>
            <p className="text-xs text-muted-foreground">
              {a.responsavel ? `Responsável: ${a.responsavel}` : "Sem responsável"}
              {variasLojas ? ` · ${a.loja}` : ""}
            </p>
          </li>
        ))}
      </Lista>
      <Lista titulo="Últimas entregas para validar" para="/painel" vazio="Nenhuma entrega esperando." n={p.validar.length}>
        {p.validar.map((v, i) => (
          <li key={v.enviadaem + i} className="py-2 text-sm">
            <p className="font-medium">{v.titulo}</p>
            <p className="text-xs text-muted-foreground">
              {v.pessoa} · {quando(v.enviadaem, p.hoje)} · {v.pontos} pts{variasLojas ? ` · ${v.loja}` : ""}
            </p>
          </li>
        ))}
      </Lista>
    </div>
  );
}
