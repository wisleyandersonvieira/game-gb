// Telegram nas telas do master: convites (link + QR, ou código do grupo),
// quem está ligado, "Desligar Telegram" e os avisos de vínculo novo.
// O código do convite só aparece aqui, na hora; o banco guarda só o hash.
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Bell, Check, Copy, Send, X } from "lucide-react";
import QRCode from "qrcode";
import { useEffect, useRef, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Botao } from "@/ui/Botao";
import { ErroTela } from "@/ui/Estados";

export const BOT_TELEGRAM = "STGameAppBot";

export type Vinculo = {
  vinculoid: number;
  tipo: "pessoa" | "master" | "grupo";
  funcionarioid: number | null;
  userid: string | null;
  lojaid: number | null;
  papelgrupo: "equipe" | "gestao" | null;
  nometelegram: string | null;
  vinculadoem: string;
};

/** Vínculos ativos da conta (pessoas, grupos e o master). */
export function useVinculosTelegram() {
  return useQuery({
    queryKey: ["telegram-vinculos"],
    refetchInterval: 30_000,
    queryFn: async () => {
      const { data, error } = await supabase
        .from("telegramvinculos")
        .select("vinculoid, tipo, funcionarioid, userid, lojaid, papelgrupo, nometelegram, vinculadoem")
        .eq("ativo", true);
      if (error) throw error;
      return (data ?? []) as Vinculo[];
    },
  });
}

export function useDesligarTelegram() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (vinculoid: number) => {
      const { error } = await supabase.rpc("desligar_telegram", { p_vinculoid: vinculoid });
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ["telegram-vinculos"] }),
  });
}

