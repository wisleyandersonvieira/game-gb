// "Configurações": o que o tablet DESTA loja faz quando chega tarefa nova.
//
// Por que é por loja, e não da conta: uma loja de shopping com música alta e um
// quiosque silencioso não aceitam o mesmo volume. Quem regula é quem está lá,
// ouvindo — e o gestor não precisa escolher um meio-termo ruim para as duas.
//
// O volume é baixo · médio · alto, e não um número de 0 a 100: ninguém no
// balcão sabe o que "72" significa. Os três níveis vivem em somDaFila.ts,
// junto do som que eles governam.
//
// O celular da equipe não entra nisto. Nunca recebe aviso, por política.
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { NIVEIS } from "@/painel/somDaFila";

type Nivel = keyof typeof NIVEIS;

const ROTULO: Record<Nivel, string> = { baixo: "Baixo", medio: "Médio", alto: "Alto" };

/** O nível mais perto do número guardado. Conta antiga pode ter outro valor. */
export function nivelDoVolume(volume: number): Nivel {
  const niveis = Object.keys(NIVEIS) as Nivel[];
  return niveis.reduce((melhor, n) =>
    Math.abs(NIVEIS[n] - volume) < Math.abs(NIVEIS[melhor] - volume) ? n : melhor,
  );
}

const REPETICOES = [
  { valor: 0, nome: "Não repetir" },
  { valor: 5, nome: "A cada 5 minutos" },
  { valor: 10, nome: "A cada 10 minutos" },
  { valor: 15, nome: "A cada 15 minutos" },
  { valor: 30, nome: "A cada 30 minutos" },
] as const;

export function ConfigurarTablet({
  lojaid,
  nome,
  fechar,
}: {
  lojaid: number;
  nome: string;
  fechar: () => void;
}) {
  const qc = useQueryClient();
  const [ligado, setLigado] = useState(true);
  const [nivel, setNivel] = useState<Nivel>("medio");
  const [repetir, setRepetir] = useState(0);

  // A janela busca a configuração da loja quando abre: o cartão da lista não
  // carrega essas colunas, e não vale a pena engordar a consulta do menu.
  const atual = useQuery({
    queryKey: ["som-da-loja", lojaid],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("lojas")
        .select("somtarefanova, somvolume, somrepetirminutos")
        .eq("lojaid", lojaid)
        .single();
      if (error) throw error;
      return data;
    },
  });

  useEffect(() => {
    if (!atual.data) return;
    setLigado(atual.data.somtarefanova);
    setNivel(nivelDoVolume(atual.data.somvolume));
    setRepetir(atual.data.somrepetirminutos);
  }, [atual.data]);

  const salvar = useMutation({
    mutationFn: async () => {
      const { error } = await supabase.rpc("salvar_som_da_loja", {
        p_lojaid: lojaid,
        p_ligado: ligado,
        p_volume: NIVEIS[nivel],
        p_repetir: repetir,
      });
      if (error) throw error;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["som-da-loja", lojaid] });
      fechar();
    },
  });

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/50 p-0 sm:items-center sm:p-4">
      <div className="max-h-[92vh] w-full max-w-lg overflow-y-auto rounded-t-2xl bg-card p-5 sm:rounded-2xl">
        <h2 className="font-display text-xl font-semibold">Tablet da {nome}</h2>
        <p className="mt-1 text-sm text-muted-foreground">
          Vale só para o tablet desta loja. O celular da equipe nunca recebe aviso.
        </p>

        {atual.isLoading ? (
          <p className="mt-4 text-sm text-muted-foreground">Carregando...</p>
        ) : atual.isError ? (
          <p className="mt-4 text-sm text-destructive">{(atual.error as Error).message}</p>
        ) : (
          <>
            <label className="mt-4 flex items-center gap-2 text-sm">
              <input type="checkbox" checked={ligado} onChange={(e) => setLigado(e.target.checked)} />
              <span className="font-semibold">Som ao chegar tarefa nova</span>
            </label>
            <p className="mt-1 pl-6 text-xs text-muted-foreground">
              Um som curto quando aparece tarefa nova na fila, inclusive a que foi liberada pelo
              horário programado. Toca uma vez só, mesmo que cheguem várias juntas.
            </p>

            <fieldset className={`mt-5 ${ligado ? "" : "opacity-50"}`}>
              <legend className="text-sm font-semibold">Volume</legend>
              <div className="mt-2 flex gap-2">
                {(Object.keys(NIVEIS) as Nivel[]).map((n) => (
                  <button
                    key={n}
                    type="button"
                    disabled={!ligado}
                    onClick={() => setNivel(n)}
                    className={`flex-1 rounded-lg border px-3 py-2 text-sm ${
                      nivel === n ? "border-primary bg-azul-soft font-semibold text-azul" : "border-border"
                    }`}
                  >
                    {ROTULO[n]}
                  </button>
                ))}
              </div>
              <p className="mt-2 text-xs text-muted-foreground">
                Ajuste ouvindo, no balcão, com o movimento do dia.
              </p>
            </fieldset>

            <label className={`mt-5 block text-sm ${ligado ? "" : "opacity-50"}`}>
              <span className="font-semibold">Repetir o aviso enquanto a tarefa não for aceita</span>
              <select
                value={repetir}
                disabled={!ligado}
                onChange={(e) => setRepetir(Number(e.target.value))}
                className="mt-1 w-full rounded-lg border border-border bg-background p-2 text-sm"
              >
                {REPETICOES.map((r) => (
                  <option key={r.valor} value={r.valor}>
                    {r.nome}
                  </option>
                ))}
              </select>
            </label>
            <p className="mt-1 text-xs text-muted-foreground">
              Conta a partir da hora em que a tarefa ficou disponível, e para na hora em que alguém
              aceita. No máximo <strong>3 repetições</strong> por tarefa — depois disso fica só o
              cartão destacado. Com várias tarefas paradas, toca uma vez só, nunca um som por
              tarefa.
            </p>

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
          </>
        )}
      </div>
    </div>
  );
}
