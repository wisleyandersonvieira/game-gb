// Etapa 1.12, parte B1b — o tablet do balcão.
//
// Ele fica logado como a LOJA, não como pessoa. Por isso toda ação com dono é
// assinada com o PIN de 6 dígitos: o servidor descobre quem é e registra em
// nome dela. O PIN nunca aparece na tela e não fica guardado em lugar nenhum.
//
// A fila atualiza a cada 15 segundos e NA HORA depois de qualquer toque: a
// tarefa que alguém acabou de pegar precisa sumir rápido da lista dos outros.
import { createFileRoute, redirect, useNavigate } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useRef, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { meuAcesso } from "@/integrations/supabase/destino";
import {
  autorizacaoDeFoto,
  conferirPinNoTablet,
  entregarNoTablet,
  filaDoTablet,
  pegarNoTablet,
  type ItemDaFila,
} from "@/servidor/tablet";
import { faz, minutosDesde, useRelogio } from "@/ui/relogio";
import { liberarSom, somLiberado, tarefasNovas, tocar } from "@/painel/somDaFila";
import { PedidoNoTablet } from "@/painel/PedidoNoTablet";
import { MuralNoTablet } from "@/painel/MuralNoTablet";

export const Route = createFileRoute("/tablet")({
  ssr: false,
  beforeLoad: async () => {
    // getSession() é local: não gasta uma ida ao servidor só para saber se
    // existe token. Quem confere de verdade é meuAcesso(), no banco.
    const { data } = await supabase.auth.getSession();
    if (!data.session) throw redirect({ to: "/auth" });
    const acesso = await meuAcesso();
    if (acesso.tipo !== "loja") throw redirect({ to: "/sem-acesso" });
  },
  component: Tablet,
});

const SEGUNDOS = 15;

/** "14h37" — o jeito como a equipe fala a hora. */
function hora(iso: string | null) {
  if (!iso) return "";
  return new Date(iso)
    .toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" })
    .replace(":", "h");
}

type Acao =
  | { tipo: "pegar"; item: ItemDaFila }
  | { tipo: "entregar"; item: ItemDaFila; arquivo: File | null; observacao: string };

