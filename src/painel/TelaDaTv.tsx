// O painel que a TV mostra. Sem login, so leitura, sem dado pessoal.
//
// ESTA TELA E INDEPENDENTE DO RESTO DO SISTEMA, de proposito: e a unica que
// roda num aparelho que a gente nao escolhe. Ela nao usa Tailwind nem a folha
// de estilo do aplicativo — leva a propria, escrita a mao em CSS antigo
// (src/painel/tv.css), embutida na propria pagina.
//
// Motivo: em 25/09/2026 uma TV Samsung mostrou a pagina SEM ESTILO NENHUM. O
// Tailwind 4 envolve tudo o que gera em @layer, e o navegador que nao conhece
// @layer descarta o bloco inteiro — nao uma cor, a folha toda.
//
// Desenho para ser lido de longe: letra grande, fundo escuro solido, margem de
// 4% nas bordas (TV corta as beiradas), layout fixo de 1920x1080 sem rolagem.
// Lista que nao cabe NAO rola: ela vira paginas, que se alternam sozinhas.
import { useQuery } from "@tanstack/react-query";
import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import tvCss from "./tv.css?raw";
import type { DadosPainel } from "./PainelDaLoja";

const ATUALIZAR_A_CADA = 30_000;
/** Rodizio de telas: painel -> meta -> agenda. */
const TROCAR_TELA_A_CADA = 30_000;
/** Quando a lista nao cabe, troca de pagina neste intervalo. */
const TROCAR_PAGINA_A_CADA = 8_000;
/** Quantas linhas cabem numa coluna, no desenho de 1080p. */
const LINHAS_POR_PAGINA = 6;

type Resposta = ({ disponivel: true } & DadosPainel) | { disponivel: false };

export function hora(iso: string | null) {
  if (!iso) return "";
  return new Date(iso).toLocaleTimeString("pt-BR", {
    timeZone: "America/Sao_Paulo",
    hour: "2-digit",
    minute: "2-digit",
  });
}

/**
 * A folha da TV, embutida na propria pagina.
 *
 * Embutida, e nao num arquivo separado, para a TV nao depender de uma segunda
 * ida a rede: se a folha nao chegasse, a tela ficaria sem estilo de novo.
 */
export function EstiloDaTv() {
  // A classe no <html> e o que separa a TV do resto: nenhuma regra daqui
  // alcanca as telas do gestor.
  useEffect(() => {
    document.documentElement.className += " tv";
    // Pelo JAVASCRIPT, e nao so pela folha: se o CSS cair inteiro, a margem
    // do corpo deixaria uma faixa branca no alto da TV. O JavaScript roda
    // mesmo nas TVs onde o CSS moderno nao roda — foi o que se viu na loja.
    document.body.style.margin = "0";
    document.body.style.backgroundColor = "#0b1220";
    return () => {
      document.documentElement.className = document.documentElement.className.replace(" tv", "");
      document.body.style.margin = "";
      document.body.style.backgroundColor = "";
    };
  }, []);
  return <style dangerouslySetInnerHTML={{ __html: tvCss }} />;
}

/**
 * A ULTIMA LINHA DE DEFESA: estilo no proprio elemento.
 *
 * Se a folha inteira cair — por qualquer motivo que a gente nao previu —, o
 * atributo style continua valendo, porque nao passa pelo interpretador de CSS.
 * Garante o minimo pedido: fundo escuro, letra grande e margem de borda.
 */
const FUNDO = { backgroundColor: "#0b1220", color: "#f2f6fc", minHeight: "100vh", padding: "4%" };
const TITULO = { fontSize: "76px", margin: "0" };

/** Quebra a lista em paginas, porque a TV nao rola. */
function paginar<T>(itens: T[], porPagina: number): T[][] {
  if (itens.length === 0) return [[]];
  const paginas: T[][] = [];
  for (let i = 0; i < itens.length; i += porPagina) paginas.push(itens.slice(i, i + porPagina));
  return paginas;
}

