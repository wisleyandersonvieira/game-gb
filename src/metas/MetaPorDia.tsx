// A meta do mês, dia a dia, por loja (30/09/2026, pedido do Wisley).
//
// Uma tabela com todos os dias do mês e duas colunas editáveis (meta em R$ e
// pontos), com UM Salvar no fim. Cada dia diz de onde veio o valor: "já
// lançado" (a meta congelada, só leitura), "especial" (só leitura, com o
// caminho para a aba), "deste mês" ou "do modelo". O que foi digitado fica
// guardado na página (trocar de mês, de aba ou de loja não perde nada) e só
// sai quando o banco confirma que salvou.
import { useEffect, useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { TabelaResponsiva } from "@/ui/TabelaResponsiva";
import { DINHEIRO } from "@/ui/prazos";
import {
  DIAS_DA_SEMANA,
  deOndeVem,
  diaDaSemana,
  editavel,
  mudancas,
  naTela,
  noCampo,
  numero,
  replicar,
  temAlteracao,
  type DiaDoMes,
  type Rascunho,
  type Semana,
} from "./mes";

type MesPorDia = {
  hoje: string;
  mesatual: string;
  /** A janela do lançamento (mês anterior): antes dela, somente leitura. */
  primeirodiaeditavel: string;
  podeeditar: boolean;
  especiaisver: boolean;
  especiaiseditar: boolean;
  modelo: { diasemanaid: number; valormeta: number; pontospremio: number }[];
  dias: DiaDoMes[];
};

const campo = "rounded-lg border border-border bg-background px-2 py-1.5 text-sm placeholder:text-muted-foreground";
const reais = (v: number | null | undefined) =>
  v === null || v === undefined || Number.isNaN(v)
    ? "—"
    : new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(Number(v));
const ddmm = (iso: string) => `${iso.slice(8, 10)}/${iso.slice(5, 7)}`;

const COR_DA_ORIGEM: Record<string, string> = {
  "já lançado": "bg-muted text-muted-foreground",
  especial: "bg-azul/10 text-azul",
  "deste mês": "bg-primary/10 text-primary",
  "do modelo": "border border-border text-muted-foreground",
};

export function useMesPorDia(lojaid: number, mes: string) {
  return useQuery({
    queryKey: ["metas-mes-dia", lojaid, mes],
    ...DINHEIRO,
    queryFn: async () => {
      const { data, error } = await supabase.rpc("metas_do_mes_por_dia", { p_lojaid: lojaid, p_mes: `${mes}-01` });
      if (error) throw error;
      return (data ?? null) as unknown as MesPorDia | null;
    },
  });
}

export function MetaPorDia({
  lojaid,
  mes,
  rascunho,
  aoDigitar,
  aoSalvar,
  aoMudarSujo,
  outrosPendentes,
  irParaEspeciais,
}: {
  lojaid: number;
  mes: string;
  rascunho: Rascunho;
  aoDigitar: (r: Rascunho) => void;
  aoSalvar: () => void;
  aoMudarSujo: (sujo: boolean) => void;
  outrosPendentes: string[];
  irParaEspeciais: () => void;
}) {
  const qc = useQueryClient();
  const consulta = useMesPorDia(lojaid, mes);
  const m = consulta.data;
  const dias = useMemo(() => m?.dias ?? [], [m]);
  const [recado, setRecado] = useState<string | null>(null);
  const [erroDoBanco, setErroDoBanco] = useState<string | null>(null);

  const sujo = temAlteracao(dias, rascunho);
  useEffect(() => aoMudarSujo(sujo), [sujo, aoMudarSujo]);
  useEffect(() => {
    setRecado(null);
    setErroDoBanco(null);
  }, [lojaid, mes]);

  const { linhas, erros } = mudancas(dias, rascunho);
  // A janela da meta é a do lançamento (01/10/2026): mês atual e anterior.
  const passado = m ? !dias.some((d) => d.dia >= m.primeirodiaeditavel) : false;
  const podeEditar = !!m?.podeeditar;

  const salvar = useMutation({
    mutationFn: async () => {
      if (Object.keys(erros).length > 0) throw new Error("Corrija os dias marcados em vermelho antes de salvar.");
      if (linhas.length === 0) throw new Error("Nada mudou.");
      const { data, error } = await supabase.rpc("salvar_metas_do_mes_por_dia", {
        p_lojaid: lojaid,
        p_mes: `${mes}-01`,
        p_linhas: linhas,
      });
      if (error) throw error;
      return data as number;
    },
    onMutate: () => {
      setRecado(null);
      setErroDoBanco(null);
    },
    onSuccess: (n) => {
      // Só agora o digitado sai: o banco confirmou.
      aoSalvar();
      setRecado(n === 1 ? "Salvo: 1 dia mudou." : `Salvo: ${n} dias mudaram.`);
      for (const k of ["metas-mes-dia", "metas-mes", "painel", "metas-modelos"]) qc.invalidateQueries({ queryKey: [k] });
    },
    // Deu errado: o que foi digitado continua na tela, e a mensagem diz o motivo.
    onError: (e) => setErroDoBanco((e as Error).message),
  });

  const mudar = (d: DiaDoMes, parte: Partial<{ valor: string; pontos: string }>) => {
    const atual = naTela(d, rascunho);
    let novo = { ...atual, ...parte };
    // Começou a digitar num dia que segue o modelo: os pontos partem dos do modelo.
    if (parte.valor !== undefined && atual.valor.trim() === "" && atual.pontos.trim() === "") {
      novo = { ...novo, pontos: noCampo(d.modelopontos ?? 0) };
    }
    aoDigitar({ ...rascunho, [d.dia]: novo });
    setRecado(null);
  };

  // A soma das metas diárias do mês, já com o que foi digitado.
  const soma = dias.reduce((s, d) => {
    if (!editavel(d)) return s + (d.meta ?? 0);
    const c = naTela(d, rascunho);
    const v = c.valor.trim() === "" ? (d.modelo ?? 0) : numero(c.valor);
    return s + (Number.isNaN(v) ? 0 : v);
  }, 0);

  if (consulta.isLoading) return <p className="text-muted-foreground">Carregando...</p>;
  if (consulta.isError) return <p className="text-sm text-destructive">{(consulta.error as Error).message}</p>;
  if (!m) {
    return (
      <p className="rounded-xl border border-border bg-card p-4 text-sm text-muted-foreground">
        Seu cargo não mostra a meta por dia desta loja.
      </p>
    );
  }

  return (
    <div className="space-y-4">
      {outrosPendentes.length > 0 && (
        <p className="rounded-xl border border-amber-500/50 bg-amber-500/10 p-3 text-sm">
          Também há metas digitadas e <strong>não salvas</strong> em: {outrosPendentes.join("; ")}.
        </p>
      )}
      {passado ? (
        <p className="rounded-xl border border-border bg-muted/40 p-3 text-sm text-muted-foreground">
          Este mês já saiu da janela de lançamento (mês atual e anterior): é somente leitura.
        </p>
      ) : !podeEditar ? (
        <p className="rounded-xl border border-border bg-muted/40 p-3 text-sm text-muted-foreground">
          Seu cargo mostra a meta por dia desta loja, mas não permite editar.
        </p>
      ) : (
        <Replicar key={`${lojaid}|${mes}`} modelo={m.modelo} dias={dias} rascunho={rascunho} aoAplicar={(r, n) => {
          aoDigitar(r);
          setRecado(n === 0 ? "Nenhum dia mudou." : `${n} ${n === 1 ? "dia preenchido" : "dias preenchidos"}. Confira e clique em Salvar.`);
        }} />
      )}

      <TabelaResponsiva
        linhas={dias}
        chave={(d) => d.dia}
        colunas={[
          {
            titulo: "Dia",
            principal: true,
            valor: (d) => (
              <>
                {ddmm(d.dia)} <span className="text-xs font-normal text-muted-foreground">{DIAS_DA_SEMANA[diaDaSemana(d.dia)]}</span>
                {d.dia === m.hoje && <span className="ml-1 text-xs text-primary">hoje</span>}
              </>
            ),
            classe: () => "whitespace-nowrap",
          },
          {
            titulo: "Meta (R$)",
            valor: (d) =>
              podeEditar && editavel(d) ? (
                <input
                  inputMode="decimal"
                  aria-label={`Meta de ${ddmm(d.dia)}`}
                  placeholder={d.modelo != null ? noCampo(d.modelo) : "sem meta"}
                  value={naTela(d, rascunho).valor}
                  onChange={(e) => mudar(d, { valor: e.target.value })}
                  className={`${campo} w-28 ${erros[d.dia] ? "border-destructive" : ""}`}
                />
              ) : d.origem === "especial" && d.meta === null ? (
                <span className="text-muted-foreground">sem permissão para ver</span>
              ) : (
                reais(d.meta)
              ),
          },
          {
            titulo: "Pontos",
            valor: (d) =>
              podeEditar && editavel(d) ? (
                <input
                  type="number"
                  min={0}
                  aria-label={`Pontos de ${ddmm(d.dia)}`}
                  placeholder={d.modelopontos != null ? String(d.modelopontos) : "0"}
                  value={naTela(d, rascunho).pontos}
                  onChange={(e) => mudar(d, { pontos: e.target.value })}
                  className={`${campo} w-20 ${erros[d.dia] ? "border-destructive" : ""}`}
                />
              ) : (
                (d.pontos ?? "—")
              ),
          },
          {
            titulo: "De onde vem",
            valor: (d) => {
              const o = deOndeVem(d, rascunho);
              return (
                <span className="flex flex-wrap items-center gap-1">
                  <span className={`rounded-full px-2 py-0.5 text-xs ${COR_DA_ORIGEM[o]}`}>{o}</span>
                  {o === "especial" && (
                    <button type="button" onClick={irParaEspeciais} className="text-xs text-azul underline-offset-2 hover:underline">
                      {d.descricao ?? "ver"} → Metas especiais
                    </button>
                  )}
                  {erros[d.dia] && <span className="text-xs text-destructive">{erros[d.dia]}</span>}
                </span>
              );
            },
          },
        ]}
      />

      <div className="space-y-2 rounded-xl border border-border bg-card p-4">
        <p className="text-sm text-muted-foreground">
          Soma das metas diárias deste mês{sujo ? " (com o que foi digitado)" : ""}:{" "}
          <strong className="text-foreground">{reais(soma)}</strong>
        </p>
        {podeEditar && !passado && (
          <div className="flex flex-wrap items-center gap-3">
            <button
              type="button"
              disabled={salvar.isPending || !sujo}
              onClick={() => salvar.mutate()}
              className="rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground disabled:opacity-60"
            >
              {salvar.isPending ? "Salvando..." : linhas.length > 0 ? `Salvar (${linhas.length} ${linhas.length === 1 ? "dia" : "dias"})` : "Salvar"}
            </button>
            {sujo && (
              <button
                type="button"
                onClick={() => window.confirm("Descartar o que foi digitado neste mês?") && aoDigitar({})}
                className="rounded-lg border border-border px-4 py-2 text-sm"
              >
                Descartar alterações
              </button>
            )}
          </div>
        )}
        {recado && <p className="text-sm text-sucesso">{recado}</p>}
        {erroDoBanco && (
          <p className="text-sm text-destructive">
            Não salvou: {erroDoBanco} Nada do que você digitou foi perdido.
          </p>
        )}
        <p className="text-xs text-muted-foreground">
          Em branco, o dia segue o modelo da semana. Apagar o valor de um dia faz ele voltar ao modelo. Dia já lançado
          guarda a meta que tinha; dia com meta especial muda na aba Metas especiais.
        </p>
      </div>
    </div>
  );
}

function Replicar({
  modelo,
  dias,
  rascunho,
  aoAplicar,
}: {
  modelo: MesPorDia["modelo"];
  dias: DiaDoMes[];
  rascunho: Rascunho;
  aoAplicar: (r: Rascunho, n: number) => void;
}) {
  // Os sete campos vêm com o modelo atual da loja.
  const [semana, setSemana] = useState<Semana>(() =>
    DIAS_DA_SEMANA.map((_, i) => {
      const x = modelo.find((mm) => mm.diasemanaid === i + 1);
      return { valor: x ? noCampo(x.valormeta) : "", pontos: x ? String(x.pontospremio) : "" };
    }),
  );
  const [substituir, setSubstituir] = useState(false);

  return (
    <div className="space-y-3 rounded-xl border border-border bg-card p-4">
      <p className="text-sm font-semibold">Replicar a semana no mês</p>
      <div className="grid gap-2 sm:grid-cols-7">
        {DIAS_DA_SEMANA.map((nome, i) => (
          <div key={nome} className="grid grid-cols-[5rem_1fr_4rem] items-center gap-2 sm:grid-cols-1">
            <span className="text-xs font-medium">{nome}</span>
            <input
              inputMode="decimal"
              aria-label={`Meta de ${nome}`}
              placeholder="R$"
              value={semana[i].valor}
              onChange={(e) => setSemana(semana.map((s, j) => (j === i ? { ...s, valor: e.target.value } : s)))}
              className={`${campo} w-full`}
            />
            <input
              type="number"
              min={0}
              aria-label={`Pontos de ${nome}`}
              placeholder="pts"
              value={semana[i].pontos}
              onChange={(e) => setSemana(semana.map((s, j) => (j === i ? { ...s, pontos: e.target.value } : s)))}
              className={`${campo} w-full`}
            />
          </div>
        ))}
      </div>
      <div className="flex flex-wrap items-center gap-4">
        <label className="flex items-center gap-2 text-sm">
          <input type="checkbox" checked={substituir} onChange={(e) => setSubstituir(e.target.checked)} />
          substituir os dias que já têm valor
        </label>
        <button
          type="button"
          onClick={() => {
            const { rascunho: r, mudou } = replicar(dias, rascunho, semana, substituir);
            aoAplicar(r, mudou);
          }}
          className="rounded-lg border border-primary px-4 py-2 text-sm font-semibold text-primary"
        >
          Aplicar ao mês
        </button>
      </div>
      <p className="text-xs text-muted-foreground">
        Preenche a tabela abaixo (nada é salvo ainda). {substituir ? "Substitui também" : "Só os dias em branco; não mexe"} nos dias que já têm valor deste mês.
        Dia já lançado e dia com meta especial nunca mudam.
      </p>
    </div>
  );
}
