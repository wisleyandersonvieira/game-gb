import { createFileRoute } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Carregando } from "@/ui/Estados";
import { TabelaResponsiva } from "@/ui/TabelaResponsiva";
import { Rotinas } from "@/configuracoes/Rotinas";
import { MensagensAutomaticas } from "@/configuracoes/MensagensAutomaticas";
import { PoliticaDeUso } from "@/configuracoes/PoliticaDeUso";
import { Pagina } from "@/ui/Pagina";

export const Route = createFileRoute("/_authenticated/configuracoes")({
  component: Configuracoes,
});

const campo =
  "rounded-lg border border-border bg-background px-3 py-2 text-sm placeholder:text-muted-foreground";

const reais = (v: number) =>
  new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(v);

type Item = { chave: string; rotulo: string; ajuda: string; tipo: "taxa" | "inteiro" | "horario" | "texto"; unidade?: string };

/** O que aparece na tela. Os IDs das tarefas do sistema (TAREFA_*) ficam de fora: o sistema cuida deles. */
const GRUPOS: { titulo: string; aviso?: string; itens: Item[] }[] = [
  {
    titulo: "Pontos",
    itens: [
      {
        chave: "TAXA_CONVERSAO_PONTO_REAL",
        rotulo: "Quanto vale 1 ponto",
        ajuda: "Usado no abate na comanda e nos valores em R$ do extrato. Mudar a taxa vale só para as próximas comandas.",
        tipo: "taxa",
        unidade: "R$",
      },
      {
        chave: "PONTOS_BONUS_FEEDBACK_DIARIO",
        rotulo: "Bônus do feedback diário",
        ajuda: "Pontos por enviar o feedback do dia. Começa a valer quando o módulo de feedbacks existir.",
        tipo: "inteiro",
        unidade: "pontos",
      },
      {
        chave: "PONTOS_BONUS_NOTA_FISCAL",
        rotulo: "Bônus por nota fiscal",
        ajuda: "Pontos por enviar uma nota fiscal. Começa a valer com o módulo de estoque.",
        tipo: "inteiro",
        unidade: "pontos",
      },
    ],
  },
  {
    titulo: "Horários das rotinas",
    aviso: "Os três primeiros já rodam sozinhos. Os lembretes chegam com o bot; os horários deles já ficam guardados.",
    itens: [
      {
        chave: "HORARIO_GERACAO_TAREFAS",
        rotulo: "Lista de tarefas do dia",
        ajuda: "A partir deste horário a lista do dia é gerada e, depois, ajustada a cada 5 minutos.",
        tipo: "horario",
      },
      {
        chave: "HORARIO_FECHAMENTO_MENSAL",
        rotulo: "Fechamento mensal do ranking",
        ajuda: "Dias 1 a 7: provisório, refeito todo dia. No dia 8 vira definitivo.",
        tipo: "horario",
      },
      {
        chave: "HORARIO_CONFERENCIA_LIVRO",
        rotulo: "Conferência do livro de pontos",
        ajuda: "Confere se o saldo de cada pessoa bate com o livro. Nunca corrige sozinha: só avisa.",
        tipo: "horario",
      },
      {
        chave: "HORARIO_DELEGACAO_FOLGA",
        rotulo: "Repasse automático das tarefas de folga (bot)",
        ajuda: "Hoje o repasse é feito no Quadro, pelo gestor.",
        tipo: "horario",
      },
      { chave: "HORARIO_LEMBRETE_COMUNICADOS", rotulo: "Lembrete de comunicados não lidos", ajuda: "", tipo: "horario" },
      { chave: "HORARIO_LEMBRETE_HOJE", rotulo: "Lembrete da agenda de hoje", ajuda: "", tipo: "horario" },
      { chave: "HORARIO_LEMBRETE_DIARIO_AMANHA", rotulo: "Lembrete da agenda de amanhã", ajuda: "", tipo: "horario" },
      { chave: "HORARIO_LEMBRETE_SEMANAL", rotulo: "Lembrete semanal da agenda", ajuda: "", tipo: "horario" },
    ],
  },
  {
    titulo: "Mensagens do bot",
    aviso: "Valem para todas as lojas. O que liga e desliga cada mensagem está logo abaixo, em Mensagens automáticas.",
    itens: [
      {
        chave: "HORARIO_SILENCIO_INICIO",
        rotulo: "Começo do silêncio",
        ajuda: "A partir desta hora o bot não manda mensagem automática. Não vale dentro do turno da pessoa: quem trabalha à noite recebe normalmente.",
        tipo: "horario",
      },
      {
        chave: "HORARIO_SILENCIO_FIM",
        rotulo: "Fim do silêncio",
        ajuda: "A partir desta hora o bot volta a mandar.",
        tipo: "horario",
      },
      {
        chave: "MAX_MENSAGENS_AUTOMATICAS_DIA",
        rotulo: "Máximo de mensagens por pessoa por dia",
        ajuda: "Conta só as mensagens automáticas. As respostas ao que a própria pessoa faz não contam.",
        tipo: "inteiro",
        unidade: "mensagens",
      },
      {
        chave: "MAX_TAREFAS_FOLGA_POR_PESSOA",
        rotulo: "Máximo de tarefas extras por pessoa por dia",
        ajuda: "Quantas tarefas de quem está de folga uma pessoa pode pegar pelo grupo no mesmo dia.",
        tipo: "inteiro",
        unidade: "tarefas",
      },
    ],
  },
  {
    titulo: "Aceite de tarefas",
    aviso:
      "Vale só para tarefa atribuída a várias pessoas e para missão da equipe. Tarefa com dono único não muda.",
    itens: [
      {
        chave: "MINUTOS_RODIZIO_ACEITE",
        rotulo: "Tempo de espera para quem pegou a última tarefa",
        ajuda:
          "Quem pegou a última tarefa disputada da loja espera este tempo antes de pegar outra, para dar chance aos colegas. Assim que outra pessoa pega alguma coisa, quem estava esperando é liberado na hora. Se a pessoa for a única disponível no dia, ela pega na hora. 0 desliga o rodízio.",
        tipo: "inteiro",
        unidade: "minutos",
      },
      {
        chave: "MINUTOS_TAREFA_PARADA",
        rotulo: "Marcar tarefa como parada depois de",
        ajuda:
          "No tablet, o cronômetro do cartão muda de cor quando a tarefa passa deste tempo sem ninguém pegar.",
        tipo: "inteiro",
        unidade: "minutos",
      },
    ],
  },
  {
    titulo: "Fotos",
    itens: [
      {
        chave: "MAX_DIFERENCA_FOTO_SEGUNDOS",
        rotulo: "Tolerância da hora da foto",
        ajuda: "Diferença máxima entre a hora em que a foto foi tirada e o envio. Usada pelo bot.",
        tipo: "inteiro",
        unidade: "segundos",
      },
      {
        chave: "DIAS_GUARDAR_FOTO_ENTREGA",
        rotulo: "Por quanto tempo guardar a foto da entrega",
        ajuda:
          "Passado esse prazo, o arquivo da foto é apagado automaticamente. A entrega, os pontos e o histórico ficam; a tela passa a mostrar \"foto removida por tempo\". Mínimo 90 dias.",
        tipo: "inteiro",
        unidade: "dias",
      },
    ],
  },
  {
    titulo: "Política de uso",
    aviso: "Aparece na política que cada pessoa aceita no primeiro acesso.",
    itens: [
      {
        chave: "CONTATO_PRIVACIDADE",
        rotulo: "Responsável pelos dados",
        ajuda: "Nome e contato de quem responde sobre dados pessoais (LGPD). Ex.: Maria Silva — rh@empresa.com.br",
        tipo: "texto",
      },
    ],
  },
];

