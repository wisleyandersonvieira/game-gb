// Quadro: o filtro por dia da Fila (29/09/2026, decisão do Wisley).
//
// Hoje é a fila ao vivo (FilaDoDia). Um dia que passou vem da FOTO que a
// rotina da madrugada tira logo depois da meia-noite: como a fila estava no
// fim daquele dia. Dia sem foto mostra "não registrado" em "para pegar" —
// nunca um número parcial — e o que foi feito e o que estava em andamento,
// que ficam gravados com hora. Dia passado é só leitura.
//
// O alcance do filtro (mês corrente e anterior) vem do banco, da mesma regra
// que decide por quanto tempo a foto fica guardada.
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { ListaRolavel } from "@/painel/ListaRolavel";
import { diaPorExtenso, horaNoFuso, quandoFoi, somarDias } from "@/ui/hoje";

type Alcance = { hoje: string; primeirodia: string };

type ItemDaFoto = {
  atribuicaoid?: number;
  titulo: string;
  pontos: number;
  aberta?: boolean;
  situacao?: "para_pegar" | "em_andamento" | "feita";
  atrasada?: boolean;
  quempegounome?: string | null;
  pegaem?: string | null;
  feitapor?: string | null;
  feitaem?: string | null;
  feitasituacao?: string | null;
};

type DiaQuePassou = {
  dia: string;
  hoje: string;
  fuso: string;
  primeirodia: string;
  registrado: boolean;
  fotoem?: string;
  itens?: ItemDaFoto[];
  motivo?: "anterior" | "semfoto";
  feitas?: ItemDaFoto[];
  emandamento?: ItemDaFoto[];
};

const CHAVE_ALCANCE = ["alcance-da-fila"];

async function buscarAlcance(): Promise<Alcance> {
  const { data, error } = await supabase.rpc("alcance_da_fila");
  if (error) throw error;
  if (!data) throw new Error("Sem acesso.");
  return data as unknown as Alcance;
}

/** Os dados de um dia que passou (lidos só quando a tela pede aquele dia). */
export function useDiaQuePassou(lojaid: number, dia: string | null) {
  return useQuery({
    queryKey: ["fila-de-um-dia", lojaid, dia],
    enabled: dia !== null,
    staleTime: 5 * 60_000,
    queryFn: async () => {
      const { data, error } = await supabase.rpc("fila_de_um_dia", { p_lojaid: lojaid, p_dia: dia as string });
      if (error) throw error;
      return data as unknown as DiaQuePassou;
    },
  });
}

/**
 * Título e navegação: "Fila — hoje, 27/09/2026" e os botões de dia. Não deixa
 * ir para o futuro nem para antes do alcance. `hoje` vem da fila ou da
 * resposta do dia; se ainda não se sabe, pergunta ao banco na hora do clique.
 */
export function SeletorDeDia({
  dia,
  hoje,
  primeirodia,
  aoMudar,
}: {
  dia: string | null;
  hoje: string | null;
  primeirodia: string | null;
  aoMudar: (dia: string | null) => void;
}) {
  const qc = useQueryClient();
  const [alcance, setAlcance] = useState<Alcance | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const hojeSabido = hoje ?? alcance?.hoje ?? null;
  const primeiro = primeirodia ?? alcance?.primeirodia ?? null;

  const pegarAlcance = async () => {
    try {
      setErro(null);
      const a = await qc.fetchQuery({ queryKey: CHAVE_ALCANCE, queryFn: buscarAlcance, staleTime: 5 * 60_000 });
      setAlcance(a);
      return a;
    } catch (e) {
      setErro((e as Error).message);
      return null;
    }
  };

  const ir = (novo: string | null, h: string) => aoMudar(novo === null || novo >= h ? null : novo);

  const voltar = async () => {
    const h = hojeSabido ?? (await pegarAlcance())?.hoje;
    if (!h) return;
    ir(somarDias(dia ?? h, -1), h);
  };
  const avancar = () => {
    if (dia && hojeSabido) ir(somarDias(dia, 1), hojeSabido);
  };
  const podeVoltar = dia === null || primeiro === null || dia > primeiro;

  return (
    <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
      <h2 className="font-semibold">
        Fila{" "}
        <span className="font-normal text-muted-foreground">
          — {dia === null ? (hoje ? `hoje, ${diaPorExtenso(hoje).split(", ")[1]}` : "hoje") : diaPorExtenso(dia)}
        </span>
      </h2>
      <div className="flex flex-wrap items-center gap-2 text-sm">
        <button
          type="button"
          onClick={voltar}
          disabled={!podeVoltar}
          className="rounded-md border border-border px-2 py-1 disabled:opacity-40"
          title={podeVoltar ? "Dia anterior" : "O filtro vai até o primeiro dia do mês anterior"}
        >
          ‹ Dia anterior
        </button>
        <input
          type="date"
          aria-label="Escolher o dia"
          className="rounded-md border border-border bg-background px-2 py-1"
          value={dia ?? hojeSabido ?? ""}
          min={primeiro ?? undefined}
          max={hojeSabido ?? undefined}
          onFocus={() => {
            if (!alcance) void pegarAlcance();
          }}
          onChange={(e) => {
            const v = e.target.value;
            const h = hojeSabido;
            if (!v || !h) return;
            if (primeiro && v < primeiro) return;
            ir(v, h);
          }}
        />
        {dia !== null && (
          <>
            <button type="button" onClick={avancar} className="rounded-md border border-border px-2 py-1">
              Dia seguinte ›
            </button>
            <button type="button" onClick={() => aoMudar(null)} className="rounded-md border border-border px-2 py-1">
              Voltar para hoje
            </button>
          </>
        )}
      </div>
      {erro && <p className="text-sm text-destructive">{erro}</p>}
    </div>
  );
}

