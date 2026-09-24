import { createFileRoute } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { TabelaResponsiva } from "@/ui/TabelaResponsiva";
import { useLojaAtiva } from "@/lojas/loja-ativa";
import { Justificar } from "@/pessoas/justificar";
import { Pontos } from "@/ui/Pontos";
import { Pagina } from "@/ui/Pagina";

export const Route = createFileRoute("/_authenticated/relatorios")({
  component: Relatorios,
});

const campo =
  "rounded-lg border border-border bg-background px-3 py-2 text-sm placeholder:text-muted-foreground";

const hoje = () => new Intl.DateTimeFormat("en-CA", { timeZone: "America/Sao_Paulo" }).format(new Date());

/** AAAA-MM-DD → dd/mm/aaaa, sem passar por fuso. */
function dia(iso: string) {
  const [a, m, d] = iso.slice(0, 10).split("-");
  return `${d}/${m}/${a}`;
}

function dataHora(iso: string) {
  return new Date(iso).toLocaleString("pt-BR", {
    timeZone: "America/Sao_Paulo",
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

type Pendencia = {
  dia: string;
  atribuicaoid: number;
  titulo: string;
  pontos: number;
  loja: string | null;
  justificativa: string | null;
};
type Entrega = {
  titulo: string;
  loja: string | null;
  enviadaem: string;
  status: string;
  pontos: number;
  motivo: string | null;
};
type TarefaAnalise = {
  titulo: string;
  aprovadas: number;
  recusadas: number;
  estornadas: number;
  pendentes: number;
  naoseaplica: number;
};

const COR_STATUS: Record<string, string> = {
  Pendente: "border-azul/40 bg-azul-soft text-azul",
  Aprovada: "border-sucesso/40 bg-sucesso-soft text-sucesso",
  Recusada: "border-perigo/40 bg-perigo-soft text-perigo",
  Estornada: "border-perigo/40 bg-perigo-soft text-perigo",
};

function Relatorios() {
  const [aba, setAba] = useState<"pessoa" | "tarefa">("pessoa");
  const [de, setDe] = useState(`${hoje().slice(0, 7)}-01`);
  const [ate, setAte] = useState(hoje());

  return (
    <Pagina titulo="Relatórios">

      <div className="flex gap-2 border-b border-border">
        {(
          [
            ["pessoa", "Por pessoa"],
            ["tarefa", "Por tarefa"],
          ] as const
        ).map(([id, rotulo]) => (
          <button
            key={id}
            onClick={() => setAba(id)}
            className={`rounded-t-lg px-4 py-2 text-sm font-medium ${
              aba === id ? "bg-card text-foreground" : "text-muted-foreground"
            }`}
          >
            {rotulo}
          </button>
        ))}
      </div>

      <div className="flex flex-wrap items-center gap-3">
        <label className="flex items-center gap-2 text-sm text-muted-foreground">
          De
          <input type="date" value={de} onChange={(e) => setDe(e.target.value)} className={campo} />
        </label>
        <label className="flex items-center gap-2 text-sm text-muted-foreground">
          até
          <input type="date" value={ate} onChange={(e) => setAte(e.target.value)} className={campo} />
        </label>
      </div>

      {aba === "pessoa" ? <PorPessoa de={de} ate={ate} /> : <PorTarefa de={de} ate={ate} />}
    </Pagina>
  );
}

/* ------------------------------------------------------------------ */
/* Por pessoa: saldo, conquistas, o que ficou por fazer, o que entregou */
/* ------------------------------------------------------------------ */

function PorPessoa({ de, ate }: { de: string; ate: string }) {
  const [funcionarioid, setFuncionarioid] = useState<number | "">("");
  const [justificando, setJustificando] = useState<string | null>(null);
  const [recado, setRecado] = useState<string | null>(null);

  const pessoas = useQuery({
    queryKey: ["pessoas-relatorio"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("funcionarios")
        .select("funcionarioid, nomecompleto, ativo, saldopontos, pontostotal")
        .order("nomecompleto");
      if (error) throw error;
      return data ?? [];
    },
  });

  const escolhida = funcionarioid !== "";

  const pendencias = useQuery({
    queryKey: ["pendencias", funcionarioid, de, ate],
    enabled: escolhida && de !== "" && ate !== "",
    queryFn: async () => {
      const { data, error } = await supabase.rpc("pendencias_da_pessoa", {
        p_funcionarioid: Number(funcionarioid),
        p_de: de,
        p_ate: ate,
      });
      if (error) throw error;
      return (data ?? []) as unknown as Pendencia[];
    },
  });

  // O outro lado das pendências: as tarefas abertas que ela ASSUMIU. Uma
  // tarefa compartilhada só pesa na nota de quem pegou, então "atribuída" e
  // "pega" não são a mesma conta.
  const pegas = useQuery({
    queryKey: ["pegas-pessoa", funcionarioid, de, ate],
    enabled: escolhida && de !== "" && ate !== "",
    queryFn: async () => {
      const { data, error } = await supabase.rpc("tarefas_pegas_da_pessoa", {
        p_funcionarioid: Number(funcionarioid),
        p_de: de,
        p_ate: ate,
      });
      if (error) throw error;
      return data ?? [];
    },
  });

  const historico = useQuery({
    queryKey: ["historico-pessoa", funcionarioid],
    enabled: escolhida,
    queryFn: async () => {
      const { data, error } = await supabase.rpc("historico_da_pessoa", {
        p_funcionarioid: Number(funcionarioid),
        p_limite: 100,
      });
      if (error) throw error;
      return (data ?? []) as unknown as Entrega[];
    },
  });

  const conquistas = useQuery({
    queryKey: ["conquistas-pessoa", funcionarioid],
    enabled: escolhida,
    queryFn: async () => {
      const { data, error } = await supabase
        .from("conquistasfuncionarios")
        .select("conquistafuncionarioid, conquistaid, dataconquista, pontosbonus")
        .eq("funcionarioid", Number(funcionarioid))
        .order("dataconquista", { ascending: false });
      if (error) throw error;
      const { data: nomes } = await supabase.from("conquistas").select("conquistaid, nome, icone");
      const porId = new Map((nomes ?? []).map((c) => [c.conquistaid, c]));
      return (data ?? []).map((l) => ({
        ...l,
        nome: porId.get(l.conquistaid)?.nome ?? "—",
        icone: porId.get(l.conquistaid)?.icone ?? "🏆",
      }));
    },
  });

  const pessoa = (pessoas.data ?? []).find((p) => p.funcionarioid === funcionarioid);
  const listaPendencias = pendencias.data ?? [];
  const pontosPerdidos = listaPendencias.reduce((s, p) => s + p.pontos, 0);

  return (
    <div className="space-y-6">
      <select
        value={funcionarioid}
        onChange={(e) => setFuncionarioid(e.target.value === "" ? "" : Number(e.target.value))}
        className={campo}
      >
        <option value="">Escolha a pessoa...</option>
        {(pessoas.data ?? []).map((p) => (
          <option key={p.funcionarioid} value={p.funcionarioid}>
            {p.nomecompleto}
            {p.ativo ? "" : " (inativo)"}
          </option>
        ))}
      </select>

      {pessoa && (
        <>
          <div className="grid gap-3 sm:grid-cols-3">
            <Cartao titulo="Saldo atual" valor={`${pessoa.saldopontos} pontos`} />
            <Cartao titulo="Pontos ganhos desde o início" valor={`${pessoa.pontostotal ?? 0} pontos`} />
            <Cartao titulo="Conquistas" valor={String(conquistas.data?.length ?? "—")} />
          </div>

          {(conquistas.data ?? []).length > 0 && (
            <section className="space-y-2">
              <h2 className="text-lg font-semibold">Conquistas</h2>
              <div className="flex flex-wrap gap-2">
                {(conquistas.data ?? []).map((c) => (
                  <span
                    key={c.conquistafuncionarioid}
                    className="rounded-lg border border-border bg-card px-3 py-2 text-sm"
                    title={`Ganhou em ${c.dataconquista ? dataHora(c.dataconquista) : "—"}`}
                  >
                    {c.icone} {c.nome}
                    {c.pontosbonus > 0 && <span className="ml-1"><Pontos valor={c.pontosbonus} sinal sufixo="" /></span>}
                  </span>
                ))}
              </div>
            </section>
          )}

          <section className="space-y-2">
            <h2 className="text-lg font-semibold">Tarefas que ela pegou</h2>
            <p className="text-xs text-muted-foreground">
              Tarefas abertas (compartilhadas ou missões da equipe) que ela assumiu no período. Não eram dela: ela
              escolheu pegar, e a partir daí passaram a pesar na nota dela. O que já era dela está logo abaixo.
            </p>
            {pegas.isError && <p className="text-sm text-destructive">{(pegas.error as Error).message}</p>}
            <TabelaResponsiva
              linhas={pegas.data ?? []}
              chave={(t) => `${t.dia}-${t.titulo}`}
              vazio={pegas.isLoading ? "Carregando..." : "Ela não pegou nenhuma tarefa aberta neste período."}
              colunas={[
                { titulo: "Dia", valor: (t) => dia(t.dia), classe: () => "whitespace-nowrap text-muted-foreground" },
                { titulo: "Tarefa", principal: true, valor: (t) => t.titulo },
                { titulo: "Loja", valor: (t) => t.loja ?? "—", classe: () => "text-muted-foreground" },
                { titulo: "Pontos", alinhar: "direita", valor: (t) => t.pontos },
                {
                  titulo: "Situação",
                  valor: (t) => (t.revogadoem ? "Aceite revogado" : t.entregue ? "Entregue" : "Em andamento"),
                  classe: (t) => (t.revogadoem ? "text-muted-foreground" : t.entregue ? "text-sucesso" : ""),
                },
              ]}
            />
          </section>

          <section className="space-y-2">
            <h2 className="text-lg font-semibold">O que ficou por fazer</h2>
            <p className="text-xs text-muted-foreground">
              Tarefas que caíam no dia e não foram entregues, até ontem. Folga, domingo de folga, afastamento e
              justificativa aceita não entram. No máximo 3 meses por vez. Se a tarefa não fazia sentido no dia, use
              "Não se aplica".
            </p>
            {pendencias.isLoading && <p className="text-muted-foreground">Carregando...</p>}
            {pendencias.isError && <p className="text-sm text-destructive">{(pendencias.error as Error).message}</p>}
            {recado && <p className="text-sm text-sucesso">{recado}</p>}
            {listaPendencias.length > 0 && (
              <p className="text-sm">
                <strong>{listaPendencias.length}</strong> {listaPendencias.length === 1 ? "tarefa" : "tarefas"} sem
                entrega, <strong className="text-destructive">{pontosPerdidos}</strong> pontos que deixaram de entrar.
              </p>
            )}
            <TabelaResponsiva
              linhas={listaPendencias}
              chave={(p) => `${p.atribuicaoid}-${p.dia}`}
              vazio={pendencias.isLoading ? "Carregando..." : "Nada ficou para trás neste período. 👏"}
              colunas={[
                { titulo: "Dia", valor: (p) => dia(p.dia), classe: () => "whitespace-nowrap text-muted-foreground" },
                {
                  titulo: "Tarefa",
                  principal: true,
                  valor: (p) => {
                    const chave = `${p.atribuicaoid}-${p.dia}`;
                    return (
                      <>
                        {p.titulo}
                        {justificando === chave && (
                          <div className="mt-2 font-normal">
                            <Justificar
                              atribuicaoid={p.atribuicaoid}
                              dia={p.dia.slice(0, 10)}
                              aoTerminar={(texto) => {
                                setJustificando(null);
                                setRecado(`${p.titulo} (${dia(p.dia)}): ${texto}`);
                              }}
                            />
                          </div>
                        )}
                      </>
                    );
                  },
                },
                { titulo: "Loja", valor: (p) => p.loja ?? "—", classe: () => "text-muted-foreground" },
                { titulo: "Pontos", alinhar: "direita", valor: (p) => p.pontos },
                {
                  titulo: "Ação",
                  alinhar: "direita",
                  valor: (p) => {
                    const chave = `${p.atribuicaoid}-${p.dia}`;
                    return p.justificativa === "Pendente" ? (
                      <span className="text-xs text-azul">justificativa a decidir</span>
                    ) : (
                      <>
                        {p.justificativa === "Recusada" && (
                          <span className="mr-2 text-xs text-destructive">justificativa recusada</span>
                        )}
                        <button
                          onClick={() => setJustificando(justificando === chave ? null : chave)}
                          className="rounded-md border border-border px-2 py-1 text-xs"
                        >
                          {justificando === chave ? "Cancelar" : "Não se aplica"}
                        </button>
                      </>
                    );
                  },
                  classe: () => "whitespace-nowrap",
                },
              ]}
            />
          </section>

          <section className="space-y-2">
            <h2 className="text-lg font-semibold">Últimas entregas</h2>
            {historico.isLoading && <p className="text-muted-foreground">Carregando...</p>}
            {historico.isError && <p className="text-sm text-destructive">{(historico.error as Error).message}</p>}
            <div className="space-y-2">
              {(historico.data ?? []).map((e, i) => (
                <div
                  key={i}
                  className="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-border bg-card px-4 py-2"
                >
                  <div className="min-w-0">
                    <p className="font-medium">
                      {e.titulo}
                      <span className={`ml-2 rounded-md border px-2 py-0.5 text-xs font-normal ${COR_STATUS[e.status] ?? ""}`}>
                        {e.status}
                      </span>
                    </p>
                    <p className="text-xs text-muted-foreground">
                      {dataHora(e.enviadaem)}
                      {e.loja && ` · ${e.loja}`}
                      {e.motivo && ` · ${e.motivo}`}
                    </p>
                  </div>
                  <span className="text-sm text-muted-foreground">
                    {e.status === "Aprovada" ? <Pontos valor={e.pontos} sinal sufixo="" /> : "—"}
                  </span>
                </div>
              ))}
              {!historico.isLoading && (historico.data ?? []).length === 0 && (
                <p className="text-sm text-muted-foreground">Nenhuma entrega ainda.</p>
              )}
            </div>
          </section>
        </>
      )}
    </div>
  );
}

function Cartao({ titulo, valor }: { titulo: string; valor: string }) {
  return (
    <div className="rounded-xl border border-border bg-card p-4">
      <p className="text-xs text-muted-foreground">{titulo}</p>
      <p className="text-2xl font-bold">{valor}</p>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Por tarefa: onde mais se recusa ou estorna                          */
/* ------------------------------------------------------------------ */

function PorTarefa({ de, ate }: { de: string; ate: string }) {
  const { lojaAtiva, loja } = useLojaAtiva();
  const [alcance, setAlcance] = useState<"loja" | "conta">("conta");
  const lojaFiltro = alcance === "loja" ? lojaAtiva : null;

  const analise = useQuery({
    queryKey: ["analise-tarefas", de, ate, lojaFiltro],
    enabled: de !== "" && ate !== "",
    queryFn: async () => {
      const { data, error } = await supabase.rpc("analise_de_tarefas", {
        p_de: de,
        p_ate: ate,
        p_lojaid: lojaFiltro ?? undefined,
      });
      if (error) throw error;
      return (data ?? []) as unknown as TarefaAnalise[];
    },
  });

  const botao = (ativo: boolean) =>
    `rounded-lg px-3 py-1.5 text-sm ${ativo ? "bg-card font-semibold text-foreground" : "text-muted-foreground"}`;
  const lista = analise.data ?? [];

  return (
    <div className="space-y-3">
      <div className="flex w-fit gap-1 rounded-lg border border-border p-1">
        <button className={botao(alcance === "conta")} onClick={() => setAlcance("conta")}>
          Todas as lojas
        </button>
        <button className={botao(alcance === "loja")} onClick={() => setAlcance("loja")} disabled={lojaAtiva === null}>
          {loja?.nome ?? "Loja"}
        </button>
      </div>
      <p className="text-xs text-muted-foreground">
        Entregas por tarefa, pelo dia do envio, e justificativas aceitas ("não se aplica"). As tarefas com mais recusas,
        estornos e "não se aplica" aparecem primeiro: pode ser sinal de tarefa mal explicada ou que não faz sentido.
      </p>

      {analise.isLoading && <p className="text-muted-foreground">Carregando...</p>}
      {analise.isError && <p className="text-sm text-destructive">{(analise.error as Error).message}</p>}

      <TabelaResponsiva
        linhas={lista}
        chave={(t) => t.titulo}
        vazio={analise.isLoading ? "Carregando..." : "Nenhuma entrega neste período."}
        colunas={[
          { titulo: "Tarefa", principal: true, valor: (t) => t.titulo },
          { titulo: "Aprovadas", alinhar: "direita", valor: (t) => t.aprovadas, classe: () => "text-sucesso" },
          { titulo: "Recusadas", alinhar: "direita", valor: (t) => t.recusadas, classe: (t) => (t.recusadas > 0 ? "text-destructive" : "") },
          { titulo: "Estornadas", alinhar: "direita", valor: (t) => t.estornadas, classe: (t) => (t.estornadas > 0 ? "text-destructive" : "") },
          { titulo: "Não se aplica", alinhar: "direita", valor: (t) => t.naoseaplica },
          { titulo: "Aguardando", alinhar: "direita", valor: (t) => t.pendentes, classe: () => "text-muted-foreground" },
        ]}
      />
    </div>
  );
}
