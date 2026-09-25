// Etapa 1.12, parte B2 — o MURAL no tablet da loja.
//
// O caminho: menu → Mural → PIN (a MESMA modal e a mesma trava do pegar
// tarefa) → esta tela → ler e dar ciência.
//
// O TABLET É DE TODO MUNDO, e isso manda no que aparece aqui:
//   - só os comunicados DELA que ainda esperam ciência;
//   - nada de histórico, nada de lista de quem já leu, nada dos colegas;
//   - a tela volta sozinha em 90 segundos sem toque, e o que estava aberto
//     some com ela.
import { useEffect, useRef, useState } from "react";
import { useMutation, useQuery } from "@tanstack/react-query";
import { darCienciaNoTablet, muralDoTablet, type ComunicadoDoMural } from "@/servidor/tablet";

/** O tablet é de todo mundo: sem toque, a tela volta sozinha. */
export const SEGUNDOS_SEM_TOQUE = 90;

export function MuralNoTablet({
  nome,
  passe,
  funcionarioid,
  fechar,
  pronto,
}: {
  nome: string;
  passe: string;
  funcionarioid: number;
  fechar: () => void;
  pronto: (recado: string) => void;
}) {
  const [aberto, setAberto] = useState<number | null>(null);

  const mural = useQuery({
    queryKey: ["mural-tablet", funcionarioid],
    // Nunca reaproveitado: é conteúdo de uma pessoa, num aparelho de todos.
    staleTime: 0,
    gcTime: 0,
    queryFn: () => muralDoTablet({ data: { passe, funcionarioid } }),
  });

  // Dois toques rápidos: trava síncrona, como no pedido. O banco também
  // segura (dar ciência duas vezes não paga duas vezes), mas a pessoa não
  // pode ver a tela piscar duas respostas.
  const dando = useRef(false);
  const ciencia = useMutation({
    mutationFn: (assinaturaid: number) =>
      darCienciaNoTablet({ data: { passe, funcionarioid, assinaturaid } }),
    onSettled: () => {
      dando.current = false;
    },
    onSuccess: async () => {
      const r = await mural.refetch();
      if ((r.data ?? []).length === 0) pronto("Tudo lido. Obrigado!");
      else setAberto(null);
    },
  });

  function darCiencia(assinaturaid: number) {
    if (dando.current) return;
    dando.current = true;
    ciencia.mutate(assinaturaid);
  }

  // Volta sozinha depois de 90 segundos sem ninguém tocar.
  const fecharRef = useRef(fechar);
  fecharRef.current = fechar;
  const [ultimoToque, setUltimoToque] = useState(() => Date.now());
  useEffect(() => {
    const t = window.setInterval(() => {
      if (Date.now() - ultimoToque > SEGUNDOS_SEM_TOQUE * 1000) fecharRef.current();
    }, 5000);
    return () => window.clearInterval(t);
  }, [ultimoToque]);

  const lista = mural.data ?? [];
  const oAberto = lista.find((c) => c.assinaturaid === aberto) ?? null;

  return (
    <div
      className="fixed inset-0 z-40 overflow-y-auto bg-background p-4"
      onPointerDown={() => setUltimoToque(Date.now())}
    >
      <div className="mx-auto max-w-2xl space-y-4">
        <div className="flex items-baseline justify-between gap-3">
          <h2 className="text-2xl font-semibold">Mural</h2>
          {/* Discreto, mas visível: ninguém dá ciência no nome errado. */}
          <p className="text-sm text-muted-foreground">Mural de {nome}</p>
        </div>

        {mural.isLoading && <p className="text-lg text-muted-foreground">Abrindo...</p>}
        {mural.isError && (
          <p className="rounded-xl bg-destructive/10 p-3 text-sm text-destructive">
            {(mural.error as Error).message}
          </p>
        )}

        {!mural.isLoading && lista.length === 0 && (
          <p className="text-lg text-muted-foreground">Nada novo para ler. Pode fechar.</p>
        )}

        {oAberto ? (
          <div className="space-y-4">
            <h3 className="text-xl font-semibold">{oAberto.titulo}</h3>
            <p className="whitespace-pre-wrap text-lg leading-relaxed">{oAberto.conteudo}</p>

            {ciencia.isError && (
              <p className="rounded-xl bg-destructive/10 p-3 text-sm text-destructive">
                {(ciencia.error as Error).message}
              </p>
            )}

            <div className="flex gap-3">
              <button
                onClick={() => setAberto(null)}
                className="min-h-[48px] flex-1 rounded-xl border border-border px-4 text-lg"
              >
                Voltar
              </button>
              <button
                onClick={() => darCiencia(oAberto.assinaturaid)}
                disabled={ciencia.isPending}
                className="min-h-[48px] flex-1 rounded-xl bg-primary px-4 text-lg font-medium text-primary-foreground disabled:opacity-60"
              >
                {ciencia.isPending ? "Registrando..." : "Li e entendi"}
              </button>
            </div>
          </div>
        ) : (
          <>
            <ul className="space-y-2">
              {lista.map((c) => (
                <li key={c.assinaturaid}>
                  <button
                    onClick={() => setAberto(c.assinaturaid)}
                    className="min-h-[64px] w-full rounded-xl border border-border px-4 py-3 text-left"
                  >
                    <span className="block text-lg font-medium">{c.titulo}</span>
                    {c.pontos > 0 && (
                      <span className="block text-sm text-muted-foreground">
                        +{c.pontos} pontos ao dar ciência
                      </span>
                    )}
                  </button>
                </li>
              ))}
            </ul>

            <button
              onClick={fechar}
              className="min-h-[48px] w-full rounded-xl border border-border px-4 text-lg"
            >
              Fechar
            </button>
          </>
        )}
      </div>
    </div>
  );
}
