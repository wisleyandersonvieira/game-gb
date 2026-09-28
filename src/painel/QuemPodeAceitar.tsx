// Tablet: "quem pode aceitar" esta tarefa (29/09/2026, pedido do Wisley).
//
// Um ícone discreto no canto do cartão abre uma janela SÓ PARA VER: quem pode
// pegar, e quem está esperando o rodízio ("Bruno L. — pode pegar em 8 min"),
// que é o que a pessoa foi buscar ali quando não consegue pegar.
//
// A lista NÃO é calculada aqui: vem pronta na mesma resposta da fila
// (visao_fila → quem_pode_aceitar), que pergunta à MESMA regra que o servidor
// usa para permitir o aceite (quem_pode_pegar e rodizio_espera). Se a regra
// mudar, a janela muda junto. Nenhuma pergunta a mais ao banco por cartão.
//
// O tablet é de todo mundo, à vista de cliente: só primeiro nome e inicial, e
// a janela fecha sozinha em cerca de 30 segundos sem toque.
import { Users, X } from "lucide-react";
import { useEffect, useRef, useState } from "react";

export const SEGUNDOS_SEM_TOQUE_JANELA = 30;

export type QuemPode = {
  /** Missão da equipe: qualquer pessoa da loja pode pegar. */
  todos: boolean;
  /** Em ordem alfabética. Vazio na missão da equipe. */
  pessoas: { nome: string; esperamin: number }[];
  /** Quem o rodízio está segurando, com os minutos que faltam. */
  esperando: { nome: string; esperamin: number }[];
};

export const textoEspera = (min: number) => `pode pegar em ${min} min`;

/** O ícone do cartão. A área de toque tem 44 px, o desenho é pequeno. */
export function BotaoQuemPode({ titulo, podem }: { titulo: string; podem: QuemPode }) {
  const [aberta, setAberta] = useState(false);
  return (
    <>
      <button
        type="button"
        aria-label="Quem pode aceitar esta tarefa"
        title="Quem pode aceitar"
        onClick={() => setAberta(true)}
        className="absolute right-0 top-0 flex h-11 w-11 items-center justify-center rounded-xl text-muted-foreground active:bg-muted"
      >
        <Users className="h-4 w-4" aria-hidden />
      </button>
      {aberta && <JanelaQuemPode titulo={titulo} podem={podem} fechar={() => setAberta(false)} />}
    </>
  );
}

export function JanelaQuemPode({ titulo, podem, fechar }: { titulo: string; podem: QuemPode; fechar: () => void }) {
  // Fecha sozinha depois de ~30 s sem ninguém tocar (como as outras telas).
  const fecharRef = useRef(fechar);
  fecharRef.current = fechar;
  const [ultimoToque, setUltimoToque] = useState(() => Date.now());
  useEffect(() => {
    const t = window.setInterval(() => {
      if (Date.now() - ultimoToque > SEGUNDOS_SEM_TOQUE_JANELA * 1000) fecharRef.current();
    }, 1000);
    return () => window.clearInterval(t);
  }, [ultimoToque]);

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-label={`Quem pode aceitar: ${titulo}`}
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4"
      // Tocar fora fecha.
      onClick={fechar}
      onPointerDown={() => setUltimoToque(Date.now())}
    >
      <div className="w-full max-w-sm space-y-3 rounded-2xl bg-card p-5" onClick={(e) => e.stopPropagation()}>
        <div>
          <p className="text-sm text-muted-foreground">Quem pode aceitar</p>
          <p className="text-lg font-semibold leading-snug">{titulo}</p>
        </div>

        {podem.todos ? (
          <p className="text-base">Qualquer pessoa da loja.</p>
        ) : podem.pessoas.length === 0 ? (
          <p className="text-base text-muted-foreground">Ninguém que trabalha hoje pode pegar esta tarefa.</p>
        ) : (
          <ul className="space-y-1.5">
            {podem.pessoas.map((p) => (
              <li key={p.nome} className="text-base">
                {p.nome}
                {p.esperamin > 0 && <span className="text-muted-foreground"> — {textoEspera(p.esperamin)}</span>}
              </li>
            ))}
          </ul>
        )}

        {/* Na missão da equipe a lista não aparece; quem espera o rodízio, sim. */}
        {podem.todos && podem.esperando.length > 0 && (
          <div className="space-y-1 rounded-xl bg-muted/50 p-3">
            <p className="text-sm font-medium">Esperando o rodízio</p>
            {podem.esperando.map((p) => (
              <p key={p.nome} className="text-base">
                {p.nome} <span className="text-muted-foreground">— {textoEspera(p.esperamin)}</span>
              </p>
            ))}
          </div>
        )}

        <button
          type="button"
          onClick={fechar}
          className="flex h-11 w-full items-center justify-center gap-2 rounded-xl border border-border text-base"
        >
          <X className="h-4 w-4" aria-hidden /> Fechar
        </button>
      </div>
    </div>
  );
}
