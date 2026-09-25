// Etapa 1.12, parte B2 — abrir pedido pelo tablet da loja.
//
// O caminho: menu → Solicitações → PIN (a MESMA modal e a mesma trava do pegar
// tarefa) → esta tela → Salvar.
//
// Quem pediu e em que loja saem do SERVIDOR, a partir do PIN e do tablet
// pareado. Esta tela manda só o que a pessoa digitou.
import { useEffect, useRef, useState } from "react";
import { useMutation } from "@tanstack/react-query";
import { abrirPedidoNoTablet } from "@/servidor/tablet";

/** O tablet é de todo mundo: sem toque, a tela volta sozinha e descarta tudo. */
export const SEGUNDOS_SEM_TOQUE = 90;

const campo = "w-full rounded-xl border border-border bg-background p-3 text-lg";

export function PedidoNoTablet({
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
  const [tipo, setTipo] = useState<"Compra" | "Manutencao" | null>(null);
  const [descricao, setDescricao] = useState("");
  const [quantidade, setQuantidade] = useState("");
  const [unidade, setUnidade] = useState("");
  const [observacao, setObservacao] = useState("");

  const salvar = useMutation({
    mutationFn: async () => {
      if (!tipo) throw new Error("Escolha Compra ou Manutenção.");
      const n = Number(quantidade.replace(",", "."));
      return await abrirPedidoNoTablet({
        data: {
          passe,
          funcionarioid,
          tipo,
          descricao,
          quantidade: tipo === "Compra" ? (Number.isFinite(n) ? n : null) : null,
          unidade: tipo === "Compra" ? unidade : null,
          observacao,
        },
      });
    },
    onSuccess: () => pronto("Pedido registrado. O gestor vai ver."),
  });

  // Volta sozinha depois de 90 segundos sem ninguém tocar, descartando o que
  // estava digitado: o tablet não pode ficar aberto no nome de uma pessoa.
  const fecharRef = useRef(fechar);
  fecharRef.current = fechar;
  const [ultimoToque, setUltimoToque] = useState(() => Date.now());
  useEffect(() => {
    const t = window.setInterval(() => {
      if (Date.now() - ultimoToque > SEGUNDOS_SEM_TOQUE * 1000) fecharRef.current();
    }, 5000);
    return () => window.clearInterval(t);
  }, [ultimoToque]);

  const marcarToque = () => setUltimoToque(Date.now());

  return (
    <div
      className="fixed inset-0 z-40 overflow-y-auto bg-background p-4"
      onPointerDown={marcarToque}
      onKeyDown={marcarToque}
    >
      <div className="mx-auto max-w-2xl space-y-4">
        <div className="flex items-baseline justify-between gap-3">
          <h2 className="text-2xl font-semibold">Pedido para o gestor</h2>
          {/* Discreto, mas visível: ninguém pede no nome errado sem perceber. */}
          <p className="text-sm text-muted-foreground">Pedido de {nome}</p>
        </div>

        {!tipo ? (
          <div className="space-y-3">
            <p className="text-lg text-muted-foreground">O que você precisa?</p>
            <button
              onClick={() => setTipo("Compra")}
              className="min-h-[64px] w-full rounded-xl bg-primary px-4 text-xl font-medium text-primary-foreground"
            >
              🛒 Comprar alguma coisa
            </button>
            <button
              onClick={() => setTipo("Manutencao")}
              className="min-h-[64px] w-full rounded-xl border border-border px-4 text-xl font-medium"
            >
              🔧 Consertar alguma coisa
            </button>
          </div>
        ) : (
          <div className="space-y-3">
            <label className="block">
              <span className="text-sm text-muted-foreground">
                {tipo === "Compra" ? "O que precisa comprar" : "O que precisa de manutenção"}
              </span>
              <input
                autoFocus
                maxLength={500}
                value={descricao}
                onChange={(e) => setDescricao(e.target.value)}
                placeholder={tipo === "Compra" ? "Ex.: detergente" : "Ex.: a porta do freezer não fecha"}
                className={campo}
              />
            </label>

            {tipo === "Compra" && (
              <div className="flex gap-3">
                <label className="flex-1">
                  <span className="text-sm text-muted-foreground">Quantidade</span>
                  <input
                    inputMode="decimal"
                    value={quantidade}
                    onChange={(e) => setQuantidade(e.target.value)}
                    placeholder="2"
                    className={campo}
                  />
                </label>
                <label className="flex-1">
                  <span className="text-sm text-muted-foreground">Unidade</span>
                  <input
                    maxLength={20}
                    value={unidade}
                    onChange={(e) => setUnidade(e.target.value)}
                    placeholder="litros, caixas..."
                    className={campo}
                  />
                </label>
              </div>
            )}

            <label className="block">
              <span className="text-sm text-muted-foreground">Observação (opcional)</span>
              <textarea
                rows={2}
                maxLength={500}
                value={observacao}
                onChange={(e) => setObservacao(e.target.value)}
                className={campo}
              />
            </label>

            {salvar.isError && (
              <p className="rounded-xl bg-destructive/10 p-3 text-sm text-destructive">
                {(salvar.error as Error).message}
              </p>
            )}

            <div className="flex gap-3">
              <button
                onClick={fechar}
                className="min-h-[48px] flex-1 rounded-xl border border-border px-4 text-lg"
              >
                Cancelar
              </button>
              <button
                onClick={() => salvar.mutate()}
                disabled={salvar.isPending}
                className="min-h-[48px] flex-1 rounded-xl bg-primary px-4 text-lg font-medium text-primary-foreground disabled:opacity-60"
              >
                {salvar.isPending ? "Salvando..." : "Enviar pedido"}
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