function Tablet() {
  const qc = useQueryClient();
  const navigate = useNavigate();
  const [acao, setAcao] = useState<Acao | null>(null);
  const [pedindoPin, setPedindoPin] = useState(false);
  const [recado, setRecado] = useState<string | null>(null);
  // Som: o navegador só deixa tocar depois de alguém encostar na tela.
  const [somPreso, setSomPreso] = useState(true);
  // Cartões que acabaram de chegar: destacam por alguns segundos. É o aviso
  // que vale enquanto o som estiver bloqueado.
  const [novas, setNovas] = useState<number[]>([]);
  const jaVistas = useRef<number[] | null>(null);
  // O menu do tablet. Hoje tem um item; mural, feedback, justificativa e
  // painel entram aqui quando existirem.
  const [menuAberto, setMenuAberto] = useState(false);
  // Quando a pessoa toca num item do menu, o PIN é pedido para ELE.
  const [doMenu, setDoMenu] = useState<"pedido" | "mural" | null>(null);
  type Sessao = { nome: string; passe: string; funcionarioid: number };
  const [pedido, setPedido] = useState<Sessao | null>(null);
  const [mural, setMural] = useState<Sessao | null>(null);

  const fila = useQuery({
    queryKey: ["fila-tablet"],
    refetchInterval: SEGUNDOS * 1000,
    refetchOnWindowFocus: true,
    queryFn: () => filaDoTablet(),
  });

  const agir = useMutation({
    mutationFn: async (pin: string) => {
      if (!acao) throw new Error("Nada para fazer.");
      if (acao.tipo === "pegar") {
        return await pegarNoTablet({ data: { pin, atribuicaoid: acao.item.atribuicaoid } });
      }
      // A foto sobe direto para o Storage com uma autorização de prazo curto:
      // a chave secreta nunca passa por aqui.
      let caminho: string | null = null;
      let bilhete: string | null = null;
      if (acao.arquivo) {
        const a = await autorizacaoDeFoto({ data: { atribuicaoid: acao.item.atribuicaoid } });
        const { error } = await supabase.storage.from("entregas").uploadToSignedUrl(a.caminho, a.token, acao.arquivo);
        if (error) throw new Error("A foto não subiu. Tente de novo.");
        caminho = a.caminho;
        bilhete = a.bilhete;
      }
      return await entregarNoTablet({
        data: { pin, atribuicaoid: acao.item.atribuicaoid, caminho, bilhete, observacao: acao.observacao || null },
      });
    },
    onSuccess: (r) => {
      const feito = acao?.tipo === "pegar" ? "pegou" : "entregou";
      setRecado(`${r.nome} ${feito} "${acao?.item.titulo}".`);
      setAcao(null);
      setPedindoPin(false);
      qc.invalidateQueries({ queryKey: ["fila-tablet"] });
      setTimeout(() => setRecado(null), 6000);
    },
  });

  // O PIN do menu usa a MESMA modal e a MESMA trava do pegar tarefa.
  const abrirPedido = useMutation({
    mutationFn: (pin: string) =>
      conferirPinNoTablet({ data: { pin, assunto: doMenu === "mural" ? "mural" : "pedido" } }),
    onSuccess: (r) => {
      const sessao = { nome: r.nome, passe: r.passe, funcionarioid: r.funcionarioid };
      if (doMenu === "mural") setMural(sessao);
      else setPedido(sessao);
      setDoMenu(null);
    },
  });

  // TAREFA NOVA NA FILA: compara o que já estava na tela com o que chegou.
  // Vale também para a tarefa que o horário programado acabou de liberar,
  // porque ela só entra nesta lista quando libera.
  const fila_itens = fila.data?.itens;
  const som = fila.data?.som;
  useEffect(() => {
    if (!fila_itens) return;
    const agora = fila_itens.filter((i) => i.situacao === "para_pegar" && i.liberada).map((i) => i.atribuicaoid);
    const chegaram = tarefasNovas(jaVistas.current, agora);
    jaVistas.current = agora;
    if (chegaram.length === 0) return;

    setNovas(chegaram);
    // Uma vez só, por mais tarefas que tenham chegado juntas.
    if (som?.ligado && somLiberado()) void tocar(som.volume);
    const t = window.setTimeout(() => setNovas([]), 8000);
    return () => window.clearTimeout(t);
  }, [fila_itens, som]);

  // Tenta liberar o som sozinho: em alguns aparelhos já vem liberado.
  useEffect(() => {
    void liberarSom().then((ok) => setSomPreso(!ok));
  }, []);

  // O relógio anda sozinho aqui; a fila só conversa com o banco a cada 15 s.
  useRelogio();
  const itens = fila.data?.itens ?? [];
  const agora = itens[0]?.agora ?? null;
  const minutosParada = fila.data?.minutosParada ?? 30;
  const faixa = (s: ItemDaFila["situacao"]) => itens.filter((i) => i.situacao === s);
  // Antes da hora a tarefa nao entra na fila de pegar: fica na lista de baixo.
  const paraPegar = faixa("para_pegar").filter((i) => i.liberada);
  const aindaNao = faixa("para_pegar").filter((i) => !i.liberada);

  async function sair() {
    await supabase.auth.signOut();
    navigate({ to: "/auth" });
  }

  return (
    <main className="min-h-screen bg-background p-3">
      {/* Cabeçalho enxuto: o nome da loja e a instrução na MESMA linha. O que
          importa na tela é a fila, não o título. */}
      <header className="mb-2 flex flex-wrap items-baseline justify-between gap-x-3">
        <h1 className="font-display text-lg font-semibold">{fila.data?.loja ?? "Tablet da loja"}</h1>
        <p className="text-xs text-muted-foreground">Toque na tarefa e confirme com o seu PIN.</p>
        <div className="relative flex items-center gap-2">
          {/* 48px de altura: o dedo, às vezes molhado, continua acertando. */}
          <button
            onClick={() => setMenuAberto((v) => !v)}
            aria-label="Menu"
            className="min-h-[48px] rounded-lg border border-border px-4 text-xl"
          >
            ☰
          </button>
          <button onClick={sair} className="min-h-[48px] rounded-lg border border-border px-4 text-sm">
            Sair
          </button>

          {/* O menu cresce quando a funcionalidade existir: nada de item
              desativado nem "em breve". */}
          {menuAberto && (
            <>
              <div className="fixed inset-0 z-20" onClick={() => setMenuAberto(false)} />
              <ul className="absolute right-0 top-full z-30 mt-1 w-56 overflow-hidden rounded-xl border border-border bg-card shadow-lg">
                <li>
                  <button
                    onClick={() => {
                      setMenuAberto(false);
                      abrirPedido.reset();
                      setDoMenu("mural");
                    }}
                    className="min-h-[48px] w-full px-4 text-left text-lg"
                  >
                    Mural
                  </button>
                </li>
                <li>
                  <button
                    onClick={() => {
                      setMenuAberto(false);
                      abrirPedido.reset();
                      setDoMenu("pedido");
                    }}
                    className="min-h-[48px] w-full px-4 text-left text-lg"
                  >
                    Solicitações
                  </button>
                </li>
              </ul>
            </>
          )}
        </div>
      </header>

      {recado && (
        <p className="mb-3 rounded-lg border border-sucesso bg-card p-3 text-lg font-medium text-sucesso">{recado}</p>
      )}
      {/* O navegador nao deixa tocar som sem um toque na tela. Enquanto isso,
          o aviso de tarefa nova e so o destaque do cartao. */}
      {fila.data?.som?.ligado && somPreso && (
        <button
          onClick={() => void liberarSom().then((ok) => setSomPreso(!ok))}
          className="mb-3 rounded-xl border border-border px-4 py-3 text-lg"
        >
          🔔 Ativar som de tarefa nova
        </button>
      )}

      {fila.isError && <p className="mb-3 text-destructive">{(fila.error as Error).message}</p>}
      {/* A faixa do topo continua para o aviso geral, mas enquanto a modal do
          PIN estiver aberta o erro aparece LA DENTRO — atras dela ninguem ve. */}
      {agir.isError && !pedindoPin && (
        <p className="mb-3 text-destructive">{(agir.error as Error).message}</p>
      )}

      <div className="grid gap-4 lg:grid-cols-3">
        <Coluna
          titulo="Para pegar"
          vazio="Nada esperando."
          itens={paraPegar}
          agora={agora}
          minutosParada={minutosParada}
          novas={novas}
        >
          {/* So "Aceitar": ninguem entrega sem aceitar antes (25/09/2026). O
              botao "Ja fiz: entregar" saiu, e o banco tambem recusa. */}
          {(i) => (
            <BotaoGrande onClick={() => { setAcao({ tipo: "pegar", item: i }); setPedindoPin(true); }}>
              Aceitar
            </BotaoGrande>
          )}
        </Coluna>

        <Coluna
          titulo="Em andamento"
          vazio="Ninguém pegou nada ainda."
          itens={faixa("em_andamento")}
          agora={agora}
          minutosParada={minutosParada}
        >
          {(i) => (
            <BotaoGrande onClick={() => setAcao({ tipo: "entregar", item: i, arquivo: null, observacao: "" })}>
              Entregar
            </BotaoGrande>
          )}
        </Coluna>

        <Coluna
          titulo="Feitas hoje"
          vazio="Nada entregue ainda."
          itens={faixa("feita")}
          agora={agora}
          minutosParada={minutosParada}
        />
      </div>

      <AindaNaoLiberadas itens={aindaNao} />

      {acao?.tipo === "entregar" && !pedindoPin && (
        <Entregar
          acao={acao}
          mudar={setAcao}
          cancelar={() => setAcao(null)}
          confirmar={() => setPedindoPin(true)}
        />
      )}

      {pedido && (
        <PedidoNoTablet
          nome={pedido.nome}
          passe={pedido.passe}
          funcionarioid={pedido.funcionarioid}
          fechar={() => setPedido(null)}
          pronto={(texto) => {
            setPedido(null);
            setRecado(texto);
            setTimeout(() => setRecado(null), 6000);
          }}
        />
      )}

      {mural && (
        <MuralNoTablet
          nome={mural.nome}
          passe={mural.passe}
          funcionarioid={mural.funcionarioid}
          fechar={() => setMural(null)}
          pronto={(texto) => {
            setMural(null);
            setRecado(texto);
            setTimeout(() => setRecado(null), 6000);
          }}
        />
      )}

      {/* O PIN do menu: MESMA modal, MESMA trava, erro dentro dela. */}
      {doMenu !== null && (
        <TecladoDoPin
          titulo={doMenu === "mural" ? "Quem está lendo?" : "Quem está pedindo?"}
          ocupado={abrirPedido.isPending}
          erro={abrirPedido.isError ? (abrirPedido.error as Error).message : null}
          cancelar={() => {
            abrirPedido.reset();
            setDoMenu(null);
          }}
          enviar={(pin) => abrirPedido.mutate(pin)}
        />
      )}

      {pedindoPin && (
        <TecladoDoPin
          titulo={acao?.tipo === "pegar" ? "Quem está pegando?" : "Quem está entregando?"}
          ocupado={agir.isPending}
          erro={agir.isError ? (agir.error as Error).message : null}
          cancelar={() => {
            agir.reset();
            setPedindoPin(false);
            if (acao?.tipo === "pegar") setAcao(null);
          }}
          enviar={(pin) => agir.mutate(pin)}
        />
      )}
    </main>
  );
}

