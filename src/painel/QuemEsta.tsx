// Tablet: "toque no seu nome" antes do PIN (29/09/2026, pedido do Wisley).
//
// A trava de tentativas do PIN é de cada pessoa, então o tablet precisa saber
// de quem é o PIN antes de conferir. Na missão, na tarefa compartilhada e no
// menu a pessoa toca no próprio nome. A lista é a de quem trabalha hoje nesta
// loja (quem está de folga não aparece), só primeiro nome e inicial, e fecha
// sozinha depois de cerca de 30 segundos sem toque, como as outras janelas.
import { useEffect, useRef, useState } from "react";
import { SEGUNDOS_SEM_TOQUE_JANELA } from "@/painel/QuemPodeAceitar";
import type { PessoaDaEquipe } from "@/servidor/mensagensDoPin";

export function QuemEsta({
  titulo,
  pessoas,
  escolher,
  cancelar,
}: {
  titulo: string;
  pessoas: PessoaDaEquipe[];
  escolher: (p: PessoaDaEquipe) => void;
  cancelar: () => void;
}) {
  const cancelarRef = useRef(cancelar);
  cancelarRef.current = cancelar;
  const [ultimoToque, setUltimoToque] = useState(() => Date.now());
  useEffect(() => {
    const t = window.setInterval(() => {
      if (Date.now() - ultimoToque > SEGUNDOS_SEM_TOQUE_JANELA * 1000) cancelarRef.current();
    }, 1000);
    return () => window.clearInterval(t);
  }, [ultimoToque]);

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-label={titulo}
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/80 p-4"
      onPointerDown={() => setUltimoToque(Date.now())}
    >
      <div className="w-full max-w-md space-y-4 rounded-2xl bg-card p-5">
        <div className="text-center">
          <p className="text-xl font-semibold">{titulo}</p>
          <p className="text-sm text-muted-foreground">Toque no seu nome.</p>
        </div>
        {pessoas.length === 0 ? (
          <p className="text-center text-base text-muted-foreground">
            Ninguém que trabalha hoje nesta loja pode fazer isto.
          </p>
        ) : (
          <div className="grid max-h-[60vh] grid-cols-2 gap-2 overflow-y-auto">
            {pessoas.map((p) => (
              <button
                key={p.funcionarioid}
                type="button"
                onClick={() => escolher(p)}
                className="min-h-[56px] rounded-xl border border-border px-3 text-lg font-medium active:bg-muted"
              >
                {p.nome}
              </button>
            ))}
          </div>
        )}
        <button type="button" onClick={cancelar} className="min-h-[48px] w-full rounded-xl border border-border text-base">
          Cancelar
        </button>
      </div>
    </div>
  );
}