/** O rodizio de paginas: anda sozinho, e volta ao inicio quando a lista muda. */
function usePagina(quantas: number) {
  const [pagina, setPagina] = useState(0);
  useEffect(() => {
    setPagina(0);
    if (quantas < 2) return;
    const t = window.setInterval(() => setPagina((p) => (p + 1) % quantas), TROCAR_PAGINA_A_CADA);
    return () => window.clearInterval(t);
  }, [quantas]);
  return Math.min(pagina, Math.max(0, quantas - 1));
}

function Coluna({
  titulo,
  itens,
  vazio,
  render,
}: {
  titulo: string;
  itens: unknown[];
  vazio: string;
  render: (item: never, i: number, ultimo: boolean) => React.ReactNode;
  fim?: boolean;
}) {
  const paginas = paginar(itens, LINHAS_POR_PAGINA);
  const pagina = usePagina(paginas.length);
  const atual = paginas[pagina] ?? [];

  return (
    <>
      <h2 className="tv-coluna-titulo">{titulo}</h2>
      <ul className="tv-lista">
        {atual.map((item, i) => render(item as never, i, i === atual.length - 1))}
        {itens.length === 0 && <li className="tv-vazio">{vazio}</li>}
      </ul>
      {paginas.length > 1 && (
        <p className="tv-paginas">
          Página {pagina + 1} de {paginas.length}
        </p>
      )}
    </>
  );
}

/**
 * O painel da TV. Serve aos dois caminhos: o link comprido de sempre
 * (/tv/<codigo>) e a TV pareada por codigo curto (/tv).
 *
 * `aoPerderAcesso` existe para o pareamento: quando o gestor revoga, o painel
 * passa a responder "indisponivel" e a TV precisa VOLTAR SOZINHA para a tela
 * do codigo, sem ninguem ir ate la.
 */