const dataHora = (iso: string) =>
  new Date(iso).toLocaleString("pt-BR", { timeZone: "America/Sao_Paulo", day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit" });

/** Ícone "ligado no Telegram" (ao lado do nome). */
export function IconeTelegram({ desde }: { desde: string }) {
  return (
    <span
      className="inline-flex items-center gap-1 rounded-md bg-azul-soft px-1.5 py-0.5 text-xs font-medium text-azul"
      title={`Telegram ligado desde ${dataHora(desde)}`}
    >
      <Send className="h-3 w-3" aria-hidden /> Telegram
    </span>
  );
}

function BotaoCopiar({ texto, rotulo }: { texto: string; rotulo: string }) {
  const [copiado, setCopiado] = useState(false);
  return (
    <Botao
      variante="secundario"
      tamanho="pequeno"
      onClick={async () => {
        try {
          await navigator.clipboard.writeText(texto);
          setCopiado(true);
          setTimeout(() => setCopiado(false), 2000);
        } catch {
          /* sem permissão para copiar: a pessoa seleciona o texto */
        }
      }}
    >
      {copiado ? <Check className="h-4 w-4" aria-hidden /> : <Copy className="h-4 w-4" aria-hidden />}
      {copiado ? "Copiado" : rotulo}
    </Botao>
  );
}

function Qr({ texto }: { texto: string }) {
  const [src, setSrc] = useState<string | null>(null);
  useEffect(() => {
    let vivo = true;
    QRCode.toDataURL(texto, { margin: 1, width: 220, errorCorrectionLevel: "M" })
      .then((u) => vivo && setSrc(u))
      .catch(() => vivo && setSrc(null));
    return () => {
      vivo = false;
    };
  }, [texto]);
  if (!src) return null;
  return <img src={src} alt="QR code do convite do Telegram" width={220} height={220} className="rounded-lg bg-white p-2" />;
}

type PropsConvite = {
  titulo: string;
  /** "link": pessoa ou master (link + QR). "grupo": comando para colar no grupo. */
  modo: "link" | "grupo";
  gerar: () => Promise<string>;
  aoFechar: () => void;
};

/** Janela do convite. Gera um código novo ao abrir (o anterior deixa de valer). */
export function JanelaConvite({ titulo, modo, gerar, aoFechar }: PropsConvite) {
  const [codigo, setCodigo] = useState<string | null>(null);
  const [erro, setErro] = useState<unknown>(null);

  // Gera uma vez só por abertura (dois pedidos juntos cancelariam um ao outro).
  const pedido = useRef<Promise<string> | null>(null);
  useEffect(() => {
    let vivo = true;
    pedido.current ??= gerar();
    pedido.current.then((c) => vivo && setCodigo(c)).catch((e) => vivo && setErro(e));
    return () => {
      vivo = false;
    };
  }, [gerar]);

  useEffect(() => {
    const tecla = (e: KeyboardEvent) => e.key === "Escape" && aoFechar();
    window.addEventListener("keydown", tecla);
    return () => window.removeEventListener("keydown", tecla);
  }, [aoFechar]);

  const link = codigo ? `https://t.me/${BOT_TELEGRAM}?start=${codigo}` : "";
  const comando = codigo ? `/vincular@${BOT_TELEGRAM} ${codigo}` : "";

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/50 p-0 sm:items-center sm:p-4" onClick={aoFechar}>
      <div
        role="dialog"
        aria-modal="true"
        aria-label={titulo}
        className="max-h-[92vh] w-full max-w-md space-y-4 overflow-y-auto rounded-t-2xl border border-border bg-card p-5 shadow-card sm:rounded-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-start justify-between gap-3">
          <h2 className="font-display text-lg font-semibold">{titulo}</h2>
          <Botao variante="fantasma" tamanho="icone" onClick={aoFechar} aria-label="Fechar">
            <X className="h-5 w-5" aria-hidden />
          </Botao>
        </div>

        {!!erro && <ErroTela erro={erro} />}
        {!codigo && !erro && <p className="text-sm text-muted-foreground">Gerando convite...</p>}

        {codigo && modo === "link" && (
          <>
            <ol className="list-decimal space-y-1 pl-5 text-sm">
              <li>Abra a câmera do celular e aponte para o QR code, ou envie o link abaixo.</li>
              <li>O Telegram abre o @{BOT_TELEGRAM}. Toque em <strong>Iniciar</strong>.</li>
              <li>Pronto: o bot confirma e mostra o menu.</li>
            </ol>
            <div className="flex justify-center">
              <Qr texto={link} />
            </div>
            <p className="break-all rounded-lg border border-border bg-background px-3 py-2 font-mono text-xs">{link}</p>
            <BotaoCopiar texto={link} rotulo="Copiar link" />
          </>
        )}

        {codigo && modo === "grupo" && (
          <>
            <ol className="list-decimal space-y-1 pl-5 text-sm">
              <li>No Telegram, abra o grupo e adicione o @{BOT_TELEGRAM} como membro (não precisa ser administrador).</li>
              <li>Copie o comando abaixo e envie no grupo.</li>
              <li>O bot responde "Grupo ligado".</li>
            </ol>
            <p className="break-all rounded-lg border border-border bg-background px-3 py-2 font-mono text-xs">{comando}</p>
            <BotaoCopiar texto={comando} rotulo="Copiar comando" />
          </>
        )}

        {codigo && (
          <p className="text-xs text-muted-foreground">
            Vale por 48 horas e só uma vez. Gerar outro convite cancela este. Não poste o código em lugar público.
          </p>
        )}
      </div>
    </div>
  );
}

/** Avisos do sistema ainda não lidos (ex.: "Bruna ligou o Telegram agora"). */
export function AvisosDoSistema() {
  const qc = useQueryClient();
  const avisos = useQuery({
    queryKey: ["avisos-sistema"],
    refetchInterval: 60_000,
    queryFn: async () => {
      const { data, error } = await supabase
        .from("avisossistema")
        .select("avisoid, texto, criadoem")
        .is("lidoem", null)
        .order("criadoem", { ascending: false })
        .limit(10);
      if (error) throw error;
      return data ?? [];
    },
  });
  const lido = useMutation({
    mutationFn: async (avisoid: number) => {
      const { error } = await supabase.rpc("marcar_aviso_lido", { p_avisoid: avisoid });
      if (error) throw error;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["avisos-sistema"] });
      qc.invalidateQueries({ queryKey: ["telegram-vinculos"] });
    },
  });

  const lista = avisos.data ?? [];
  if (lista.length === 0) return null;
  return (
    <ul className="space-y-2" aria-label="Novidades">
      {lista.map((a) => (
        <li key={a.avisoid} className="flex items-start gap-2 rounded-lg border border-border bg-card px-3 py-2 text-sm">
          <Bell className="mt-0.5 h-4 w-4 shrink-0 text-azul" aria-hidden />
          <span className="flex-1">
            {a.texto} <span className="text-xs text-muted-foreground">({dataHora(a.criadoem)})</span>
          </span>
          <button
            onClick={() => lido.mutate(a.avisoid)}
            disabled={lido.isPending}
            className="shrink-0 rounded-md px-2 py-0.5 text-xs text-muted-foreground hover:bg-muted hover:text-foreground"
          >
            Marcar como lido
          </button>
        </li>
      ))}
    </ul>
  );
}

const PAPEIS = [
  { papel: "equipe", nome: "Grupo da equipe", texto: "Avisos para todos: meta batida e, depois, as rotinas do dia." },
  { papel: "gestao", nome: "Grupo de gestão", texto: "Entregas com foto para aprovar ou recusar, /pendencias, /lancar e /status_meta." },
] as const;

