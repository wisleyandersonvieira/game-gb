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
  horaEscrita,
  type Celula,
  type LinhaDoMapa,
  type Mapa,
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

/** O que o clique pediu: a pessoa, e (se foi numa célula) a hora e se ali já é intervalo. */
type Pedido = { pessoa: PessoaDoMapa; hora?: number; ehIntervalo?: boolean };

/** "Domingo" -> "domingo"; "Segunda-feira" -> "segunda-feira". */
const minusculo = (dia: string) => dia.charAt(0).toLowerCase() + dia.slice(1);

export function MapaDaJornada() {
  const { lojas, lojaAtiva } = useLojaAtiva();
  const [lojaEscolhida, setLojaEscolhida] = useState<number | null>(null);
  // Vazio = o dia da semana de hoje (quem decide é o banco, na mesma consulta).
  const [dia, setDia] = useState<number | null>(null);
  const [pedido, setPedido] = useState<Pedido | null>(null);
  const [avisoDoClique, setAvisoDoClique] = useState<string | null>(null);
  const [modoExportar, setModoExportar] = useState<"dia" | "semana">("dia");
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
    if (!consulta.data || lojaid === null) return;
    setExportando(true);
    setErroExportar(null);
    try {
      const { pdfMapaDaJornada } = await import("@/rh/pdf");
      if (modoExportar === "dia") {
        await pdfMapaDaJornada({
          loja: consulta.data.loja ?? "",
          paginas: [{ dia: nomeDoDia, mapa }],
          pulados: [],
          nomeDoArquivo: nomeDoDia,
        });
      } else {
        // A semana inteira numa consulta só (os sete dias vêm juntos).
        const { data, error } = await supabase.rpc("mapa_da_semana", { p_lojaid: lojaid });
        if (error) throw error;
        const semana = data as unknown as { loja: string | null; dias: Resposta[] };
        const paginas: { dia: string; mapa: Mapa }[] = [];
        const pulados: string[] = [];
        for (const n of ORDEM_NA_TELA) {
          const d = semana.dias.find((x) => x.diasemana === n);
          const m = montarMapa(d?.pessoas ?? []);
          if (m.horas.length === 0) pulados.push(DIAS_POR_EXTENSO[n - 1]);
          else paginas.push({ dia: DIAS_POR_EXTENSO[n - 1], mapa: m });
        }
        if (paginas.length === 0) throw new Error("Ninguém desta loja tem expediente em dia nenhum da semana.");
        await pdfMapaDaJornada({ loja: semana.loja ?? "", paginas, pulados, nomeDoArquivo: "semana" });
      }
    } catch (e) {
      setErroExportar((e as Error).message || "Não deu para gerar o PDF. Tente de novo.");
    } finally {
      setExportando(false);
    }
  }

  function aoClicarNaCelula(l: LinhaDoMapa, c: Celula | null, hora: number | null) {
    setAvisoDoClique(null);
    if (!l.celulas || c === null || hora === null) {
      setAvisoDoClique(`${l.pessoa.nome}: ${l.aviso ?? "sem expediente"} na ${minusculo(nomeDoDia)}. Não há intervalo para marcar.`);
      return;
    }
    if (c.tipo === "vazio") {
      setAvisoDoClique(`${l.pessoa.nome} está fora do expediente às ${rotuloDaHora(hora)}: não dá para marcar intervalo nessa hora.`);
      return;
    }
    setPedido({ pessoa: l.pessoa, hora, ehIntervalo: c.tipo === "intervalo" });
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
        <label className="space-y-1 text-sm">
          <span className="block text-muted-foreground">Exportar</span>
          <select
            value={modoExportar}
            onChange={(e) => setModoExportar(e.target.value as "dia" | "semana")}
            className={campo}
          >
            <option value="dia">Dia ({nomeDoDia || "selecionado"})</option>
            <option value="semana">Semana (um dia por página)</option>
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
        Clique num X para marcar o {NOME_DO_INTERVALO.toLowerCase()} daquela hora, ou na linha da pessoa para escolher o
        horário. Cada dia da semana tem o seu intervalo. Ele serve só para enxergar e imprimir a escala. O intervalo da
        jornada (em que o sistema não envia mensagens) não aparece aqui e continua como está.
      </p>
      {avisoDoClique && (
        <p className="rounded-lg border border-border bg-card px-3 py-2 text-sm text-muted-foreground">{avisoDoClique}</p>
      )}

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
          <Tabela
            horas={mapa.horas}
            linhas={mapa.linhas}
            totais={mapa.totais}
            aoClicarNaLinha={(p) => {
              setAvisoDoClique(null);
              setPedido({ pessoa: p });
            }}
            aoClicarNaCelula={aoClicarNaCelula}
          />
          <ul className="space-y-0.5 text-xs text-muted-foreground">
            {LEGENDA_DO_MAPA.map((l) => (
              <li key={l}>{l}</li>
            ))}
          </ul>
        </>
      )}

      <p className="rounded-lg border border-border px-4 py-3 text-xs text-muted-foreground">{AVISO_DA_JORNADA}</p>

      {pedido && diaMostrado && (
        <EditarIntervalo
          pedido={pedido}
          diasemana={diaMostrado}
          nomeDoDia={nomeDoDia}
          fechar={() => setPedido(null)}
        />
      )}
    </div>
  );
}