/**
 * "Ainda nao liberadas (2)" — abre e mostra cada uma com a hora.
 *
 * Elas NAO entram na fila de pegar: o botao nem existe aqui. A equipe ve o que
 * vem por ai, e quando chega a hora a tarefa entra sozinha na fila, porque a
 * fila e conferida a cada 15 segundos.
 */
function AindaNaoLiberadas({ itens }: { itens: ItemDaFila[] }) {
  const [aberta, setAberta] = useState(false);
  if (itens.length === 0) return null;

  return (
    <section className="mt-4 rounded-2xl border border-border bg-card p-3">
      <button
        onClick={() => setAberta((v) => !v)}
        className="flex w-full items-center justify-between text-lg font-semibold"
      >
        <span>
          Ainda não liberadas <span className="text-muted-foreground">({itens.length})</span>
        </span>
        <span className="text-muted-foreground">{aberta ? "▲" : "▼"}</span>
      </button>
      {aberta && (
        <ul className="mt-2 space-y-2">
          {itens.map((i) => (
            <li key={i.atribuicaoid} className="rounded-xl bg-background px-3 py-2 text-lg">
              {i.titulo} <span className="text-muted-foreground">— a partir das {hora(i.liberaas)}</span>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

function Coluna({
  titulo,
  itens,
  vazio,
  agora,
  minutosParada,
  novas = [],
  children,
}: {
  titulo: string;
  itens: ItemDaFila[];
  vazio: string;
  agora: string | null;
  minutosParada: number;
  /** Quais acabaram de chegar: destacam por alguns segundos. */
  novas?: number[];
  children?: (i: ItemDaFila) => React.ReactNode;
}) {
  return (
    <section className="rounded-2xl border border-border bg-card p-2">
      <h2 className="mb-1.5 px-1 text-base font-semibold">
        {titulo} <span className="text-muted-foreground">({itens.length})</span>
      </h2>
      {itens.length === 0 ? (
        <p className="px-1 text-xs text-muted-foreground">{vazio}</p>
      ) : (
        <ul className="space-y-2">
          {itens.map((i) => (
            <li
              key={i.atribuicaoid}
              className={
                novas.indexOf(i.atribuicaoid) >= 0
                  ? "space-y-1 rounded-xl bg-background p-2 ring-4 ring-primary"
                  : "space-y-1 rounded-xl bg-background p-2"
              }
            >
              {/* O título continua legível de pé; o resto encolheu. */}
              <p className="text-base font-medium leading-snug">{i.titulo}</p>
              <Cronometro item={i} agora={agora} minutosParada={minutosParada} />
              <QuemFez item={i} />
              <p className="text-xs text-muted-foreground">
                {i.pontos} pontos
                {!i.quempegounome && i.aberta && " · quem pegar primeiro leva"}
                {i.atrasada && " · atrasada"}
              </p>
              {i.rodizio && i.situacao === "para_pegar" && (
                <p className="text-[11px] leading-tight text-muted-foreground">
                  🔄 Rodízio ativo: quem pegou a última espera um pouco.
                </p>
              )}
              {children?.(i)}
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

/**
 * "por Teste U. às 14h37 · aguardando o gestor". Só na faixa "Feitas hoje".
 *
 * A equipe precisa ver o que já rolou no dia e quem fez — antes o cartão
 * mostrava só o título e os pontos. O nome vem da ENTREGA, então tarefa com
 * dono único também aparece com nome.
 */
function QuemFez({ item }: { item: ItemDaFila }) {
  if (item.situacao !== "feita" || !item.feitapor) return null;

  const aprovada = item.feitasituacao === "Aprovada";
  return (
    <p className="text-sm">
      por <strong>{item.feitapor}</strong>
      {item.feitaem ? ` às ${hora(item.feitaem)}` : ""}
      {" · "}
      <span className={aprovada ? "text-sucesso" : "text-muted-foreground"}>
        {aprovada ? "aprovada" : "aguardando o gestor"}
      </span>
    </p>
  );
}

/**
 * "disponível há 12 min" ou "com Maria S. há 20 min". Conta a partir da hora do
 * SERVIDOR, não de quando a tela abriu: dois tablets mostram o mesmo número.
 */
function Cronometro({
  item,
  agora,
  minutosParada,
}: {
  item: ItemDaFila;
  agora: string | null;
  minutosParada: number;
}) {
  if (item.situacao === "feita") return null;

  if (item.situacao === "em_andamento") {
    const m = minutosDesde(item.pegaem, agora);
    return (
      <p className="text-sm">
        com <strong>{item.quempegounome}</strong> {faz(m)}
      </p>
    );
  }

  const m = minutosDesde(item.disponiveldesde, agora);
  const parada = m !== null && m >= minutosParada;
  return (
    <p className={`text-sm font-medium ${parada ? "text-destructive" : "text-muted-foreground"}`}>
      {parada && "⏰ "}
      disponível {faz(m)}
    </p>
  );
}

function BotaoGrande({
  children,
  onClick,
  tom = "forte",
}: {
  children: React.ReactNode;
  onClick: () => void;
  tom?: "forte" | "claro";
}) {
  return (
    <button
      onClick={onClick}
      // O cartão encolheu, o botão NÃO: 48px de altura e largura cheia. O
      // tablet é usado com o dedo, às vezes com a mão molhada.
      className={`min-h-[48px] w-full rounded-xl px-4 text-lg font-medium ${
        tom === "forte" ? "bg-primary text-primary-foreground" : "border border-border"
      }`}
    >
      {children}
    </button>
  );
}

function Entregar({
  acao,
  mudar,
  cancelar,
  confirmar,
}: {
  acao: Extract<Acao, { tipo: "entregar" }>;
  mudar: (a: Acao) => void;
  cancelar: () => void;
  confirmar: () => void;
}) {
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4">
      <div className="w-full max-w-md space-y-3 rounded-2xl bg-card p-5">
        <p className="text-xl font-semibold">{acao.item.titulo}</p>
        <label className="block text-sm">
          Foto da entrega
          <input
            type="file"
            accept="image/*"
            capture="environment"
            onChange={(e) => mudar({ ...acao, arquivo: e.target.files?.[0] ?? null })}
            className="mt-1 w-full rounded-lg border border-border p-2 text-sm"
          />
        </label>
        {acao.arquivo && <p className="text-sm text-sucesso">Foto escolhida: {acao.arquivo.name}</p>}
        <label className="block text-sm">
          Observação (opcional)
          <textarea
            value={acao.observacao}
            onChange={(e) => mudar({ ...acao, observacao: e.target.value })}
            rows={2}
            className="mt-1 w-full rounded-lg border border-border p-2 text-sm"
          />
        </label>
        <p className="text-xs text-muted-foreground">
          A entrega vai para o gestor conferir. Quem aprova é ele — o tablet não aprova nada.
        </p>
        <div className="flex gap-2">
          <BotaoGrande onClick={confirmar}>Enviar</BotaoGrande>
          <BotaoGrande tom="claro" onClick={cancelar}>
            Cancelar
          </BotaoGrande>
        </div>
      </div>
    </div>
  );
}

/** Teclado do PIN: o número digitado NUNCA aparece, só as bolinhas. */
function TecladoDoPin({
  titulo,
  cancelar,
  enviar,
  ocupado,
  erro,
}: {
  titulo: string;
  cancelar: () => void;
  enviar: (pin: string) => void;
  ocupado: boolean;
  /** O motivo da recusa. Aparece DENTRO da modal: atrás dela ninguém vê. */
  erro: string | null;
}) {
  const [pin, setPin] = useState("");

  // Deu erro: apaga os pontinhos e deixa pronto para digitar de novo. A modal
  // continua aberta — só fecha quando dá certo ou em Cancelar.
  useEffect(() => {
    if (erro) setPin("");
  }, [erro]);

  function tocar(d: string) {
    if (ocupado) return;
    const novo = (pin + d).slice(0, 6);
    setPin(novo);
    if (novo.length === 6) {
      enviar(novo);
      setPin("");
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/80 p-4">
      <div className="w-full max-w-xs space-y-4 rounded-2xl bg-card p-5 text-center">
        <p className="text-xl font-semibold">{titulo}</p>

        {/* Espaço RESERVADO: a modal não pula de tamanho quando o texto
            aparece. min-h cabe duas linhas. */}
        <p className="flex min-h-[2.75rem] items-center justify-center text-sm font-medium text-destructive">
          {erro ?? ""}
        </p>

        <div className="flex justify-center gap-2">
          {[0, 1, 2, 3, 4, 5].map((i) => (
            <span
              key={i}
              className={`h-4 w-4 rounded-full border border-border ${i < pin.length ? "bg-primary" : ""}`}
            />
          ))}
        </div>
        <div className="grid grid-cols-3 gap-2">
          {["1", "2", "3", "4", "5", "6", "7", "8", "9"].map((d) => (
            <button key={d} onClick={() => tocar(d)} className="rounded-xl border border-border py-4 text-2xl">
              {d}
            </button>
          ))}
          <button onClick={() => setPin("")} className="rounded-xl border border-border py-4 text-sm">
            Apagar
          </button>
          <button onClick={() => tocar("0")} className="rounded-xl border border-border py-4 text-2xl">
            0
          </button>
          <button onClick={cancelar} className="rounded-xl border border-border py-4 text-sm">
            Cancelar
          </button>
        </div>
        {ocupado && <p className="text-sm text-muted-foreground">Confirmando...</p>}
      </div>
    </div>
  );
}
