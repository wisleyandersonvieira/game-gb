// O painel que a TV mostra. Sem login, so leitura, sem dado pessoal.
//
// ESTA TELA E INDEPENDENTE DO RESTO DO SISTEMA, de proposito: e o unico
// aparelho que a gente nao escolhe. Ela nao usa Tailwind nem a folha do
// aplicativo — leva a propria, escrita a mao em CSS antigo (tv.css), embutida
// na propria pagina.
//
// O QUE ELA MOSTRA e escolhido pelo gestor, por loja, e vem na MESMA resposta
// do painel: a TV faz uma ida so, nunca oito.
import { useQuery } from "@tanstack/react-query";
import { useEffect, useRef, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import tvCss from "./tv.css?raw";
import type { DadosPainel } from "./PainelDaLoja";

const ATUALIZAR_A_CADA = 30_000;
/** Quantas linhas cabem numa coluna, no desenho de 1080p. */
const LINHAS = 5;
/** No maximo tres colunas por tela: mais do que isso nao se le de longe. */
const POR_TELA = 3;

type Config = {
  blocos: Record<string, boolean>;
  segundos: number;
};

type Dados = DadosPainel & {
  emandamento?: { titulo: string; pessoa: string; pegaem: string }[];
  podiomes?: { pessoa: string; pontos: number }[];
  config?: Config;
};

type Resposta = ({ disponivel: true } & Dados) | { disponivel: false };

/** "15:48" no fuso da loja. A hora vem do servidor, nunca do aparelho. */
export function hora(iso: string | null) {
  if (!iso) return "";
  return new Date(iso).toLocaleTimeString("pt-BR", {
    timeZone: "America/Sao_Paulo",
    hour: "2-digit",
    minute: "2-digit",
  });
}

function dataLonga(iso: string | null) {
  if (!iso) return "";
  return new Date(iso).toLocaleDateString("pt-BR", {
    timeZone: "America/Sao_Paulo",
    weekday: "long",
    day: "numeric",
    month: "long",
  });
}

/** "há 22 min", contado a partir da hora do SERVIDOR. */
function faz(desde: string | null, agora: string | null): { texto: string; minutos: number } {
  if (!desde || !agora) return { texto: "", minutos: 0 };
  const m = Math.max(0, Math.floor((new Date(agora).getTime() - new Date(desde).getTime()) / 60000));
  if (m < 60) return { texto: `há ${m} min`, minutos: m };
  return { texto: `há ${Math.floor(m / 60)}h${String(m % 60).padStart(2, "0")}`, minutos: m };
}

/** O pontinho de estado: azul recente, amarelo parada, vermelho parada demais. */
function corDoTempo(minutos: number): string {
  if (minutos >= 60) return "tv-ponto-vermelho";
  if (minutos >= 30) return "tv-ponto-amarelo";
  return "tv-ponto-azul";
}

export function EstiloDaTv() {
  useEffect(() => {
    document.documentElement.className += " tv";
    // Pelo JAVASCRIPT tambem: se o CSS cair inteiro, a margem do corpo
    // deixaria uma faixa branca no alto da TV.
    document.body.style.margin = "0";
    document.body.style.backgroundColor = "#0a1020";
    return () => {
      document.documentElement.className = document.documentElement.className.replace(" tv", "");
      document.body.style.margin = "";
      document.body.style.backgroundColor = "";
    };
  }, []);
  return <style dangerouslySetInnerHTML={{ __html: tvCss }} />;
}

const FUNDO = { backgroundColor: "#0a1020", color: "#eef3fb", minHeight: "100vh", padding: "4%" };

/** Divide as colunas em telas, o mais equilibrado possivel (4 -> 2+2, 5 -> 3+2). */
export function repartir<T>(colunas: T[], porTela = POR_TELA): T[][] {
  if (colunas.length <= porTela) return [colunas];
  const quantas = Math.ceil(colunas.length / porTela);
  const base = Math.floor(colunas.length / quantas);
  const sobra = colunas.length % quantas;
  const telas: T[][] = [];
  let i = 0;
  for (let t = 0; t < quantas; t++) {
    const tamanho = base + (t < sobra ? 1 : 0);
    telas.push(colunas.slice(i, i + tamanho));
    i += tamanho;
  }
  return telas;
}

function Linhas({
  itens,
  vazio,
  render,
}: {
  itens: unknown[];
  vazio: string;
  render: (item: never, i: number, ultimo: boolean) => React.ReactNode;
}) {
  // So o que couber, sem rolagem. O resto vira "+3 outras".
  const mostra = itens.slice(0, LINHAS);
  const sobra = itens.length - mostra.length;
  return (
    <ul className="tv-lista">
      {mostra.map((item, i) => render(item as never, i, i === mostra.length - 1 && sobra === 0))}
      {sobra > 0 && (
        <li className="tv-mais">
          +{sobra} {sobra === 1 ? "outra" : "outras"}
        </li>
      )}
      {/* Coluna sem nada NAO some da tela: diz o que nao tem. */}
      {itens.length === 0 && <li className="tv-vazio">{vazio}</li>}
    </ul>
  );
}

function Podio({ lista }: { lista: { pessoa: string; pontos: number }[] }) {
  const mostra = lista.slice(0, LINHAS);
  return (
    <ul className="tv-lista">
      {mostra.map((x, i) => (
        <li
          key={i}
          className={
            (i === 0 ? "tv-podio tv-podio-primeiro" : "tv-podio") +
            (i === mostra.length - 1 ? " tv-podio-fim" : "")
          }
        >
          <span className="tv-podio-lugar">{i + 1}</span>
          <span className="tv-podio-nome">{x.pessoa}</span>
          <span className="tv-podio-pontos">{x.pontos.toLocaleString("pt-BR")}</span>
        </li>
      ))}
      {lista.length === 0 && <li className="tv-vazio">Ainda sem pontos.</li>}
    </ul>
  );
}

export function TelaDaTv({ codigo, aoPerderAcesso }: { codigo: string; aoPerderAcesso?: () => void }) {
  const [tela, setTela] = useState(0);
  const [saindo, setSaindo] = useState(false);

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
        trava =
          (await (
            navigator as { wakeLock?: { request: (t: string) => Promise<{ release: () => Promise<void> }> } }
          ).wakeLock?.request("screen")) ?? null;
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

  useEffect(() => {
    if (r && !r.disponivel) aoPerderAcesso?.();
  }, [r, aoPerderAcesso]);

  const blocos = dados?.config?.blocos ?? {};
  const segundos = dados?.config?.segundos ?? 60;
  const agora = dados?.atualizadoem ?? null;

  // As colunas marcadas, na ordem do cadastro.
  const colunas = [
    blocos.parafazer && "parafazer",
    blocos.emandamento && "emandamento",
    blocos.emvalidacao && "emvalidacao",
    blocos.atividade && "atividade",
    blocos.podiohoje && "podiohoje",
    blocos.podiomes && "podiomes",
  ].filter(Boolean) as string[];

  const telas = repartir(colunas);
  const quantas = telas.length;

  // Troca sozinha, com esmaecer. Com uma tela so, nao existe troca.
  const telaRef = useRef(0);
  telaRef.current = tela;
  useEffect(() => {
    setTela(0);
    if (quantas < 2) return;
    const t = window.setInterval(() => {
      setSaindo(true);
      window.setTimeout(() => {
        setTela((v) => (v + 1) % quantas);
        setSaindo(false);
      }, 600);
    }, segundos * 1000);
    return () => window.clearInterval(t);
  }, [quantas, segundos]);

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
  const feitas = p && p.total > 0 ? Math.round((p.aprovadas / p.total) * 100) : 0;
  const meta = dados?.meta?.dia;
  const daVez = telas[Math.min(tela, quantas - 1)] ?? [];

  function coluna(qual: string, ultima: boolean) {
    const classe = ultima ? "tv-coluna tv-coluna-fim" : "tv-coluna";
    if (!dados) return <div key={qual} className={classe} />;

    if (qual === "parafazer") {
      return (
        <div key={qual} className={classe}>
          <p className="tv-rotulo">
            Para fazer<span className="tv-rotulo-conta">{dados.parafazer.length}</span>
          </p>
          <Linhas
            itens={dados.parafazer}
            vazio="Tudo feito por aqui."
            render={(t: DadosPainel["parafazer"][number], i, ultimo) => (
              <li key={i} className={ultimo ? "tv-item tv-item-fim" : "tv-item"}>
                <p className="tv-item-titulo">{t.titulo}</p>
                <p className="tv-item-linha">
                  <span className={"tv-ponto " + (t.atrasada ? "tv-ponto-vermelho" : "tv-ponto-azul")} />
                  {t.pessoa} · <span className="tv-pts">{t.pontos} pts</span>
                </p>
              </li>
            )}
          />
        </div>
      );
    }

    if (qual === "emandamento") {
      const lista = dados.emandamento ?? [];
      return (
        <div key={qual} className={classe}>
          <p className="tv-rotulo">
            Em andamento<span className="tv-rotulo-conta">{lista.length}</span>
          </p>
          <Linhas
            itens={lista}
            vazio="Ninguém pegou nada ainda."
            render={(t: { titulo: string; pessoa: string; pegaem: string }, i, ultimo) => {
              const q = faz(t.pegaem, agora);
              return (
                <li key={i} className={ultimo ? "tv-item tv-item-fim" : "tv-item"}>
                  <p className="tv-item-titulo">{t.titulo}</p>
                  <p className="tv-item-linha">
                    <span className={"tv-ponto " + corDoTempo(q.minutos)} />
                    {t.pessoa} · {q.texto}
                  </p>
                </li>
              );
            }}
          />
        </div>
      );
    }

    if (qual === "emvalidacao") {
      return (
        <div key={qual} className={classe}>
          <p className="tv-rotulo">
            Esperando o gestor<span className="tv-rotulo-conta">{dados.emvalidacao.length}</span>
          </p>
          <Linhas
            itens={dados.emvalidacao}
            vazio="Nada esperando o gestor."
            render={(t: DadosPainel["emvalidacao"][number], i, ultimo) => (
              <li key={i} className={ultimo ? "tv-item tv-item-fim" : "tv-item"}>
                <p className="tv-item-titulo">{t.titulo}</p>
                <p className="tv-item-linha">
                  <span className="tv-ponto tv-ponto-amarelo" />
                  {t.pessoa} · às {hora(t.enviadaem)}
                </p>
              </li>
            )}
          />
        </div>
      );
    }

    if (qual === "atividade") {
      return (
        <div key={qual} className={classe}>
          <p className="tv-rotulo">Atividade recente</p>
          <Linhas
            itens={dados.atividade}
            vazio="Nada aprovado hoje ainda."
            render={(t: DadosPainel["atividade"][number], i, ultimo) => (
              <li key={i} className={ultimo ? "tv-item tv-item-fim" : "tv-item"}>
                <p className="tv-item-titulo">{t.titulo}</p>
                <p className="tv-item-linha">
                  <span className="tv-ponto tv-ponto-verde" />
                  {t.pessoa} · {hora(t.aprovadaem)} · <span className="tv-pts">+{t.pontos}</span>
                </p>
              </li>
            )}
          />
        </div>
      );
    }

    if (qual === "podiohoje") {
      return (
        <div key={qual} className={classe}>
          <p className="tv-rotulo">Pódio de hoje</p>
          <Podio lista={dados.podio} />
        </div>
      );
    }

    return (
      <div key={qual} className={classe}>
        <p className="tv-rotulo">Pódio do mês</p>
        <Podio lista={dados.podiomes ?? []} />
      </div>
    );
  }

  return (
    <div className="tv-tela" style={FUNDO}>
      <EstiloDaTv />

      {/* Cabecalho FIXO: nunca sai da tela. */}
      <div className="tv-topo">
        <div>
          <div className="tv-marca">
            <span className="tv-marca-quadro" />
            <span className="tv-marca-nome">STGame</span>
          </div>
          <h1 className="tv-loja" style={{ fontSize: "68px", margin: 0 }}>
            {dados?.loja ?? "Carregando..."}
          </h1>
        </div>
        <div>
          <p className="tv-relogio">{painel.isError ? "--:--" : hora(agora)}</p>
          <p className="tv-data">
            {painel.isError ? "Sem conexão. Tentando de novo..." : dataLonga(agora)}
          </p>
        </div>
      </div>

      {/* As faixas marcadas: finas, lado a lado, em TODAS as telas. */}
      {dados && (blocos.barra || blocos.meta) && (
        <div className="tv-faixas">
          {blocos.barra && (
            <div className={blocos.meta ? "tv-faixa" : "tv-faixa tv-faixa-fim"}>
              <div className="tv-faixa-alto">
                <span className="tv-faixa-texto">
                  <span className="tv-faixa-forte">
                    {p!.aprovadas} de {p!.total}
                  </span>{" "}
                  tarefas concluídas hoje
                </span>
                <span className="tv-faixa-numero tv-verde">{feitas}%</span>
              </div>
              <div className="tv-barra">
                <div className="tv-barra-verde" style={{ width: feitas + "%" }} />
              </div>
            </div>
          )}
          {blocos.meta && (
            <div className="tv-faixa tv-faixa-fim">
              <div className="tv-faixa-alto">
                <span className="tv-faixa-texto">Meta do dia</span>
                <span className="tv-faixa-numero tv-azul">{Math.round(meta?.percentual ?? 0)}%</span>
              </div>
              <div className="tv-barra">
                <div
                  className="tv-barra-azul"
                  style={{ width: Math.min(100, Math.round(meta?.percentual ?? 0)) + "%" }}
                />
              </div>
            </div>
          )}
        </div>
      )}

      <div className={saindo ? "tv-colunas tv-troca tv-troca-saindo" : "tv-colunas tv-troca"}>
        {daVez.map((c, i) => coluna(c, i === daVez.length - 1))}
      </div>

      {/* Com uma tela so, nao existe indicador. */}
      {quantas > 1 && (
        <div className="tv-rodape">
          <span>
            {Math.min(tela, quantas - 1) + 1} de {quantas}
          </span>
          {Array.from({ length: quantas }).map((_, i) => (
            <span
              key={i}
              className={i === Math.min(tela, quantas - 1) ? "tv-pontinho tv-pontinho-aceso" : "tv-pontinho"}
            />
          ))}
        </div>
      )}
    </div>
  );
}
