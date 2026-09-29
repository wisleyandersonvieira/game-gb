// Jornada: horários de EXPEDIENTE com nome, por dia da semana (27/09/2026).
//
// NÃO é controle de jornada (CLAUDE.md). Estes horários existem só para o
// sistema saber quando enviar tarefas e avisos. Esta tela não tem, e não deve
// ter: total de horas, carga semanal, banco de horas, marcação de entrada e
// saída, nem comparação entre previsto e feito. Pedido que leve para esse lado
// é avisado ANTES de ser feito.
import { createFileRoute } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Pagina } from "@/ui/Pagina";
import { DIAS, resumoDaJornada } from "@/jornada/resumo";
import { MapaDaJornada } from "@/jornada/MapaDaJornada";

export const Route = createFileRoute("/_authenticated/jornada")({
  component: Jornadas,
});

const campo = "rounded-lg border border-border bg-background px-3 py-2 text-sm placeholder:text-muted-foreground";

type Dia = { ativo: boolean; entrada: string; saida: string };
const SEMANA_VAZIA = (): Dia[] => Array.from({ length: 7 }, () => ({ ativo: false, entrada: "", saida: "" }));
const FORM_VAZIO = {
  nome: "",
  dias: SEMANA_VAZIA(),
  temPausa: false,
  pausainicio: "",
  pausafim: "",
  observacao: "",
  ativa: true,
};
// A ordem da tela começa na segunda; o banco guarda 1 = domingo ... 7 = sábado.
const ORDEM_NA_TELA = [2, 3, 4, 5, 6, 7, 1];

function Jornadas() {
  const [aba, setAba] = useState<"jornadas" | "mapa">("jornadas");
  return (
    <Pagina titulo="Jornada" descricao="Horários de expediente com nome, para vincular às pessoas.">
      <p className="rounded-lg border-2 border-primary bg-card px-4 py-3 text-sm font-medium">
        Estes horários servem para o sistema saber quando enviar tarefas e avisos. O STGame não registra ponto nem
        controla jornada.
      </p>
      <div className="flex gap-2 border-b border-border">
        {(
          [
            ["jornadas", "Jornadas"],
            ["mapa", "Mapa"],
          ] as const
        ).map(([chave, rotulo]) => (
          <button
            key={chave}
            onClick={() => setAba(chave)}
            className={`-mb-px border-b-2 px-4 py-2 text-sm font-medium ${
              aba === chave ? "border-primary text-primary" : "border-transparent text-muted-foreground"
            }`}
          >
            {rotulo}
          </button>
        ))}
      </div>
      {aba === "jornadas" ? <ListaDeJornadas /> : <MapaDaJornada />}
    </Pagina>
  );
}