function Tabela({
  horas,
  linhas,
  totais,
  aoClicarNaLinha,
  aoClicarNaCelula,
}: {
  horas: number[];
  linhas: LinhaDoMapa[];
  totais: number[];
  aoClicarNaLinha: (p: PessoaDoMapa) => void;
  aoClicarNaCelula: (l: LinhaDoMapa, c: Celula | null, hora: number | null) => void;
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
            <tr key={l.pessoa.funcionarioid} className="border-t border-border">
              <td
                className={`${fixa} cursor-pointer px-3 py-2 hover:bg-accent/40`}
                onClick={() => aoClicarNaLinha(l.pessoa)}
                title={`Definir o ${NOME_DO_INTERVALO.toLowerCase()} de ${l.pessoa.nome}`}
              >
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
                l.celulas.map((c, i) => (
                  <CelulaDoMapa key={i} c={c} aoClicar={() => aoClicarNaCelula(l, c, horas[i])} />
                ))
              ) : (
                <td
                  colSpan={Math.max(1, horas.length)}
                  onClick={() => aoClicarNaCelula(l, null, null)}
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

function CelulaDoMapa({ c, aoClicar }: { c: Celula; aoClicar: () => void }) {
  if (c.tipo === "expediente")
    return (
      <td
        onClick={aoClicar}
        title="Marcar o intervalo nesta hora"
        className="cursor-pointer bg-sucesso/15 px-1 py-2 text-center font-bold text-sucesso hover:bg-sucesso/30"
      >
        X
      </td>
    );
  if (c.tipo === "intervalo")
    return (
      <td
        onClick={aoClicar}
        className="cursor-pointer bg-destructive/10 px-1 py-2 text-center font-bold tracking-widest text-destructive hover:bg-destructive/20"
        title={`${NOME_DO_INTERVALO}: clique para mudar ou remover`}
      >
        •••
      </td>
    );
  if (c.tipo === "parcial")
    return (
      <td
        onClick={aoClicar}
        title="Marcar o intervalo nesta hora"
        className="cursor-pointer bg-sucesso/5 px-1 py-2 text-center text-xs text-sucesso hover:bg-sucesso/20"
      >
        {c.hora}
      </td>
    );
  return <td onClick={aoClicar} className="px-1 py-2" />;
}

function EditarIntervalo({
  pedido,
  diasemana,
  nomeDoDia,
  fechar,
}: {
  pedido: Pedido;
  diasemana: number;
  nomeDoDia: string;
  fechar: () => void;
}) {
  const qc = useQueryClient();
  const { pessoa, hora, ehIntervalo } = pedido;
  // Clicou num X: sugere 1 hora a partir da hora clicada (15h -> 15:00 às 16:00).
  const sugerido = hora !== undefined && !ehIntervalo;
  const [inicio, setInicio] = useState(sugerido ? horaEscrita(hora * 60) : (pessoa.intervaloinicio ?? ""));
  const [fim, setFim] = useState(sugerido ? horaEscrita(hora * 60 + 60) : (pessoa.intervalofim ?? ""));
  const nomeMinusculo = minusculo(nomeDoDia);

  const salvar = useMutation({
    mutationFn: async (o: { tirar?: boolean; de?: string; ate?: string }) => {
      const de = o.tirar ? null : (o.de ?? inicio);
      const ate = o.tirar ? null : (o.ate ?? fim);
      if (!o.tirar && (!de || !ate)) throw new Error("Preencha o começo e o fim do intervalo.");
      if (!o.tirar && de === ate) throw new Error("O começo e o fim do intervalo são iguais.");
      const { error } = await supabase.rpc("salvar_intervalo_do_mapa", {
        p_funcionarioid: pessoa.funcionarioid,
        p_diasemana: diasemana,
        p_inicio: de,
        p_fim: ate,
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
          salvar.mutate({});
        }}
        className="w-full max-w-md space-y-3 rounded-2xl bg-card p-5"
      >
        <p className="text-lg font-semibold">
          Intervalo de {nomeMinusculo} · {pessoa.nome}
        </p>
        <p className="text-sm font-medium">{NOME_DO_INTERVALO}</p>

        {sugerido && (
          <div className="space-y-2 rounded-lg border border-border p-3">
            <p className="text-sm">
              Marcar o intervalo de {nomeMinusculo} às <strong>{rotuloDaHora(hora)}</strong> (
              {horaEscrita(hora * 60)} às {horaEscrita(hora * 60 + 60)})?
              {pessoa.intervaloinicio && (
                <span className="block text-xs text-muted-foreground">
                  Troca o intervalo de {nomeMinusculo} que já existe ({pessoa.intervaloinicio} às {pessoa.intervalofim}).
                </span>
              )}
            </p>
            <button
              type="button"
              disabled={salvar.isPending}
              onClick={() => salvar.mutate({ de: horaEscrita(hora * 60), ate: horaEscrita(hora * 60 + 60) })}
              className="rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground disabled:opacity-60"
            >
              Sim
            </button>
          </div>
        )}

        {ehIntervalo && (
          <div className="space-y-2 rounded-lg border border-border p-3">
            <p className="text-sm">
              {pessoa.nome} está em intervalo de {nomeMinusculo} ({pessoa.intervaloinicio} às {pessoa.intervalofim}).
              Remover?
            </p>
            <button
              type="button"
              disabled={salvar.isPending}
              onClick={() => salvar.mutate({ tirar: true })}
              className="rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground disabled:opacity-60"
            >
              Remover o intervalo de {nomeMinusculo}
            </button>
          </div>
        )}

        <p className="text-xs text-muted-foreground">
          {sugerido || ehIntervalo ? "Ou escolha outro horário e outra duração:" : `Horário do intervalo de ${nomeMinusculo}:`}
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
        <p className="text-xs text-muted-foreground">
          Vale só para {nomeMinusculo}: cada dia da semana tem o seu. Serve só para enxergar e imprimir a escala. Não cala
          o bot, não mexe em tarefa, liberação, nota nem rodízio: se uma tarefa cair no intervalo, a pessoa cumpre quando
          voltar.
        </p>
        {salvar.isError && <p className="text-sm text-destructive">{(salvar.error as Error).message}</p>}
        <div className="flex flex-wrap gap-2">
          <button
            type="submit"
            disabled={salvar.isPending}
            className="rounded-lg border border-border px-4 py-2 text-sm font-semibold disabled:opacity-60"
          >
            {salvar.isPending ? "Salvando..." : "Salvar este horário"}
          </button>
          {pessoa.intervaloinicio && !ehIntervalo && (
            <button
              type="button"
              disabled={salvar.isPending}
              onClick={() => salvar.mutate({ tirar: true })}
              className="rounded-lg border border-border px-4 py-2 text-sm"
            >
              Tirar o intervalo de {nomeMinusculo}
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