/** Tela Lojas: os dois grupos do Telegram de cada loja. */
export function GruposTelegram({ lojas, suspensa }: { lojas: { lojaid: number; nome: string }[]; suspensa: boolean }) {
  const vinculos = useVinculosTelegram();
  const desligar = useDesligarTelegram();
  const [convite, setConvite] = useState<{ lojaid: number; papel: "equipe" | "gestao"; titulo: string } | null>(null);
  const grupo = (lojaid: number, papel: string) =>
    (vinculos.data ?? []).find((v) => v.tipo === "grupo" && v.lojaid === lojaid && v.papelgrupo === papel);

  return (
    <section className="space-y-3">
      <div>
        <h2 className="text-sm font-semibold">Grupos do Telegram</h2>
        <p className="text-xs text-muted-foreground">
          Cada loja pode ter um grupo da equipe e um de gestão. No grupo de gestão, só você e quem estiver marcado como
          validador da loja (tela Equipe) conseguem aprovar ou recusar.
        </p>
      </div>
      {vinculos.isError && <ErroTela erro={vinculos.error} />}
      {desligar.isError && <ErroTela erro={desligar.error} />}
      <ul className="space-y-2">
        {lojas.map((l) => (
          <li key={l.lojaid} className="space-y-2 rounded-lg border border-border bg-card px-4 py-3">
            <p className="font-medium">{l.nome}</p>
            {PAPEIS.map((p) => {
              const g = grupo(l.lojaid, p.papel);
              return (
                <div key={p.papel} className="flex flex-wrap items-center justify-between gap-2 text-sm">
                  <div className="min-w-0">
                    <p>
                      {p.nome}:{" "}
                      {g ? (
                        <span className="font-medium text-sucesso">ligado{g.nometelegram ? ` (${g.nometelegram})` : ""}</span>
                      ) : (
                        <span className="text-muted-foreground">não ligado</span>
                      )}
                    </p>
                    <p className="text-xs text-muted-foreground">{p.texto}</p>
                  </div>
                  {g ? (
                    <Botao
                      variante="secundario"
                      tamanho="pequeno"
                      disabled={desligar.isPending || suspensa}
                      onClick={() => {
                        if (confirm(`Desligar o ${p.nome.toLowerCase()} de ${l.nome}? O bot para de mandar avisos para ele.`)) {
                          desligar.mutate(g.vinculoid);
                        }
                      }}
                    >
                      Desligar
                    </Botao>
                  ) : (
                    <Botao
                      variante="secundario"
                      tamanho="pequeno"
                      disabled={suspensa}
                      onClick={() => setConvite({ lojaid: l.lojaid, papel: p.papel, titulo: `${p.nome}: ${l.nome}` })}
                    >
                      Ligar grupo
                    </Botao>
                  )}
                </div>
              );
            })}
          </li>
        ))}
      </ul>
      {convite && (
        <JanelaConvite
          titulo={convite.titulo}
          modo="grupo"
          gerar={async () => {
            const { data, error } = await supabase.rpc("criar_convite_grupo", { p_lojaid: convite.lojaid, p_papel: convite.papel });
            if (error) throw error;
            return data as string;
          }}
          aoFechar={() => setConvite(null)}
        />
      )}
    </section>
  );
}

/** Meu perfil: o Telegram do próprio master (para receber os avisos). */
export function MeuTelegram() {
  const vinculos = useVinculosTelegram();
  const desligar = useDesligarTelegram();
  const [abrir, setAbrir] = useState(false);
  const [uid, setUid] = useState<string | null>(null);
  useEffect(() => {
    supabase.auth.getUser().then(({ data }) => setUid(data.user?.id ?? null));
  }, []);
  const meu = (vinculos.data ?? []).find((v) => v.tipo === "master" && v.userid === uid);

  return (
    <section className="space-y-3 rounded-xl border border-border bg-card p-4">
      <h2 className="text-sm font-medium">Meu Telegram</h2>
      {meu ? (
        <>
          <p className="text-sm">
            <IconeTelegram desde={meu.vinculadoem} /> Ligado{meu.nometelegram ? ` como ${meu.nometelegram}` : ""}. Você recebe
            no Telegram os avisos da empresa (ex.: quem ligou o Telegram).
          </p>
          <Botao
            variante="secundario"
            disabled={desligar.isPending}
            onClick={() => confirm("Desligar o seu Telegram do STGame?") && desligar.mutate(meu.vinculoid)}
          >
            Desligar Telegram
          </Botao>
        </>
      ) : (
        <>
          <p className="text-sm text-muted-foreground">
            Ligue o seu Telegram para receber os avisos. Para aprovar entregas pelo Telegram, entre também no grupo de gestão
            da loja.
          </p>
          <Botao onClick={() => setAbrir(true)} disabled={!uid}>
            Ligar meu Telegram
          </Botao>
        </>
      )}
      {desligar.isError && <ErroTela erro={desligar.error} />}
      {abrir && (
        <JanelaConvite
          titulo="Ligar meu Telegram"
          modo="link"
          gerar={async () => {
            const { data, error } = await supabase.rpc("criar_convite_meu_telegram");
            if (error) throw error;
            return data as string;
          }}
          aoFechar={() => setAbrir(false)}
        />
      )}
    </section>
  );
}