export function TelaDaTv({ codigo, aoPerderAcesso }: { codigo: string; aoPerderAcesso?: () => void }) {
  const [tela, setTela] = useState(0);

  const painel = useQuery({
    queryKey: ["tv", codigo],
    refetchInterval: ATUALIZAR_A_CADA,
    refetchIntervalInBackground: true,
    retry: true,
    queryFn: async () => {
      const { data, error } = await supabase.rpc("painel_da_tv", { p_codigo: codigo });
      if (error) throw error;
      return data as unknown as Resposta;
    },
  });

  // Mantem a tela acesa (TVs e celulares com navegador que suportam).
  useEffect(() => {
    let trava: { release: () => Promise<void> } | null = null;
    const pedir = async () => {
      try {
        trava = await (navigator as { wakeLock?: { request: (t: string) => Promise<{ release: () => Promise<void> }> } })
          .wakeLock?.request("screen") ?? null;
      } catch {
        /* sem suporte: a tela pode apagar sozinha */
      }
    };
    pedir();
    const aoVoltar = () => document.visibilityState === "visible" && pedir();
    document.addEventListener("visibilitychange", aoVoltar);
    return () => {
      document.removeEventListener("visibilitychange", aoVoltar);
      trava?.release().catch(() => {});
    };
  }, []);

  const r = painel.data;
  const dados = r && r.disponivel ? r : null;

  // Revogada: avisa quem cuida do pareamento e sai da frente.
  useEffect(() => {
    if (r && !r.disponivel) aoPerderAcesso?.();
  }, [r, aoPerderAcesso]);

  // Rodizio: entram so as telas com conteudo.
  const telas = ["painel", ...(dados?.meta ? ["meta"] : []), ...((dados?.agenda ?? []).length > 0 ? ["agenda"] : [])];
  const quantas = telas.length;
  useEffect(() => {
    setTela(0);
    if (quantas < 2) return;
    const t = window.setInterval(() => setTela((v) => (v + 1) % quantas), TROCAR_TELA_A_CADA);
    return () => window.clearInterval(t);
  }, [quantas]);
  const atual = telas[tela % quantas] ?? "painel";

  if (r && !r.disponivel) {
    return (
      <div className="tv-tela" style={FUNDO}>
        <EstiloDaTv />
        <div className="tv-centro">
          <p className="tv-recado">Painel indisponível</p>
          <p className="tv-legenda">Peça o painel de novo ao responsável pela loja.</p>
        </div>
      </div>
    );
  }

  const p = dados?.progresso;
  const feito = p && p.total > 0 ? Math.round((p.aprovadas / p.total) * 100) : 0;

  return (
    <div className="tv-tela" style={FUNDO}>
      <EstiloDaTv />

      <div className="tv-topo">
        <h1 className="tv-loja" style={TITULO}>{dados?.loja ?? "Carregando..."}</h1>
        <p className={painel.isError ? "tv-relogio tv-relogio-erro" : "tv-relogio"}>
          {painel.isError
            ? "Sem conexão. Tentando de novo..."
            : dados
              ? "Atualizado às " + hora(dados.atualizadoem)
              : ""}
        </p>
      </div>

      {dados && atual === "painel" && (
        <>
          <div className="tv-progresso">
            <p className="tv-progresso-texto">
              {p!.aprovadas} de {p!.total} tarefas prontas · {p!.emvalidacao} esperando o gestor
            </p>
            <div className="tv-barra">
              <div className="tv-barra-feita" style={{ width: feito + "%" }} />
            </div>
          </div>

          <div className="tv-colunas">
            <div className="tv-coluna">
              <Coluna
                titulo="Para fazer"
                itens={dados.parafazer}
                vazio="Tudo feito por aqui."
                render={(t: DadosPainel["parafazer"][number], i, ultimo) => (
                  <li key={i} className={ultimo ? "tv-item tv-item-fim" : "tv-item"}>
                    <span className={t.atrasada ? "tv-item-texto tv-atrasada" : "tv-item-texto"}>
                      {t.titulo}
                      <span className="tv-item-pessoa">{t.pessoa}</span>
                    </span>
                    <span className="tv-item-pontos">{t.pontos}</span>
                  </li>
                )}
              />
            </div>

            <div className="tv-coluna">
              <Coluna
                titulo="Esperando o gestor"
                itens={dados.emvalidacao}
                vazio="Nada esperando."
                render={(t: DadosPainel["emvalidacao"][number], i, ultimo) => (
                  <li key={i} className={ultimo ? "tv-item tv-item-fim" : "tv-item"}>
                    <span className="tv-item-texto">
                      {t.titulo}
                      <span className="tv-item-pessoa">
                        {t.pessoa} · {hora(t.enviadaem)}
                      </span>
                    </span>
                    <span className="tv-item-pontos">{t.pontos}</span>
                  </li>
                )}
              />
            </div>

            <div className="tv-coluna tv-coluna-fim">
              <h2 className="tv-coluna-titulo">Pódio do mês</h2>
              <ul className="tv-lista">
                {dados.podio.slice(0, 5).map((x, i) => (
                  <li key={i} className="tv-podio-linha">
                    <span className="tv-medalha">{["🥇", "🥈", "🥉"][i] ?? "  "}</span>
                    <span className="tv-podio-nome">{x.pessoa}</span>
                    <span className="tv-item-pontos">{x.pontos}</span>
                  </li>
                ))}
                {dados.podio.length === 0 && <li className="tv-vazio">Ainda sem pontos este mês.</li>}
              </ul>
            </div>
          </div>
        </>
      )}

      {dados && atual === "meta" && dados.meta && (
        <div className="tv-centro">
          <p className={dados.meta.dia?.bateu ? "tv-numerao tv-bateu" : "tv-numerao"}>
            {Math.round(dados.meta.dia?.percentual ?? 0)}%
          </p>
          <p className="tv-legenda">{dados.meta.dia?.bateu ? "Meta do dia batida!" : "da meta de hoje"}</p>
        </div>
      )}

      {dados && atual === "agenda" && (
        <div className="tv-colunas">
          <div className="tv-coluna tv-coluna-fim">
            <Coluna
              titulo="Próximos da agenda"
              itens={dados.agenda}
              vazio="Nada marcado."
              render={(a: DadosPainel["agenda"][number], i, ultimo) => (
                <li key={i} className={ultimo ? "tv-item tv-item-fim" : "tv-item"}>
                  <span className="tv-item-texto">{a.tipo}</span>
                  <span className="tv-item-pontos">{hora(a.quando)}</span>
                </li>
              )}
            />
          </div>
        </div>
      )}
    </div>
  );
}