const ROTULO = new Map(GRUPOS.flatMap((g) => g.itens.map((i) => [i.chave, i.rotulo] as const)));

function dataHora(iso: string) {
  return new Date(iso).toLocaleString("pt-BR", {
    timeZone: "America/Sao_Paulo",
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

/** Mostra o valor como a pessoa lê: taxa com vírgula. */
function mostrar(chave: string, valor: string | null) {
  if (valor === null || valor === "") return "—";
  if (chave === "TAXA_CONVERSAO_PONTO_REAL") return reais(Number(valor));
  return valor;
}

function Configuracoes() {
  const qc = useQueryClient();

  const eu = useQuery({
    queryKey: ["meu-papel"],
    queryFn: async () => {
      const { data: sessao } = await supabase.auth.getUser();
      const uid = sessao.user?.id ?? null;
      if (!uid) return { uid: null, master: false };
      const { data } = await supabase.from("contasusuarios").select("papel").eq("userid", uid).maybeSingle();
      return { uid, master: data?.papel === "master" };
    },
  });

  const configs = useQuery({
    queryKey: ["configuracoes"],
    queryFn: async () => {
      const { data, error } = await supabase.from("configuracoes").select("chave, valor, atualizadoem");
      if (error) throw error;
      return new Map((data ?? []).map((c) => [c.chave, c]));
    },
  });

  const historico = useQuery({
    queryKey: ["configuracoes-historico"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("configuracoeshistorico")
        .select("historicoid, chave, valoranterior, valornovo, alteradopor, alteradoem")
        .order("alteradoem", { ascending: false })
        .limit(50);
      if (error) throw error;
      return data ?? [];
    },
  });

  const podeAlterar = eu.data?.master ?? false;

  return (
    <Pagina titulo="Configurações">

      {eu.data && !podeAlterar && (
        <p className="rounded-lg border border-azul/40 bg-azul-soft px-4 py-3 text-sm text-azul">
          Só o responsável pela conta altera as configurações. Você pode consultar.
        </p>
      )}
      {configs.isLoading && <p className="text-muted-foreground">Carregando...</p>}
      {configs.isError && <p className="text-sm text-destructive">{(configs.error as Error).message}</p>}

      {configs.data &&
        GRUPOS.map((g) => (
          <section key={g.titulo} className="space-y-3 rounded-xl border border-border bg-card p-4">
            <h2 className="text-lg font-semibold">{g.titulo}</h2>
            {g.aviso && <p className="text-xs text-muted-foreground">{g.aviso}</p>}
            {g.itens.map((item) => {
              const atual = configs.data.get(item.chave);
              if (!atual) return null;
              return (
                <Linha
                  key={item.chave}
                  item={item}
                  valor={atual.valor ?? ""}
                  podeAlterar={podeAlterar}
                  aoSalvar={() => {
                    for (const k of ["configuracoes", "configuracoes-historico", "minha-taxa", "extrato"]) {
                      qc.invalidateQueries({ queryKey: [k] });
                    }
                  }}
                />
              );
            })}
          </section>
        ))}

      <PoliticaDeUso podeAlterar={podeAlterar} />

      <Rotinas podeRodar={podeAlterar} />

      <MensagensAutomaticas podeAlterar={podeAlterar} />

      <section className="space-y-2">
        <h2 className="text-lg font-semibold">Histórico de mudanças</h2>
        {historico.isError && <p className="text-sm text-destructive">{(historico.error as Error).message}</p>}
        {historico.isLoading ? (
          <Carregando />
        ) : (
          <TabelaResponsiva
            linhas={historico.data ?? []}
            chave={(h) => h.historicoid}
            vazio="Nenhuma mudança ainda."
            colunas={[
              { titulo: "O quê", principal: true, valor: (h) => ROTULO.get(h.chave) ?? h.chave },
              { titulo: "Quando", valor: (h) => dataHora(h.alteradoem), classe: () => "whitespace-nowrap text-muted-foreground" },
              { titulo: "De", valor: (h) => mostrar(h.chave, h.valoranterior), classe: () => "text-muted-foreground" },
              { titulo: "Para", valor: (h) => mostrar(h.chave, h.valornovo), classe: () => "font-medium" },
              {
                titulo: "Quem",
                valor: (h) =>
                  h.alteradopor && h.alteradopor === eu.data?.uid ? "Você" : h.alteradopor ? "Outro usuário" : "Sistema",
                classe: () => "text-muted-foreground",
              },
            ]}
          />
        )}
      </section>
    </Pagina>
  );
}

function Linha({
  item,
  valor,
  podeAlterar,
  aoSalvar,
}: {
  item: Item;
  valor: string;
  podeAlterar: boolean;
  aoSalvar: () => void;
}) {
  const paraTela = (v: string) => (item.tipo === "taxa" ? v.replace(".", ",") : v);
  const [texto, setTexto] = useState(paraTela(valor));
  const [ok, setOk] = useState(false);

  useEffect(() => setTexto(paraTela(valor)), [valor]); // eslint-disable-line react-hooks/exhaustive-deps

  const salvar = useMutation({
    mutationFn: async () => {
      const limpo = texto.trim();
      if (item.tipo === "taxa") {
        const n = Number(limpo.replace(",", "."));
        if (!(n > 0)) throw new Error("A taxa precisa ser maior que zero.");
      }
      if (item.tipo === "inteiro" && !/^\d+$/.test(limpo)) throw new Error("Use um número inteiro, 0 ou mais.");
      if (item.tipo === "horario" && !/^([01]\d|2[0-3]):[0-5]\d$/.test(limpo)) throw new Error("Use o formato HH:MM.");
      // O banco confere de novo e registra quem mudou.
      const { error } = await supabase.rpc("alterar_configuracao", { p_chave: item.chave, p_valor: limpo });
      if (error) throw error;
    },
    onSuccess: () => {
      setOk(true);
      setTimeout(() => setOk(false), 2500);
      aoSalvar();
    },
  });

  const mudou = texto.trim() !== paraTela(valor);
  const taxaPrevia = item.tipo === "taxa" ? Number(texto.replace(",", ".")) : NaN;

  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        salvar.mutate();
      }}
      className="space-y-1 border-t border-border pt-3 first-of-type:border-t-0 first-of-type:pt-0"
    >
      <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between sm:gap-3">
        <label htmlFor={item.chave} className="font-medium">
          {item.rotulo}
        </label>
        <div className="flex items-center gap-2">
          {item.unidade === "R$" && <span className="text-sm text-muted-foreground">R$</span>}
          <input
            id={item.chave}
            type={item.tipo === "horario" ? "time" : "text"}
            inputMode={item.tipo === "taxa" ? "decimal" : item.tipo === "inteiro" ? "numeric" : undefined}
            value={texto}
            disabled={!podeAlterar}
            onChange={(e) => setTexto(e.target.value)}
            maxLength={item.tipo === "texto" ? 200 : undefined}
            placeholder={item.tipo === "texto" ? "Nome — e-mail ou telefone" : undefined}
            className={`${campo} ${item.tipo === "horario" ? "w-36" : item.tipo === "texto" ? "w-full sm:w-96" : "w-28"}`}
          />
          {item.unidade && item.unidade !== "R$" && (
            <span className="text-sm text-muted-foreground">{item.unidade}</span>
          )}
          {podeAlterar && (
            <button
              type="submit"
              disabled={!mudou || salvar.isPending}
              className="rounded-lg bg-primary px-3 py-2 text-sm font-semibold text-primary-foreground disabled:opacity-40"
            >
              Salvar
            </button>
          )}
        </div>
      </div>
      {item.ajuda && <p className="text-xs text-muted-foreground">{item.ajuda}</p>}
      {item.tipo === "taxa" && taxaPrevia > 0 && (
        <p className="text-xs text-muted-foreground">
          100 pontos = {reais(100 * taxaPrevia)} · 1.000 pontos = {reais(1000 * taxaPrevia)}
        </p>
      )}
      {ok && <p className="text-xs text-sucesso">Salvo.</p>}
      {salvar.isError && <p className="text-xs text-destructive">{(salvar.error as Error).message}</p>}
    </form>
  );
}
