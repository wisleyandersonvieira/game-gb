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
import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { meuAcesso } from "@/integrations/supabase/destino";
import {
  autorizacaoDeFoto,
  entregarNoTablet,
  filaDoTablet,
  pegarNoTablet,
  type ItemDaFila,
} from "@/servidor/tablet";
import { faz, minutosDesde, useRelogio } from "@/ui/relogio";

export const Route = createFileRoute("/tablet")({
  ssr: false,
  beforeLoad: async () => {
    // getSession() é local: não gasta uma ida ao servidor só para saber se
    // existe token. Quem confere de verdade é meuAcesso(), no banco.
    const { data } = await supabase.auth.getSession();
    if (!data.session) throw redirect({ to: "/auth" });
    const acesso = await meuAcesso();
    if (acesso.tipo !== "loja") throw redirect({ to: "/meu-acesso" });
  },
  component: Tablet,
});

const SEGUNDOS = 15;

function hora(iso: string | null) {
  if (!iso) return "";
  return new Date(iso).toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" });
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
      if (acao.arquivo) {
        const a = await autorizacaoDeFoto();
        const { error } = await supabase.storage.from("entregas").uploadToSignedUrl(a.caminho, a.token, acao.arquivo);
        if (error) throw new Error("A foto não subiu. Tente de novo.");
        caminho = a.caminho;
      }
      return await entregarNoTablet({
        data: { pin, atribuicaoid: acao.item.atribuicaoid, caminho, observacao: acao.observacao || null },
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

  // O relógio anda sozinho aqui; a fila só conversa com o banco a cada 15 s.
  useRelogio();
  const itens = fila.data?.itens ?? [];
  const agora = itens[0]?.agora ?? null;
  const minutosParada = fila.data?.minutosParada ?? 30;
  const faixa = (s: ItemDaFila["situacao"]) => itens.filter((i) => i.situacao === s);

  async function sair() {
    await supabase.auth.signOut();
    navigate({ to: "/auth" });
  }

  return (
    <main className="min-h-screen bg-background p-4">
      <header className="mb-4 flex items-center justify-between">
        <div>
          <h1 className="font-display text-2xl font-semibold">{fila.data?.loja ?? "Tablet da loja"}</h1>
          <p className="text-xs text-muted-foreground">
            Toque na tarefa e confirme com o seu PIN. A lista atualiza sozinha.
          </p>
        </div>
        <button onClick={sair} className="rounded-lg border border-border px-3 py-2 text-sm">
          Sair
        </button>
      </header>

      {recado && (
        <p className="mb-3 rounded-lg border border-sucesso bg-card p-3 text-lg font-medium text-sucesso">{recado}</p>
      )}
      {fila.isError && <p className="mb-3 text-destructive">{(fila.error as Error).message}</p>}
      {agir.isError && <p className="mb-3 text-destructive">{(agir.error as Error).message}</p>}

      <div className="grid gap-4 lg:grid-cols-3">
        <Coluna
          titulo="Para pegar"
          vazio="Nada esperando."
          itens={faixa("para_pegar")}
          agora={agora}
          minutosParada={minutosParada}
        >
          {(i) => (
            <>
              <BotaoGrande onClick={() => { setAcao({ tipo: "pegar", item: i }); setPedindoPin(true); }}>
                Pegar
              </BotaoGrande>
              <BotaoGrande
                tom="claro"
                onClick={() => setAcao({ tipo: "entregar", item: i, arquivo: null, observacao: "" })}
              >
                Já fiz: entregar
              </BotaoGrande>
            </>
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

      {acao?.tipo === "entregar" && !pedindoPin && (
        <Entregar
          acao={acao}
          mudar={setAcao}
          cancelar={() => setAcao(null)}
          confirmar={() => setPedindoPin(true)}
        />
      )}

      {pedindoPin && (
        <TecladoDoPin
          titulo={acao?.tipo === "pegar" ? "Quem está pegando?" : "Quem está entregando?"}
          ocupado={agir.isPending}
          cancelar={() => { setPedindoPin(false); if (acao?.tipo === "pegar") setAcao(null); }}
          enviar={(pin) => agir.mutate(pin)}
        />
      )}
    </main>
  );
}

function Coluna({
  titulo,
  itens,
  vazio,
  agora,
  minutosParada,
  children,
}: {
  titulo: string;
  itens: ItemDaFila[];
  vazio: string;
  agora: string | null;
  minutosParada: number;
  children?: (i: ItemDaFila) => React.ReactNode;
}) {
  return (
    <section className="rounded-2xl border border-border bg-card p-3">
      <h2 className="mb-2 text-lg font-semibold">
        {titulo} <span className="text-muted-foreground">({itens.length})</span>
      </h2>
      {itens.length === 0 ? (
        <p className="text-sm text-muted-foreground">{vazio}</p>
      ) : (
        <ul className="space-y-3">
          {itens.map((i) => (
            <li key={i.atribuicaoid} className="space-y-2 rounded-xl bg-background p-3">
              <p className="text-lg font-medium">{i.titulo}</p>
              <Cronometro item={i} agora={agora} minutosParada={minutosParada} />
              <p className="text-sm text-muted-foreground">
                {i.pontos} pontos
                {!i.quempegounome && i.aberta && " · quem pegar primeiro leva"}
                {i.atrasada && " · atrasada"}
              </p>
              {i.rodizio && i.situacao === "para_pegar" && (
                <p className="text-xs text-muted-foreground">
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
      className={`w-full rounded-xl px-4 py-3 text-lg font-medium ${
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
}: {
  titulo: string;
  cancelar: () => void;
  enviar: (pin: string) => void;
  ocupado: boolean;
}) {
  const [pin, setPin] = useState("");

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