/** Um dia que passou: só leitura. */
export function FilaDeUmDia({ consulta }: { consulta: ReturnType<typeof useDiaQuePassou> }) {
  if (consulta.isLoading) return <p className="text-sm text-muted-foreground">Carregando o dia...</p>;
  if (consulta.isError) return <p className="text-sm text-destructive">{(consulta.error as Error).message}</p>;
  const d = consulta.data;
  if (!d) return null;

  // Horas escritas relativas ao dia escolhido: "às 15h10" é daquele dia.
  const quando = (iso: string | null | undefined) => quandoFoi(iso ?? null, d.dia, d.fuso);

  if (d.registrado) {
    const itens = d.itens ?? [];
    const de = (s: ItemDaFoto["situacao"]) => itens.filter((i) => i.situacao === s);
    return (
      <div className="space-y-3">
        <p className="text-xs text-muted-foreground">
          Como a fila estava no fim do dia{d.fotoem ? ` (foto tirada às ${horaNoFuso(d.fotoem, d.fuso)} do dia seguinte)` : ""}.
          Dia que passou é só para consulta: não dá para pegar, entregar nem revogar.
        </p>
        <div className="grid gap-3 md:grid-cols-3">
          <Faixa titulo="Ficou para pegar" itens={de("para_pegar")} vazio="Nada ficou para pegar.">
            {(i) => `ninguém pegou${i.aberta ? "" : " · com dono"}${i.atrasada ? " · atrasada" : ""}`}
          </Faixa>
          <Faixa titulo="Em andamento" itens={de("em_andamento")} vazio="Nada ficou em andamento.">
            {(i) => `com ${i.quempegounome ?? "alguém"} desde ${quando(i.pegaem).replace(/^às /, "")} · não foi entregue`}
          </Faixa>
          <Faixa titulo="Feitas" itens={de("feita")} vazio="Nada foi entregue.">
            {(i) => textoFeita(i, quando)}
          </Faixa>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-3">
      <p className="text-xs text-muted-foreground">
        Dia que passou é só para consulta: não dá para pegar, entregar nem revogar.
      </p>
      <div className="grid gap-3 md:grid-cols-3">
        <div className="space-y-1 rounded-lg border border-dashed border-border p-3">
          <p className="text-sm font-medium">Ficou para pegar</p>
          <p className="text-lg font-semibold text-muted-foreground">não registrado</p>
          <p className="text-xs text-muted-foreground">
            {d.motivo === "semfoto"
              ? "A rotina da madrugada não tirou a foto da fila deste dia a tempo. A Saúde do sistema mostra os dias que ficaram sem foto."
              : "Dia anterior ao registro completo."}
          </p>
        </div>
        <Faixa titulo="Em andamento no fim do dia" itens={d.emandamento ?? []} vazio="Nada ficou em andamento.">
          {(i) => `com ${i.quempegounome ?? "alguém"} desde ${quando(i.pegaem).replace(/^às /, "")} · não foi entregue`}
        </Faixa>
        <Faixa titulo="Feitas" itens={d.feitas ?? []} vazio="Nada foi entregue.">
          {(i) => textoFeita(i, quando)}
        </Faixa>
      </div>
    </div>
  );
}

function textoFeita(i: ItemDaFoto, quando: (iso: string | null | undefined) => string) {
  const quem = i.feitapor ? `por ${i.feitapor} ` : "";
  const situacao = i.feitasituacao === "Pendente" ? " · esperava validação" : i.feitasituacao === "Aprovada" ? " · aprovada" : "";
  return `${quem}${quando(i.feitaem)}${situacao}`;
}

function Faixa({
  titulo,
  itens,
  vazio,
  children,
}: {
  titulo: string;
  itens: ItemDaFoto[];
  vazio: string;
  children: (i: ItemDaFoto) => string;
}) {
  return (
    <div className="space-y-2 rounded-lg border border-border p-3">
      <p className="text-sm font-medium">
        {titulo} <span className="text-muted-foreground">({itens.length})</span>
      </p>
      {itens.length === 0 ? (
        <p className="text-xs text-muted-foreground">{vazio}</p>
      ) : (
        <ListaRolavel quantos={itens.length}>
          {itens.map((i, k) => (
            <li key={i.atribuicaoid ?? `${i.titulo}-${k}`} className="rounded-lg bg-background p-2 text-sm">
              <p className="font-medium">
                {i.titulo} <span className="text-muted-foreground">({i.pontos} pts)</span>
              </p>
              <p className="text-xs text-muted-foreground">{children(i)}</p>
            </li>
          ))}
        </ListaRolavel>
      )}
    </div>
  );
}
