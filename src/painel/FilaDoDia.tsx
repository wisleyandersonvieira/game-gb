// Quadro: a fila do dia da loja, em três faixas. É a mesma lista que o tablet
// vai mostrar na parte B1b — uma só fonte da verdade.
//
// "Para pegar" reúne as tarefas compartilhadas e as missões que ninguém
// assumiu ainda. Quem estava atribuído e não pegou fica neutro na nota, então
// o que ninguém pegou precisa aparecer aqui para o gestor decidir.
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { AindaNaoLiberadas } from "@/painel/AindaNaoLiberadas";
import { FilaDeUmDia, SeletorDeDia, useDiaQuePassou } from "@/painel/FilaDeUmDia";
import { ListaRolavel } from "@/painel/ListaRolavel";
import { separarParaPegar, textoDisponivel } from "@/painel/textoDaFila";
import { supabase } from "@/integrations/supabase/client";
import { faz, minutosDesde, useRelogio } from "@/ui/relogio";
import { quandoFoi } from "@/ui/hoje";

type Item = {
  atribuicaoid: number;
  entregarid: number | null;
  titulo: string;
  pontos: number;
  tipofrequencia: string;
  aberta: boolean;
  donoid: number | null;
  quempegou: number | null;
  quempegounome: string | null;
  pegaem: string | null;
  situacao: "para_pegar" | "em_andamento" | "feita";
  atrasada: boolean;
  disponiveldesde: string | null;
  rodizio: boolean;
  agora: string;
  /** O dia de hoje DA CONTA e o fuso dela, ditos pelo servidor. */
  hoje: string;
  fuso: string;
  /** false enquanto não chegou a hora de liberação. */
  liberada: boolean;
  liberaas: string | null;
};

export function FilaDoDia({
  lojaid,
  dia = null,
  aoMudarDia = () => {},
}: {
  lojaid: number;
  /** null = hoje (a fila ao vivo); AAAA-MM-DD = um dia que passou. */
  dia?: string | null;
  aoMudarDia?: (dia: string | null) => void;
}) {
  const qc = useQueryClient();
  const passado = useDiaQuePassou(lojaid, dia);
  const fila = useQuery({
    queryKey: ["fila-da-loja", lojaid],
    // Num dia que passou, a fila de hoje não é pedida.
    enabled: dia === null,
    queryFn: async () => {
      const { data, error } = await supabase.rpc("fila_da_loja", { p_lojaid: lojaid });
      if (error) throw error;
      return (data ?? []) as unknown as Item[];
    },
  });

  const revogar = useMutation({
    mutationFn: async ({ atribuicaoid, motivo }: { atribuicaoid: number; motivo: string }) => {
      // O dia do aceite é o que a FILA disse que é hoje (o servidor, no fuso
      // da conta), e não o do relógio deste computador.
      const hoje = fila.data?.[0]?.hoje;
      if (!hoje) throw new Error("A fila ainda não carregou. Tente de novo.");
      const { error } = await supabase.rpc("revogar_aceite", {
        p_atribuicaoid: atribuicaoid,
        p_dia: hoje,
        p_motivo: motivo,
      });
      if (error) throw error;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["fila-da-loja", lojaid] });
      qc.invalidateQueries({ queryKey: ["nao-pegas"] });
    },
  });

  // O relógio anda sozinho; a fila só conversa com o banco quando precisa.
  useRelogio();
  const lista = fila.data ?? [];
  const agora = lista[0]?.agora ?? null;
  const faixa = (s: Item["situacao"]) => lista.filter((i) => i.situacao === s);
  // A MESMA separação do tablet: "Para pegar" só com o que já liberou.
  const { liberadas: paraPegar, aindaNao } = separarParaPegar(lista);

  const seletor = (
    <SeletorDeDia
      dia={dia}
      hoje={lista[0]?.hoje ?? passado.data?.hoje ?? null}
      primeirodia={passado.data?.primeirodia ?? null}
      aoMudar={aoMudarDia}
    />
  );

  if (dia !== null) {
    return (
      <section className="space-y-3 rounded-xl border border-border bg-card p-4">
        {seletor}
        <FilaDeUmDia consulta={passado} />
      </section>
    );
  }

  return (
    <section className="space-y-3 rounded-xl border border-border bg-card p-4">
      <div className="space-y-1">
        {seletor}
        <p className="text-xs text-muted-foreground">
          O que a loja tem para fazer hoje. A tarefa compartilhada fica em "para pegar" até alguém assumir; a partir
          daí ela pesa na nota de quem pegou, e de mais ninguém.
        </p>
      </div>
      {fila.isError && <p className="text-sm text-destructive">{(fila.error as Error).message}</p>}
      {revogar.isError && <p className="text-sm text-destructive">{(revogar.error as Error).message}</p>}

      <div className="grid gap-3 md:grid-cols-3">
        <Faixa
          titulo="Para pegar"
          itens={paraPegar}
          vazio="Ninguém está esperando tarefa."
          agora={agora}
        />
        <Faixa
          titulo="Em andamento"
          itens={faixa("em_andamento")}
          vazio="Nada em andamento agora."
          agora={agora}
          aoRevogar={(i) => {
            const motivo = prompt(`Por que está tirando "${i.titulo}" de ${i.quempegounome}?`);
            if (motivo && motivo.trim()) revogar.mutate({ atribuicaoid: i.atribuicaoid, motivo });
          }}
          revogando={revogar.isPending}
        />
        <Faixa titulo="Feitas hoje" itens={faixa("feita")} vazio="Nada entregue ainda." agora={agora} />
      </div>
      <AindaNaoLiberadas itens={aindaNao} />
    </section>
  );
}

function Faixa({
  titulo,
  itens,
  vazio,
  agora,
  aoRevogar,
  revogando,
}: {
  titulo: string;
  itens: Item[];
  vazio: string;
  agora: string | null;
  aoRevogar?: (i: Item) => void;
  revogando?: boolean;
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
          {itens.map((i) => (
            <li key={i.atribuicaoid} className="rounded-lg bg-background p-2 text-sm">
              <p className="font-medium">
                {i.titulo} <span className="text-muted-foreground">({i.pontos} pts)</span>
              </p>
              <p className="text-xs text-muted-foreground">
                {i.quempegounome
                  ? `com ${i.quempegounome} ${faz(minutosDesde(i.pegaem, agora))} (${quandoFoi(i.pegaem, i.hoje, i.fuso)})`
                  : i.situacao === "para_pegar"
                    ? // As MESMAS palavras do tablet (textoDaFila).
                      `${textoDisponivel(i, agora)}${i.aberta ? " · a primeira que pegar leva" : " · com dono"}`
                    : "com dono"}
                {i.rodizio && i.situacao === "para_pegar" && " · rodízio ativo"}
                {i.atrasada && " · atrasada"}
              </p>
              {aoRevogar && (
                <button
                  disabled={revogando}
                  onClick={() => aoRevogar(i)}
                  className="mt-1 rounded-md border border-border px-2 py-1 text-xs disabled:opacity-40"
                >
                  Revogar o aceite
                </button>
              )}
            </li>
          ))}
        </ListaRolavel>
      )}
    </div>
  );
}
