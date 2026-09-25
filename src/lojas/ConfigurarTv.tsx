// "Configurar TV": o gestor escolhe o que cada TV da loja mostra.
//
// A configuração é POR LOJA e fica no banco, então a TV reflete a mudança na
// atualização seguinte (até 30 segundos), sem ninguém tocar nela.
//
// Se ele desmarcar todas as colunas, a TV volta ao conjunto padrão — uma TV
// apagada no salão é pior do que uma TV mostrando o básico. Quem garante isso
// é o banco (`tv_blocos_da_loja`), não esta janela.
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";

export type BlocosDaTv = Record<string, boolean>;

/** O que a TV mostrava antes de existir esta janela. */
export const PADRAO: BlocosDaTv = {
  barra: true,
  meta: true,
  parafazer: true,
  emandamento: false,
  emvalidacao: true,
  atividade: false,
  podiohoje: true,
  podiomes: false,
};

const FAIXAS = [
  { chave: "barra", nome: "Barra de tarefas" },
  { chave: "meta", nome: "Meta do dia" },
] as const;

const COLUNAS = [
  { chave: "parafazer", nome: "Para fazer" },
  { chave: "emandamento", nome: "Em andamento" },
  { chave: "emvalidacao", nome: "Esperando o gestor" },
  { chave: "atividade", nome: "Atividade recente" },
  { chave: "podiohoje", nome: "Pódio de hoje" },
  { chave: "podiomes", nome: "Pódio do mês" },
] as const;

const TEMPOS = [
  { valor: 30, nome: "30 segundos" },
  { valor: 60, nome: "1 minuto" },
  { valor: 120, nome: "2 minutos" },
] as const;

export function ConfigurarTv({
  lojaid,
  nome,
  blocos,
  segundos,
  valores,
  fechar,
}: {
  lojaid: number;
  nome: string;
  blocos: BlocosDaTv | null;
  segundos: number;
  valores: boolean;
  fechar: () => void;
}) {
  const qc = useQueryClient();
  const [marcados, setMarcados] = useState<BlocosDaTv>({ ...PADRAO, ...(blocos ?? {}) });
  const [tempo, setTempo] = useState(segundos);
  const [emReais, setEmReais] = useState(valores);

  const salvar = useMutation({
    mutationFn: async () => {
      const { error } = await supabase.rpc("salvar_tv_da_loja", {
        p_lojaid: lojaid,
        p_blocos: marcados,
        p_segundos: tempo,
        p_valores: emReais,
      });
      if (error) throw error;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["lojas"] });
      fechar();
    },
  });

  const quantasColunas = COLUNAS.filter((c) => marcados[c.chave]).length;
  const telas = quantasColunas <= 3 ? 1 : Math.ceil(quantasColunas / 3);

  function alternar(chave: string) {
    setMarcados((m) => ({ ...m, [chave]: !m[chave] }));
  }

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/50 p-0 sm:items-center sm:p-4">
      <div className="max-h-[92vh] w-full max-w-lg overflow-y-auto rounded-t-2xl bg-card p-5 sm:rounded-2xl">
        <h2 className="font-display text-xl font-semibold">TV da {nome}</h2>
        <p className="mt-1 text-sm text-muted-foreground">
          Marque o que esta TV mostra. A TV muda sozinha em até 30 segundos.
        </p>

        <fieldset className="mt-4">
          <legend className="text-sm font-semibold">Faixas</legend>
          <p className="text-xs text-muted-foreground">Ficam no alto, e aparecem em todas as telas.</p>
          {FAIXAS.map((f) => (
            <label key={f.chave} className="mt-2 flex items-center gap-2 text-sm">
              <input type="checkbox" checked={!!marcados[f.chave]} onChange={() => alternar(f.chave)} />
              {f.nome}
            </label>
          ))}
          {/* Só faz sentido com a meta marcada: sem ela, não há valor nenhum. */}
          <label
            className={`mt-2 flex items-center gap-2 pl-6 text-sm ${
              marcados.meta ? "" : "text-muted-foreground opacity-60"
            }`}
          >
            <input
              type="checkbox"
              checked={emReais}
              disabled={!marcados.meta}
              onChange={(e) => setEmReais(e.target.checked)}
            />
            Mostrar valores em R$ da meta (desligado: só a porcentagem)
          </label>
        </fieldset>

        <fieldset className="mt-5">
          <legend className="text-sm font-semibold">Colunas</legend>
          <p className="text-xs text-muted-foreground">No máximo 3 por tela.</p>
          {COLUNAS.map((c) => (
            <label key={c.chave} className="mt-2 flex items-center gap-2 text-sm">
              <input type="checkbox" checked={!!marcados[c.chave]} onChange={() => alternar(c.chave)} />
              {c.nome}
            </label>
          ))}
          <p className="mt-2 text-xs text-muted-foreground">
            {quantasColunas === 0
              ? "Sem nenhuma marcada, a TV volta ao conjunto padrão — ela nunca fica em branco."
              : telas === 1
                ? "Cabem numa tela só: a TV não vai trocar de tela."
                : `${quantasColunas} colunas em ${telas} telas, que se alternam sozinhas.`}
          </p>
        </fieldset>

        {telas > 1 && (
          <label className="mt-5 block text-sm">
            <span className="font-semibold">Trocar de tela a cada</span>
            <select
              value={tempo}
              onChange={(e) => setTempo(Number(e.target.value))}
              className="mt-1 w-full rounded-lg border border-border bg-background p-2 text-sm"
            >
              {TEMPOS.map((t) => (
                <option key={t.valor} value={t.valor}>
                  {t.nome}
                </option>
              ))}
            </select>
          </label>
        )}

        {salvar.isError && (
          <p className="mt-3 text-sm text-destructive">{(salvar.error as Error).message}</p>
        )}

        <div className="mt-5 flex gap-2">
          <button onClick={fechar} className="flex-1 rounded-lg border border-border px-4 py-2 text-sm">
            Cancelar
          </button>
          <button
            onClick={() => salvar.mutate()}
            disabled={salvar.isPending}
            className="flex-1 rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground disabled:opacity-60"
          >
            {salvar.isPending ? "Salvando..." : "Salvar"}
          </button>
        </div>
      </div>
    </div>
  );
}
