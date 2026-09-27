// Aba Mapa da tela Jornada: quem está em expediente em cada hora, numa loja,
// num dia da semana. PLANEJAMENTO de escala, montado só com o cadastro: não
// olha a hora de agora nem marca nada (o STGame não controla jornada).
//
// O intervalo daqui é o "Intervalo (planejamento, não afeta o sistema)": só
// para enxergar e imprimir a escala. NÃO é o intervalo da jornada (silêncio
// do bot), e nada do sistema o lê além desta tela (seção 75 do teste de
// isolamento e mapa-catraca.test.ts).
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useMemo, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useLojaAtiva } from "@/lojas/loja-ativa";
import {
  AVISO_DA_JORNADA,
  LEGENDA_DO_MAPA,
  montarMapa,
  rotuloDaHora,
  type Celula,
  type LinhaDoMapa,
  type PessoaDoMapa,
} from "@/jornada/mapa";

const campo = "rounded-lg border border-border bg-background px-3 py-2 text-sm";
const NOME_DO_INTERVALO = "Intervalo (planejamento, não afeta o sistema)";
const DIAS_POR_EXTENSO = [
  "Domingo",
  "Segunda-feira",
  "Terça-feira",
  "Quarta-feira",
  "Quinta-feira",
  "Sexta-feira",
  "Sábado",
];
// A ordem da tela começa na segunda; o banco guarda 1 = domingo ... 7 = sábado.
const ORDEM_NA_TELA = [2, 3, 4, 5, 6, 7, 1];

type Resposta = {
  diasemana: number;
  hoje: string;
  loja: string | null;
  pessoas: PessoaDoMapa[];
};

export function MapaDaJornada() {
  const { lojas, lojaAtiva } = useLojaAtiva();
  const [lojaEscolhida, setLojaEscolhida] = useState<number | null>(null);
  // Vazio = o dia da semana de hoje (quem decide é o banco, na mesma consulta).
  const [dia, setDia] = useState<number | null>(null);
  const [editando, setEditando] = useState<PessoaDoMapa | null>(null);
  const [exportando, setExportando] = useState(false);
  const [erroExportar, setErroExportar] = useState<string | null>(null);
  const lojaid = lojaEscolhida ?? lojaAtiva;

  const consulta = useQuery({
    queryKey: ["mapa-jornada", lojaid, dia],
    enabled: lojaid !== null,
    queryFn: async () => {
      const { data, error } = await supabase.rpc("mapa_da_jornada", {
        p_lojaid: lojaid!,
        ...(dia !== null ? { p_diasemana: dia } : {}),
      });
      if (error) throw error;
      return data as unknown as Resposta;
    },
  });

  const mapa = useMemo(() => montarMapa(consulta.data?.pessoas ?? []), [consulta.data]);
  const diaMostrado = dia ?? consulta.data?.diasemana ?? null;
  const nomeDoDia = diaMostrado ? DIAS_POR_EXTENSO[diaMostrado - 1] : "";

  async function exportar() {
    if (!consulta.data) return;
    setExportando(true);
    setErroExportar(null);
    try {
      const { pdfMapaDaJornada } = await import("@/rh/pdf");
      await pdfMapaDaJornada({
        loja: consulta.data.loja ?? "",
        dia: nomeDoDia,
        mapa,
      });
    } catch (e) {
      setErroExportar((e as Error).message || "Não deu para gerar o PDF. Tente de novo.");
    } finally {
      setExportando(false);
    }
  }

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-end gap-3">
        <label className="space-y-1 text-sm">
          <span className="block text-muted-foreground">Loja</span>
          <select value={lojaid ?? ""} onChange={(e) => setLojaEscolhida(Number(e.target.value))} className={campo}>
            {lojas.map((l) => (
              <option key={l.lojaid} value={l.lojaid}>
                {l.nome}
              </option>
            ))}
          </select>
        </label>
        <label className="space-y-1 text-sm">
          <span className="block text-muted-foreground">Dia da semana</span>
          <select value={diaMostrado ?? ""} onChange={(e) => setDia(Number(e.target.value))} className={campo}>
            {ORDEM_NA_TELA.map((n) => (
              <option key={n} value={n}>
                {DIAS_POR_EXTENSO[n - 1]}
              </option>
            ))}
          </select>
        </label>
        <button
          onClick={exportar}
          disabled={!consulta.data || exportando}
          className="rounded-lg border border-border px-4 py-2 text-sm font-medium disabled:opacity-60"
        >
          {exportando ? "Gerando PDF..." : "Exportar (PDF)"}
        </button>
      </div>
      {erroExportar && <p className="text-sm text-destructive">{erroExportar}</p>}

      <p className="text-xs text-muted-foreground">
        Clique na linha de uma pessoa para definir o {NOME_DO_INTERVALO.toLowerCase()}. Ele serve só para enxergar e
        imprimir a escala. O intervalo da jornada (em que o sistema não envia mensagens) não aparece aqui e continua
        como está.
      </p>

      {consulta.isLoading && <p className="text-muted-foreground">Carregando...</p>}
      {consulta.isError && <p className="text-sm text-destructive">{(consulta.error as Error).message}</p>}
      {consulta.data && consulta.data.pessoas.length === 0 && (
        <p className="text-sm text-muted-foreground">Nenhum colaborador ativo nesta loja.</p>
      )}
      {consulta.data && consulta.data.pessoas.length > 0 && (
        <>
          {mapa.horas.length === 0 && (
            <p className="text-sm text-muted-foreground">
              Ninguém desta loja tem expediente na {nomeDoDia.toLowerCase()}.
            </p>
          )}
          <Tabela horas={mapa.horas} linhas={mapa.linhas} totais={mapa.totais} aoClicar={setEditando} />
          <ul className="space-y-0.5 text-xs text-muted-foreground">
            {LEGENDA_DO_MAPA.map((l) => (
              <li key={l}>{l}</li>
            ))}
          </ul>
        </>
      )}

      <p className="rounded-lg border border-border px-4 py-3 text-xs text-muted-foreground">{AVISO_DA_JORNADA}</p>

      {editando && <EditarIntervalo pessoa={editando} fechar={() => setEditando(null)} />}
    </div>
  );
}