function ListaDeJornadas() {
  const qc = useQueryClient();
  // O formulário começa fechado: abre em "Criar jornada" ou em "Editar".
  const [formAberto, setFormAberto] = useState(false);
  const [form, setForm] = useState(FORM_VAZIO);
  const [editando, setEditando] = useState<number | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [vendoPessoas, setVendoPessoas] = useState<number | null>(null);

  const dados = useQuery({
    queryKey: ["jornadas"],
    queryFn: async () => {
      const [j, d, f, fl, l] = await Promise.all([
        supabase.from("jornadas").select("jornadaid, nome, pausainicio, pausafim, observacao, ativa").order("nome"),
        supabase.from("jornadasdias").select("jornadaid, diasemana, entrada, saida"),
        supabase.from("funcionarios").select("funcionarioid, nomecompleto, ativo, jornadaid").eq("ativo", true),
        supabase.from("funcionarioslojas").select("funcionarioid, lojaid, ativo"),
        supabase.from("lojas").select("lojaid, nome"),
      ]);
      for (const r of [j, d, f, fl, l]) if (r.error) throw r.error;
      const nomeLoja = new Map((l.data ?? []).map((x) => [x.lojaid, x.nome]));
      const lojasDe = new Map<number, string[]>();
      for (const v of fl.data ?? []) {
        if (!v.ativo) continue;
        lojasDe.set(v.funcionarioid, [...(lojasDe.get(v.funcionarioid) ?? []), nomeLoja.get(v.lojaid) ?? ""]);
      }
      return (j.data ?? []).map((jo) => ({
        ...jo,
        dias: (d.data ?? []).filter((x) => x.jornadaid === jo.jornadaid),
        // Só os colaboradores ATIVOS contam (e aparecem na janela).
        pessoas: (f.data ?? [])
          .filter((p) => p.jornadaid === jo.jornadaid)
          .map((p) => ({
            nome: p.nomecompleto,
            lojas: lojasDe.get(p.funcionarioid) ?? [],
          })),
      }));
    },
  });

  const lista = dados.data ?? [];
  const emEdicao = lista.find((j) => j.jornadaid === editando);

  function limpar() {
    setForm({ ...FORM_VAZIO, dias: SEMANA_VAZIA() });
    setEditando(null);
    setErro(null);
    setFormAberto(false);
  }

  function editar(j: (typeof lista)[number]) {
    const dias = SEMANA_VAZIA();
    for (const d of j.dias)
      dias[d.diasemana - 1] = {
        ativo: true,
        entrada: d.entrada.slice(0, 5),
        saida: d.saida.slice(0, 5),
      };
    setForm({
      nome: j.nome,
      dias,
      temPausa: !!j.pausainicio,
      pausainicio: j.pausainicio?.slice(0, 5) ?? "",
      pausafim: j.pausafim?.slice(0, 5) ?? "",
      observacao: j.observacao ?? "",
      ativa: j.ativa,
    });
    setEditando(j.jornadaid);
    setErro(null);
    setFormAberto(true);
  }

  /** "Repetir para todos os dias": copia o primeiro dia preenchido para os sete. */
  function repetirParaTodos() {
    const modelo = ORDEM_NA_TELA.map((n) => form.dias[n - 1]).find((d) => d.ativo && d.entrada && d.saida);
    if (!modelo) {
      setErro("Preencha a entrada e a saída de um dia primeiro.");
      return;
    }
    setForm({ ...form, dias: form.dias.map(() => ({ ...modelo })) });
    setErro(null);
  }

  const salvar = useMutation({
    mutationFn: async () => {
      const dias = form.dias
        .map((d, i) => ({ ...d, dia: i + 1 }))
        .filter((d) => d.ativo)
        .map((d) => {
          if (!d.entrada || !d.saida)
            throw new Error(`Preencha a entrada e a saída de ${DIAS[d.dia - 1]} (ou desmarque o dia).`);
          if (d.entrada === d.saida) throw new Error(`${DIAS[d.dia - 1]}: entrada e saída iguais.`);
          return { dia: d.dia, entrada: d.entrada, saida: d.saida };
        });
      if (form.temPausa && (!form.pausainicio || !form.pausafim)) {
        throw new Error("Preencha o começo e o fim do intervalo (ou desmarque o intervalo).");
      }
      const vinculadas = emEdicao?.pessoas.length ?? 0;
      if (editando !== null && vinculadas > 0) {
        const ok = confirm(
          `Esta mudança vale para ${vinculadas} ${vinculadas === 1 ? "pessoa vinculada" : "pessoas vinculadas"} a "${emEdicao?.nome}". Salvar?`,
        );
        if (!ok) return false;
      }
      const { error } = await supabase.rpc("salvar_jornada", {
        p_jornadaid: editando,
        p_nome: form.nome,
        p_dias: dias,
        p_pausainicio: form.temPausa ? form.pausainicio : null,
        p_pausafim: form.temPausa ? form.pausafim : null,
        p_observacao: form.observacao || null,
        p_ativa: form.ativa,
      });
      if (error) throw error;
      return true;
    },
    onMutate: () => setErro(null),
    onError: (e) => setErro((e as Error).message),
    onSuccess: (salvou) => {
      if (!salvou) return;
      limpar();
      qc.invalidateQueries({ queryKey: ["jornadas"] });
      qc.invalidateQueries({ queryKey: ["equipe"] });
    },
  });

  const apagar = useMutation({
    mutationFn: async (j: (typeof lista)[number]) => {
      // O banco recusa de qualquer jeito (e conta também quem está inativo);
      // a tela avisa antes, com o número.
      if (j.pessoas.length > 0) {
        throw new Error(
          `A jornada "${j.nome}" tem ${j.pessoas.length} ${j.pessoas.length === 1 ? "pessoa vinculada" : "pessoas vinculadas"}. Mova-as para outra jornada (ou "sem jornada") em Equipe antes de apagar.`,
        );
      }
      if (!confirm(`Apagar a jornada "${j.nome}"?`)) return;
      const { error } = await supabase.rpc("apagar_jornada", { p_jornadaid: j.jornadaid });
      if (error) throw error;
    },
    onMutate: () => setErro(null),
    onError: (e) => setErro((e as Error).message),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["jornadas"] }),
  });

  const pessoasDaJanela = lista.find((j) => j.jornadaid === vendoPessoas);

  return (
    <div className="space-y-4">
      {!formAberto && (
        <button
          onClick={() => setFormAberto(true)}
          className="rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground"
        >
          Criar jornada
        </button>
      )}

      {formAberto && (
        <form
          onSubmit={(e) => {
            e.preventDefault();
            salvar.mutate();
          }}
          className="space-y-3 rounded-xl border border-border bg-card p-4"
        >
          <p className="text-sm font-semibold">
            {editando === null ? "Nova jornada" : `Editando "${emEdicao?.nome ?? ""}"`}
          </p>
          {editando !== null && (emEdicao?.pessoas.length ?? 0) > 0 && (
            <p className="rounded-md border border-azul px-3 py-2 text-sm text-azul">
              A mudança vale para as {emEdicao?.pessoas.length}{" "}
              {emEdicao?.pessoas.length === 1 ? "pessoa vinculada" : "pessoas vinculadas"} a esta jornada.
            </p>
          )}
          <input
            required
            placeholder='Nome (ex.: "Balcão manhã", "Fechamento")'
            value={form.nome}
            onChange={(e) => setForm({ ...form, nome: e.target.value })}
            className={`${campo} w-full`}
          />

          <div className="space-y-2">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <p className="text-sm font-medium">Entrada e saída por dia</p>
              <button
                type="button"
                onClick={repetirParaTodos}
                className="rounded-md border border-border px-3 py-1 text-xs"
              >
                Repetir para todos os dias
              </button>
            </div>
            <p className="text-xs text-muted-foreground">
              Dia desmarcado: sem horário naquele dia. Saída menor que a entrada: turno da noite (acaba no dia
              seguinte). A folga continua sendo de cada pessoa, no cadastro dela.
            </p>
            <p className="rounded-md border border-azul px-3 py-2 text-xs text-azul">
              A saída é um horário escrito, não uma conta: se você mudar a entrada, confira a saída — ela{" "}
              <strong>não acompanha a entrada sozinha</strong>. (Nas jornadas criadas a partir dos horários antigos, a
              saída que antes era calculada — entrada + 8h20 — foi escrita por extenso.)
            </p>
            {ORDEM_NA_TELA.map((n) => {
              const d = form.dias[n - 1];
              const mudar = (novo: Partial<Dia>) =>
                setForm({
                  ...form,
                  dias: form.dias.map((x, i) => (i === n - 1 ? { ...x, ...novo } : x)),
                });
              return (
                <div key={n} className="flex flex-wrap items-center gap-3 text-sm">
                  <label className="flex w-20 items-center gap-2">
                    <input type="checkbox" checked={d.ativo} onChange={(e) => mudar({ ativo: e.target.checked })} />
                    {DIAS[n - 1]}
                  </label>
                  <label className="flex items-center gap-1">
                    Entrada
                    <input
                      type="time"
                      disabled={!d.ativo}
                      value={d.entrada}
                      onChange={(e) => mudar({ entrada: e.target.value })}
                      className={`${campo} disabled:opacity-40`}
                    />
                  </label>
                  <label className="flex items-center gap-1">
                    Saída
                    <input
                      type="time"
                      disabled={!d.ativo}
                      value={d.saida}
                      onChange={(e) => mudar({ saida: e.target.value })}
                      className={`${campo} disabled:opacity-40`}
                    />
                  </label>
                  {d.ativo && d.entrada && d.saida && d.saida < d.entrada && (
                    <span className="text-xs text-muted-foreground">turno da noite</span>
                  )}
                </div>
              );
            })}
          </div>

          <div className="space-y-2 rounded-lg border border-border p-3">
            <label className="flex items-center gap-2 text-sm">
              <input
                type="checkbox"
                checked={form.temPausa}
                onChange={(e) => setForm({ ...form, temPausa: e.target.checked })}
              />
              Intervalo em que o sistema não envia nada (ex.: almoço)
            </label>
            <p className="text-xs text-muted-foreground">
              É silêncio do sistema, não marcação: ninguém registra saída nem volta. Mensagens que caírem no intervalo
              esperam ele acabar.
            </p>
            {form.temPausa && (
              <div className="flex flex-wrap gap-3 text-sm">
                <label className="flex items-center gap-1">
                  De
                  <input
                    type="time"
                    value={form.pausainicio}
                    onChange={(e) => setForm({ ...form, pausainicio: e.target.value })}
                    className={campo}
                  />
                </label>
                <label className="flex items-center gap-1">
                  até
                  <input
                    type="time"
                    value={form.pausafim}
                    onChange={(e) => setForm({ ...form, pausafim: e.target.value })}
                    className={campo}
                  />
                </label>
              </div>
            )}
          </div>

          <input
            placeholder="Observação (opcional)"
            value={form.observacao}
            onChange={(e) => setForm({ ...form, observacao: e.target.value })}
            className={`${campo} w-full`}
          />
          <label className="flex items-center gap-2 text-sm">
            <input
              type="checkbox"
              checked={form.ativa}
              onChange={(e) => setForm({ ...form, ativa: e.target.checked })}
            />
            Ativa (jornada inativa não aparece para vincular; com gente vinculada, não se desativa)
          </label>

          <div className="flex flex-wrap gap-2">
            <button
              type="submit"
              disabled={salvar.isPending}
              className="rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground disabled:opacity-60"
            >
              {salvar.isPending ? "Salvando..." : editando === null ? "Criar jornada" : "Salvar"}
            </button>
            <button type="button" onClick={limpar} className="rounded-lg border border-border px-4 py-2 text-sm">
              Cancelar
            </button>
          </div>
        </form>
      )}

      {erro && <p className="rounded-lg border border-destructive px-4 py-3 text-sm text-destructive">{erro}</p>}

      <div className="space-y-2">
        {dados.isLoading && <p className="text-muted-foreground">Carregando...</p>}
        {dados.isError && <p className="text-sm text-destructive">{(dados.error as Error).message}</p>}
        {!dados.isLoading && lista.length === 0 && (
          <p className="text-sm text-muted-foreground">Nenhuma jornada ainda.</p>
        )}
        {lista.map((j) => (
          <div
            key={j.jornadaid}
            className="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-border bg-card px-4 py-3"
          >
            <div className="min-w-0">
              <p className="font-medium">
                {j.nome}
                {!j.ativa && (
                  <span className="ml-2 rounded-md border border-border px-2 py-0.5 text-xs font-normal text-muted-foreground">
                    inativa
                  </span>
                )}
              </p>
              <p className="text-sm text-muted-foreground">
                {resumoDaJornada(j.dias, {
                  inicio: j.pausainicio,
                  fim: j.pausafim,
                })}
              </p>
              {j.observacao && <p className="text-xs text-muted-foreground">{j.observacao}</p>}
            </div>
            <div className="flex flex-wrap items-center gap-2">
              <button
                onClick={() => setVendoPessoas(j.jornadaid)}
                disabled={j.pessoas.length === 0}
                className="rounded-md border border-border px-3 py-1 text-sm disabled:opacity-60"
                title="Ver quem está nesta jornada"
              >
                {j.pessoas.length} {j.pessoas.length === 1 ? "pessoa" : "pessoas"}
              </button>
              <button onClick={() => editar(j)} className="rounded-md border border-border px-3 py-1 text-sm">
                Editar
              </button>
              <button onClick={() => apagar.mutate(j)} className="rounded-md border border-border px-3 py-1 text-sm">
                Apagar
              </button>
            </div>
          </div>
        ))}
      </div>

      {pessoasDaJanela && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4"
          onClick={() => setVendoPessoas(null)}
        >
          <div
            className="max-h-[80vh] w-full max-w-md space-y-3 overflow-y-auto rounded-2xl bg-card p-5"
            onClick={(e) => e.stopPropagation()}
          >
            <p className="text-lg font-semibold">
              {pessoasDaJanela.nome}: {pessoasDaJanela.pessoas.length}{" "}
              {pessoasDaJanela.pessoas.length === 1 ? "pessoa" : "pessoas"}
            </p>
            <ul className="space-y-1 text-sm">
              {[...pessoasDaJanela.pessoas]
                .sort((a, b) => a.nome.localeCompare(b.nome, "pt-BR"))
                .map((p) => (
                  <li key={p.nome}>
                    {p.nome} <span className="text-muted-foreground">· {p.lojas.join(", ") || "sem loja"}</span>
                  </li>
                ))}
            </ul>
            <button onClick={() => setVendoPessoas(null)} className="rounded-lg border border-border px-4 py-2 text-sm">
              Fechar
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