function Tabela({
  horas,
  linhas,
  totais,
  aoClicar,
}: {
  horas: number[];
  linhas: LinhaDoMapa[];
  totais: number[];
  aoClicar: (p: PessoaDoMapa) => void;
}) {
  // Rola de lado no celular; a coluna do nome fica parada.
  const fixa = "sticky left-0 z-10 bg-card";
  return (
    <div className="overflow-x-auto rounded-xl border border-border bg-card">
      <table className="w-full border-collapse text-sm">
        <thead>
          <tr className="bg-primary text-primary-foreground">
            <th className={`sticky left-0 z-10 bg-primary px-3 py-2 text-left font-semibold`}>Cargo | Nome</th>
            {horas.map((h) => (
              <th key={h} className="min-w-12 px-1 py-2 text-center font-semibold">
                {rotuloDaHora(h)}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {linhas.map((l) => (
            <tr
              key={l.pessoa.funcionarioid}
              onClick={() => aoClicar(l.pessoa)}
              className="cursor-pointer border-t border-border hover:bg-accent/40"
              title={`Definir o ${NOME_DO_INTERVALO.toLowerCase()} de ${l.pessoa.nome}`}
            >
              <td className={`${fixa} px-3 py-2`}>
                <span className="flex flex-wrap items-center gap-2">
                  {l.pessoa.cargo && (
                    <span className="rounded-md bg-accent px-2 py-0.5 text-xs font-semibold uppercase text-accent-foreground">
                      {l.pessoa.cargo}
                    </span>
                  )}
                  <span className="font-medium">{l.pessoa.nome}</span>
                </span>
                {l.celulas && l.aviso && <span className="block text-xs text-muted-foreground">{l.aviso}</span>}
                {l.intervaloFora && (
                  <span className="block text-xs text-destructive">intervalo do mapa fora do expediente neste dia</span>
                )}
              </td>
              {l.celulas ? (
                l.celulas.map((c, i) => <CelulaDoMapa key={i} c={c} />)
              ) : (
                <td
                  colSpan={Math.max(1, horas.length)}
                  className="px-3 py-2 text-center text-sm italic text-muted-foreground"
                >
                  {l.aviso}
                </td>
              )}
            </tr>
          ))}
          {horas.length > 0 && (
            <tr className="border-t-2 border-border bg-accent font-semibold">
              <td className="sticky left-0 z-10 bg-accent px-3 py-2">Total de colaboradores</td>
              {totais.map((t, i) => (
                <td key={i} className={`px-1 py-2 text-center text-base ${t === 0 ? "text-destructive" : ""}`}>
                  {t}
                </td>
              ))}
            </tr>
          )}
        </tbody>
      </table>
    </div>
  );
}

function CelulaDoMapa({ c }: { c: Celula }) {
  if (c.tipo === "expediente") return <td className="bg-sucesso/15 px-1 py-2 text-center font-bold text-sucesso">X</td>;
  if (c.tipo === "intervalo")
    return (
      <td
        className="bg-destructive/10 px-1 py-2 text-center font-bold tracking-widest text-destructive"
        title={NOME_DO_INTERVALO}
      >
        •••
      </td>
    );
  if (c.tipo === "parcial")
    return <td className="bg-sucesso/5 px-1 py-2 text-center text-xs text-sucesso">{c.hora}</td>;
  return <td className="px-1 py-2" />;
}

function EditarIntervalo({ pessoa, fechar }: { pessoa: PessoaDoMapa; fechar: () => void }) {
  const qc = useQueryClient();
  const [inicio, setInicio] = useState(pessoa.intervaloinicio ?? "");
  const [fim, setFim] = useState(pessoa.intervalofim ?? "");

  const salvar = useMutation({
    mutationFn: async (tirar: boolean) => {
      if (!tirar && (!inicio || !fim)) throw new Error("Preencha o começo e o fim do intervalo.");
      if (!tirar && inicio === fim) throw new Error("O começo e o fim do intervalo são iguais.");
      const { error } = await supabase.rpc("salvar_intervalo_do_mapa", {
        p_funcionarioid: pessoa.funcionarioid,
        p_inicio: tirar ? null : inicio,
        p_fim: tirar ? null : fim,
      });
      if (error) throw error;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["mapa-jornada"] });
      fechar();
    },
  });

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4" onClick={fechar}>
      <form
        onClick={(e) => e.stopPropagation()}
        onSubmit={(e) => {
          e.preventDefault();
          salvar.mutate(false);
        }}
        className="w-full max-w-md space-y-3 rounded-2xl bg-card p-5"
      >
        <p className="text-lg font-semibold">{pessoa.nome}</p>
        <p className="text-sm font-medium">{NOME_DO_INTERVALO}</p>
        <p className="text-xs text-muted-foreground">
          Serve só para enxergar e imprimir a escala. Não cala o bot, não mexe em tarefa, liberação, nota nem rodízio:
          se uma tarefa cair no intervalo, a pessoa cumpre quando voltar. Um intervalo por pessoa, mostrado nos dias em
          que ela trabalha.
        </p>
        <div className="flex flex-wrap gap-3 text-sm">
          <label className="flex items-center gap-1">
            De
            <input type="time" value={inicio} onChange={(e) => setInicio(e.target.value)} className={campo} />
          </label>
          <label className="flex items-center gap-1">
            até
            <input type="time" value={fim} onChange={(e) => setFim(e.target.value)} className={campo} />
          </label>
        </div>
        {salvar.isError && <p className="text-sm text-destructive">{(salvar.error as Error).message}</p>}
        <div className="flex flex-wrap gap-2">
          <button
            type="submit"
            disabled={salvar.isPending}
            className="rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground disabled:opacity-60"
          >
            {salvar.isPending ? "Salvando..." : "Salvar"}
          </button>
          {pessoa.intervaloinicio && (
            <button
              type="button"
              disabled={salvar.isPending}
              onClick={() => salvar.mutate(true)}
              className="rounded-lg border border-border px-4 py-2 text-sm"
            >
              Tirar intervalo
            </button>
          )}
          <button type="button" onClick={fechar} className="rounded-lg border border-border px-4 py-2 text-sm">
            Cancelar
          </button>
        </div>
      </form>
    </div>
  );
}
