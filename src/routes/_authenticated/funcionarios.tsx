import { createFileRoute } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import {
  criarAcessoColaborador,
  desativarColaborador,
  emitirFolhasDeAcesso,
  redefinirAcessoColaborador,
  trocarCpfDoColaborador,
} from "@/servidor/acesso";
import { AvisoSemLoja, useLojaAtiva } from "@/lojas/loja-ativa";
import { Pontos } from "@/ui/Pontos";
import { IconeTelegram, JanelaConvite, useDesligarTelegram, useVinculosTelegram } from "@/telegram/Telegram";
import { Pagina } from "@/ui/Pagina";
import { useHojeDaConta } from "@/ui/hoje";
import { dataHoraBr } from "@/rh/datas";
import { EscolherDaLista } from "@/ui/EscolherDaLista";

export const Route = createFileRoute("/_authenticated/funcionarios")({
  component: Funcionarios,
});

// Mesma codificação do sistema antigo (legado/database.py):
// 0 = sem folga fixa, 1 = domingo ... 7 = sábado.
const DIAS_FOLGA = [
  { valor: 0, nome: "Sem folga fixa" },
  { valor: 1, nome: "Domingo" },
  { valor: 2, nome: "Segunda-feira" },
  { valor: 3, nome: "Terça-feira" },
  { valor: 4, nome: "Quarta-feira" },
  { valor: 5, nome: "Quinta-feira" },
  { valor: 6, nome: "Sexta-feira" },
  { valor: 7, nome: "Sábado" },
];

const FORM_VAZIO = {
  nomecompleto: "",
  cpf: "",
  cargo: "",
  setor: "",
  telefonewhatsapp: "",
  diadefolga: 0,
};

type SituacaoAcesso = {
  temacesso: boolean; nuncaentrou: boolean; semsenha: boolean; sempin: boolean;
  codigopendente: boolean; codigoexpiraem: string | null; redefinidoem: string | null;
  codigogeradoem: string | null; codigogeradopor: string | null; codigoreimprimivel: boolean;
  folhaemitidaem: string | null; folhaemitidapor: string | null; folhas: number;
};

/** Já fez o primeiro acesso: tem senha ou PIN. Folha nova, para ela, redefine o acesso. */
const jaEntrou = (a: SituacaoAcesso | undefined) => !!a?.temacesso && (!a.semsenha || !a.sempin);

/** "Código gerado em 27/09/2026 09:40 por x@y · folha impressa 2× (a última em … por …)". */
function registroDoAcesso(a: SituacaoAcesso | undefined) {
  if (!a?.temacesso) return null;
  const partes: string[] = [];
  if (a.codigopendente && a.codigogeradoem) {
    partes.push(`Código gerado em ${dataHoraBr(a.codigogeradoem)}${a.codigogeradopor ? ` por ${a.codigogeradopor}` : ""}`);
    if (!a.codigoreimprimivel) partes.push("código anterior à folha em PDF: o PDF gera um novo");
  }
  if (a.folhas > 0 && a.folhaemitidaem) {
    partes.push(
      `folha impressa ${a.folhas}× (a última em ${dataHoraBr(a.folhaemitidaem)}${a.folhaemitidapor ? ` por ${a.folhaemitidapor}` : ""})`,
    );
  }
  return partes.length ? partes.join(" · ") : null;
}

/** Frase curta sobre o acesso ao aplicativo, para o gestor saber o que falta. */
function situacaoDoAcesso(a: SituacaoAcesso | undefined) {
  if (!a?.temacesso) return "Sem acesso ao app";
  if (a.semsenha) {
    return a.codigopendente
      ? "Aguardando o 1º acesso: a pessoa entra com o CPF e o código (não há senha provisória)"
      : "Sem senha e sem código válido: gere um código novo";
  }
  if (a.sempin) return "Entrou, falta escolher o PIN do tablet";
  return "Acesso ativo";
}

/** CPF só aparece inteiro para quem edita; na lista fica escondido. */
function cpfMascarado(cpf: string | null) {
  const n = (cpf ?? "").replace(/\D/g, "");
  if (n.length !== 11) return null;
  return `***.${n.slice(3, 6)}.${n.slice(6, 9)}-**`;
}

const campo =
  "rounded-lg border border-border bg-background px-3 py-2 text-sm placeholder:text-muted-foreground";

function Funcionarios() {
  const qc = useQueryClient();
  const { lojas, lojaAtiva, carregando: carregandoLojas } = useLojaAtiva();

  const [form, setForm] = useState(FORM_VAZIO);
  const [lojasEscolhidas, setLojasEscolhidas] = useState<number[]>([]);
  // Lojas em que a pessoa pode aprovar e recusar entregas pelo Telegram.
  const [validadorEm, setValidadorEm] = useState<number[]>([]);
  const [convite, setConvite] = useState<{ funcionarioid: number; nome: string } | null>(null);
  const vinculos = useVinculosTelegram();
  const desligar = useDesligarTelegram();
  const [editando, setEditando] = useState<number | null>(null);
  const [mostrarInativos, setMostrarInativos] = useState(false);
  const [filtroLoja, setFiltroLoja] = useState<number | "todas">("todas");
  // Pessoas marcadas nas caixinhas: PDF de acesso e jornada em lote.
  const [selecionados, setSelecionados] = useState<number[]>([]);
  // A jornada escolhida para o lote (undefined = ainda não escolheu; null = sem jornada).
  const [jornadaDoLote, setJornadaDoLote] = useState<number | null | undefined>(undefined);
  const [vinculandoJornada, setVinculandoJornada] = useState<number | null>(null);

  const equipe = useQuery({
    queryKey: ["equipe"],
    queryFn: async () => {
      // As duas não dependem uma da outra: vão juntas. Em fila, eram duas
      // idas ao servidor a cada abertura da tela (medido em 24/09/2026).
      const [{ data: pessoas, error }, { data: vinculos, error: erroVinculos }] = await Promise.all([
        // O gerente: quem tem uma loja em comum com ele (CPF e telefone, só de
        // quem está inteiro nas lojas dele), e só as lojas dele de cada um.
        supabase.rpc("equipe_da_tela"),
        supabase.rpc("vinculos_da_tela"),
      ]);
      if (error) throw error;
      if (erroVinculos) throw erroVinculos;

      const porFuncionario = new Map<number, number[]>();
      const validadorPor = new Map<number, number[]>();
      for (const v of vinculos ?? []) {
        if (!v.ativo) continue;
        porFuncionario.set(v.funcionarioid, [
          ...(porFuncionario.get(v.funcionarioid) ?? []),
          v.lojaid,
        ]);
        if (v.validador) {
          validadorPor.set(v.funcionarioid, [...(validadorPor.get(v.funcionarioid) ?? []), v.lojaid]);
        }
      }

      return (pessoas ?? []).map((p) => ({
        ...p,
        lojas: porFuncionario.get(p.funcionarioid) ?? [],
        validadorEm: validadorPor.get(p.funcionarioid) ?? [],
      }));
    },
  });

  function limparFormulario() {
    setForm(FORM_VAZIO);
    setLojasEscolhidas(lojaAtiva ? [lojaAtiva] : []);
    setValidadorEm([]);
    setEditando(null);
  }

  const salvar = useMutation({
    mutationFn: async () => {
      const dados = {
        nomecompleto: form.nomecompleto.trim(),
        cpf: form.cpf.trim() || null,
        cargo: form.cargo.trim() || null,
        setor: form.setor.trim() || null,
        telefonewhatsapp: form.telefonewhatsapp.trim() || null,
        diadefolga: form.diadefolga,
      };

      // Uma função só grava a pessoa e as lojas dela (sair de uma loja é
      // desativar o vínculo, nunca apagar). O banco confere as bordas.
      const { error } = await supabase.rpc("salvar_pessoa", {
        p_funcionarioid: editando,
        p_nomecompleto: dados.nomecompleto,
        p_cpf: dados.cpf,
        p_cargo: dados.cargo,
        p_setor: dados.setor,
        p_telefone: dados.telefonewhatsapp,
        p_diadefolga: dados.diadefolga,
        p_lojas: lojasEscolhidas,
        p_validador: validadorEm,
      });
      if (error) throw error;
    },
    onSuccess: () => {
      limparFormulario();
      qc.invalidateQueries({ queryKey: ["equipe"] });
    },
  });

  // As jornadas da conta (a página Jornada cadastra). Só as ATIVAS aparecem
  // para vincular; o nome de todas aparece no cartão.
  const jornadas = useQuery({
    queryKey: ["jornadas-para-vincular"],
    queryFn: async () => {
      const { data, error } = await supabase.rpc("jornadas_da_conta");
      if (error) throw error;
      return data ?? [];
    },
  });
  const nomeDaJornada = (id: number | null) => jornadas.data?.find((j) => j.jornadaid === id)?.nome;
  const jornadasAtivas = (jornadas.data ?? []).filter((j) => j.ativa).map((j) => ({ id: j.jornadaid, nome: j.nome }));

  // Vincular uma ou várias pessoas a uma jornada (null = sem jornada).
  const vincularJornada = useMutation({
    mutationFn: async ({ ids, jornadaid }: { ids: number[]; jornadaid: number | null }) => {
      if (ids.length === 0) throw new Error("Marque pelo menos uma pessoa.");
      const { error } = await supabase.rpc("vincular_jornada", { p_funcionarios: ids, p_jornadaid: jornadaid });
      if (error) throw error;
    },
    onSuccess: (_r, { ids }) => {
      if (ids.length > 1) setSelecionados([]);
      setJornadaDoLote(undefined);
      setVinculandoJornada(null);
      qc.invalidateQueries({ queryKey: ["equipe"] });
      qc.invalidateQueries({ queryKey: ["jornadas"] });
    },
  });

  // Situação do acesso ao app (nunca traz CPF nem PIN: só as marcas).
  const acessos = useQuery({
    queryKey: ["acessos-equipe"],
    queryFn: async () => {
      const { data, error } = await supabase.rpc("situacao_dos_acessos");
      if (error) throw error;
      const mapa = new Map<number, SituacaoAcesso>();
      for (const a of data ?? []) mapa.set(a.funcionarioid, a);
      return mapa;
    },
  });

  const [codigoNovo, setCodigoNovo] = useState<{ nome: string; codigo: string; dias: number } | null>(null);
  // Erro aparece NA LINHA de quem foi clicado: antes ia para o topo da tela e
  // quem clicava lá embaixo não via nada acontecer.
  const [erroDoAcesso, setErroDoAcesso] = useState<{ funcionarioid: number; texto: string } | null>(null);

  function aoGerarCodigo(r: { nome: string; codigo: string; dias: number }) {
    setErroDoAcesso(null);
    setCodigoNovo(r);
    qc.invalidateQueries({ queryKey: ["acessos-equipe"] });
    qc.invalidateQueries({ queryKey: ["equipe"] });
  }

  const criarAcesso = useMutation({
    onError: (e, funcionarioid) => setErroDoAcesso({ funcionarioid, texto: (e as Error).message }),
    mutationFn: (funcionarioid: number) => criarAcessoColaborador({ data: { funcionarioid } }),
    onSuccess: aoGerarCodigo,
  });

  const redefinirAcesso = useMutation({
    onError: (e, funcionarioid) => setErroDoAcesso({ funcionarioid, texto: (e as Error).message }),
    mutationFn: (funcionarioid: number) => redefinirAcessoColaborador({ data: { funcionarioid } }),
    onSuccess: aoGerarCodigo,
  });

  // A FOLHA DE ACESSO (PDF). O servidor decide o que acontece com cada
  // pessoa; quando algo vai deixar de valer (um código, uma senha), ele devolve
  // os avisos ANTES, e só executa depois do "OK".
  const hojeConta = useHojeDaConta();
  const [erroDoLote, setErroDoLote] = useState<string | null>(null);
  type ModoDaFolha = "imprimir" | "codigonovo" | "redefinir";
  const folha = useMutation({
    mutationFn: async ({ ids, modo }: { ids: number[]; modo: ModoDaFolha }) => {
      let r = await emitirFolhasDeAcesso({ data: { funcionarioids: ids, modo } });
      if (r.precisaConfirmar) {
        if (!confirm(`${r.avisos.join("\n\n")}\n\nContinuar?`)) return null;
        r = await emitirFolhasDeAcesso({ data: { funcionarioids: ids, modo, aceito: true } });
      }
      if (r.folhas.length > 0) {
        // O gerador de PDF só é baixado quando alguém pede um.
        const { pdfFolhasDeAcesso, nomeDaFolha } = await import("@/rh/pdf");
        const dia = hojeConta.data?.hoje ?? r.folhas[0].emitidaem.slice(0, 10);
        await pdfFolhasDeAcesso(r.folhas, nomeDaFolha(r.folhas, dia));
      }
      return r;
    },
    onMutate: () => {
      setErroDoAcesso(null);
      setErroDoLote(null);
    },
    onError: (e, { ids }) => {
      if (ids.length === 1) setErroDoAcesso({ funcionarioid: ids[0], texto: (e as Error).message });
      else setErroDoLote((e as Error).message);
    },
    onSuccess: (r) => {
      qc.invalidateQueries({ queryKey: ["acessos-equipe"] });
      qc.invalidateQueries({ queryKey: ["equipe"] });
      if (!r) return;
      if (r.folhas.length === 1) setCodigoNovo({ nome: r.folhas[0].nome, codigo: r.folhas[0].codigo, dias: 7 });
      if (r.deFora.length > 0) {
        alert(`Ficaram de fora do PDF:\n${r.deFora.map((d) => `• ${d.nome}: ${d.motivo}`).join("\n")}`);
      }
    },
  });

  const trocarCpf = useMutation({
    mutationFn: ({ funcionarioid, cpf }: { funcionarioid: number; cpf: string }) =>
      trocarCpfDoColaborador({ data: { funcionarioid, cpf } }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["equipe"] });
      qc.invalidateQueries({ queryKey: ["acessos-equipe"] });
    },
  });

  // PIN do tablet bloqueado por tentativas (29/09/2026): a trava é de cada
  // pessoa, 1, 3 e no máximo 10 minutos. O gestor libera na hora, e o banco
  // guarda quem liberou e quando.
  const travasPin = useQuery({
    queryKey: ["travas-pin"],
    refetchInterval: 30_000,
    queryFn: async () => {
      const { data, error } = await supabase.rpc("travas_do_pin");
      if (error) throw error;
      return new Map((data ?? []).map((t) => [t.funcionarioid, t]));
    },
  });
  const liberarPin = useMutation({
    onError: (e, funcionarioid) => setErroDoAcesso({ funcionarioid, texto: (e as Error).message }),
    mutationFn: async (funcionarioid: number) => {
      const { error } = await supabase.rpc("liberar_pin", { p_funcionarioid: funcionarioid });
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ["travas-pin"] }),
  });

  // Desativar passa pelo servidor: além de marcar no cadastro, ele derruba o
  // login da pessoa no mesmo movimento (o banco apaga senha e PIN).
  const alternarAtivo = useMutation({
    mutationFn: ({ funcionarioid, ativo }: { funcionarioid: number; ativo: boolean }) =>
      desativarColaborador({ data: { funcionarioid, ativo } }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["equipe"] });
      qc.invalidateQueries({ queryKey: ["acessos-equipe"] });
    },
  });

  if (carregandoLojas) {
    return (
      <Pagina>
        <p className="text-muted-foreground">Carregando...</p>
      </Pagina>
    );
  }

  if (lojas.length === 0) {
    return (
      <Pagina titulo="Equipe">
        <AvisoSemLoja />
      </Pagina>
    );
  }

  const todos = equipe.data ?? [];
  const porLoja =
    filtroLoja === "todas" ? todos : todos.filter((f) => f.lojas.includes(filtroLoja));
  const visiveis = mostrarInativos ? porLoja : porLoja.filter((f) => f.ativo);
  const inativos = porLoja.length - porLoja.filter((f) => f.ativo).length;
  const nomeDaLoja = (id: number) => lojas.find((l) => l.lojaid === id)?.nome ?? `Loja ${id}`;
  const telegramDe = (id: number) =>
    (vinculos.data ?? []).find((v) => v.tipo === "pessoa" && v.funcionarioid === id);

  return (
    <Pagina
      titulo="Equipe"
      acoes={
        <p className="text-sm text-muted-foreground">
          {porLoja.filter((f) => f.ativo).length} ativos
          {inativos > 0 && ` · ${inativos} inativos`}
        </p>
      }
    >
      {codigoNovo && (
        <div className="space-y-2 rounded-xl border-2 border-primary bg-card p-4">
          <p className="font-semibold">Código de primeiro acesso — {codigoNovo.nome}</p>
          <p className="font-mono text-3xl tracking-widest">{codigoNovo.codigo}</p>
          <p className="text-sm">
            <strong>Não existe senha provisória.</strong> Este código é a entrada: com ele a pessoa
            cria a própria senha. Vale {codigoNovo.dias} dias e serve uma vez só.
          </p>
          <p className="text-sm text-muted-foreground">
            Entregue à pessoa, junto com o link da equipe (menu <strong>Lojas e links da TV</strong>).
            No celular dela:
            abrir o link → aba <strong>1º acesso</strong> → CPF + este código → criar senha → escolher
            o PIN → aceitar a política.
          </p>
          <p className="text-sm text-destructive">Anote agora: o código não aparece de novo.</p>
          <button onClick={() => setCodigoNovo(null)} className="rounded-md border border-border px-3 py-1 text-sm">
            Anotei
          </button>
        </div>
      )}

      <form
        onSubmit={(e) => {
          e.preventDefault();
          salvar.mutate();
        }}
        className="space-y-3 rounded-xl border border-border bg-card p-4"
      >
        <p className="text-sm font-semibold">
          {editando === null ? "Adicionar funcionário" : "Editando funcionário"}
        </p>

        <div className="grid gap-3 md:grid-cols-3">
          <input
            required
            placeholder="Nome completo"
            value={form.nomecompleto}
            onChange={(e) => setForm({ ...form, nomecompleto: e.target.value })}
            className={`${campo} md:col-span-2`}
          />
          <input
            placeholder="Cargo"
            value={form.cargo}
            onChange={(e) => setForm({ ...form, cargo: e.target.value })}
            className={campo}
          />
          <input
            placeholder="CPF (só o gestor vê)"
            inputMode="numeric"
            value={form.cpf}
            onChange={(e) => setForm({ ...form, cpf: e.target.value })}
            className={campo}
          />
          <input
            placeholder="Setor"
            value={form.setor}
            onChange={(e) => setForm({ ...form, setor: e.target.value })}
            className={campo}
          />
          <input
            placeholder="WhatsApp"
            value={form.telefonewhatsapp}
            onChange={(e) => setForm({ ...form, telefonewhatsapp: e.target.value })}
            className={campo}
          />
          <select
            value={form.diadefolga}
            onChange={(e) => setForm({ ...form, diadefolga: Number(e.target.value) })}
            className={campo}
          >
            {DIAS_FOLGA.map((d) => (
              <option key={d.valor} value={d.valor}>
                {d.nome}
              </option>
            ))}
          </select>
        </div>

        <fieldset className="space-y-2">
          <legend className="text-sm text-muted-foreground">
            Trabalha em quais lojas? (pode marcar mais de uma)
          </legend>
          <div className="flex flex-wrap gap-3">
            {lojas.map((l) => (
              <label key={l.lojaid} className="flex items-center gap-2 text-sm">
                <input
                  type="checkbox"
                  checked={lojasEscolhidas.includes(l.lojaid)}
                  onChange={(e) =>
                    setLojasEscolhidas((atual) =>
                      e.target.checked
                        ? [...atual, l.lojaid]
                        : atual.filter((id) => id !== l.lojaid),
                    )
                  }
                />
                {l.nome}
              </label>
            ))}
          </div>
          {lojasEscolhidas.length > 0 && (
            <div className="space-y-1 pt-1">
              <p className="text-sm text-muted-foreground">
                Pode aprovar e recusar entregas pelo Telegram (no grupo de gestão da loja)?
              </p>
              <div className="flex flex-wrap gap-3">
                {lojas
                  .filter((l) => lojasEscolhidas.includes(l.lojaid))
                  .map((l) => (
                    <label key={l.lojaid} className="flex items-center gap-2 text-sm">
                      <input
                        type="checkbox"
                        checked={validadorEm.includes(l.lojaid)}
                        onChange={(e) =>
                          setValidadorEm((atual) =>
                            e.target.checked ? [...atual, l.lojaid] : atual.filter((id) => id !== l.lojaid),
                          )
                        }
                      />
                      Validador em {l.nome}
                    </label>
                  ))}
              </div>
            </div>
          )}
          {lojasEscolhidas.length === 0 && (
            <p className="text-xs text-muted-foreground">
              Sem loja marcada, a pessoa fica cadastrada mas não pode receber tarefas.
            </p>
          )}
        </fieldset>

        <div className="flex flex-wrap items-center gap-2">
          <button
            type="submit"
            disabled={salvar.isPending}
            className="rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground disabled:opacity-60"
          >
            {salvar.isPending ? "Salvando..." : editando === null ? "Adicionar" : "Salvar"}
          </button>
          {editando !== null && (
            <button
              type="button"
              onClick={limparFormulario}
              className="rounded-lg border border-border px-4 py-2 text-sm"
            >
              Cancelar
            </button>
          )}
        </div>

        {salvar.isError && (
          <p className="text-sm text-destructive">
            Não foi possível salvar: {(salvar.error as Error).message}
          </p>
        )}
      </form>

      <div className="flex flex-wrap items-center gap-4">
        {lojas.length > 1 && (
          <label className="flex items-center gap-2 text-sm text-muted-foreground">
            Loja:
            <select
              value={filtroLoja}
              onChange={(e) =>
                setFiltroLoja(e.target.value === "todas" ? "todas" : Number(e.target.value))
              }
              className={campo}
            >
              <option value="todas">Todas as lojas</option>
              {lojas.map((l) => (
                <option key={l.lojaid} value={l.lojaid}>
                  {l.nome}
                </option>
              ))}
            </select>
          </label>
        )}

        {inativos > 0 && (
          <label className="flex items-center gap-2 text-sm text-muted-foreground">
            <input
              type="checkbox"
              checked={mostrarInativos}
              onChange={(e) => setMostrarInativos(e.target.checked)}
            />
            Mostrar também os inativos
          </label>
        )}
      </div>

      <div className="flex flex-wrap items-center gap-2 text-sm">
        <button
          onClick={() => setSelecionados(visiveis.filter((f) => f.ativo).map((f) => f.funcionarioid))}
          className="rounded-lg border border-border px-3 py-1.5"
        >
          Marcar todos
        </button>
        {selecionados.length > 0 && (
          <button onClick={() => setSelecionados([])} className="rounded-lg border border-border px-3 py-1.5">
            Limpar
          </button>
        )}
        <span className="text-xs text-muted-foreground">
          Marque pessoas para gerar o PDF de acesso ou vincular uma jornada de uma vez.
        </span>
      </div>

      {selecionados.length > 0 && (
        <section className="flex flex-wrap items-center gap-3 rounded-lg border border-border bg-card px-4 py-3">
          <p className="text-sm">
            {selecionados.length} {selecionados.length === 1 ? "pessoa marcada" : "pessoas marcadas"}
          </p>
          <button
            onClick={() => folha.mutate({ ids: selecionados, modo: "imprimir" })}
            disabled={folha.isPending}
            className="rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground disabled:opacity-50"
          >
            {folha.isPending ? "Gerando..." : "PDF de acesso (uma página por pessoa)"}
          </button>
          <p className="w-full text-xs text-muted-foreground">
            Quem já tem código recebe o mesmo; quem não tem acesso ganha o acesso agora. Quem já entrou no app fica
            de fora: a folha dessas pessoas redefine o acesso e é feita no cartão de cada uma.
          </p>
          {erroDoLote && <p className="w-full text-sm text-destructive">{erroDoLote}</p>}
          <div className="flex w-full flex-wrap items-center gap-2 border-t border-border pt-3">
            <div className="w-64">
              <EscolherDaLista
                itens={jornadasAtivas}
                valor={jornadaDoLote ?? null}
                mudar={(id) => setJornadaDoLote(id)}
                rotulo="Jornada"
                semItem={jornadaDoLote === undefined ? "escolha" : "sem jornada"}
                buscaTexto="Buscar jornada por parte do nome"
              />
            </div>
            <button
              onClick={() => vincularJornada.mutate({ ids: selecionados, jornadaid: jornadaDoLote ?? null })}
              disabled={vincularJornada.isPending || jornadaDoLote === undefined}
              className="rounded-lg border border-border px-4 py-2 text-sm font-semibold disabled:opacity-50"
            >
              Vincular a {selecionados.length} {selecionados.length === 1 ? "pessoa" : "pessoas"}
            </button>
            {vincularJornada.isError && (
              <p className="w-full text-sm text-destructive">{(vincularJornada.error as Error).message}</p>
            )}
          </div>
        </section>
      )}

      <div className="space-y-2">
        {equipe.isLoading && <p className="text-muted-foreground">Carregando...</p>}
        {equipe.isError && (
          <p className="text-sm text-destructive">
            Não foi possível carregar a equipe: {(equipe.error as Error).message}
          </p>
        )}

        {visiveis.map((f) => (
          <div
            key={f.funcionarioid}
            className="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-border bg-card px-4 py-3"
          >
            <div className="flex min-w-0 items-start gap-3">
              <input
                type="checkbox"
                className="mt-1.5"
                aria-label={`Marcar ${f.nomecompleto}`}
                checked={selecionados.includes(f.funcionarioid)}
                onChange={(e) =>
                  setSelecionados((atual) =>
                    e.target.checked ? [...atual, f.funcionarioid] : atual.filter((id) => id !== f.funcionarioid),
                  )
                }
              />
              <div className="min-w-0">
              <p className="flex flex-wrap items-center gap-2 font-medium">
                {f.nomecompleto}
                {telegramDe(f.funcionarioid) &&
                  (telegramDe(f.funcionarioid)!.bloqueadoem ? (
                    <span
                      className="rounded-md border border-destructive px-1.5 py-0.5 text-xs font-medium text-destructive"
                      title="A pessoa bloqueou o bot no Telegram. Peça para ela desbloquear e mandar uma mensagem ao bot."
                    >
                      Bot bloqueado
                    </span>
                  ) : (
                    <IconeTelegram desde={telegramDe(f.funcionarioid)!.vinculadoem} />
                  ))}
                {!f.ativo && (
                  <span className="ml-2 rounded-md border border-border px-2 py-0.5 text-xs font-normal text-muted-foreground">
                    Inativo
                  </span>
                )}
              </p>
              <p className="text-sm text-muted-foreground">
                {[f.cargo, f.setor].filter(Boolean).join(" · ") || "Sem cargo nem setor"}
                {f.diadefolga > 0 &&
                  ` · Folga: ${DIAS_FOLGA.find((d) => d.valor === f.diadefolga)?.nome}`}
              </p>
              <p className="text-sm text-muted-foreground">
                {f.lojas.length > 0
                  ? f.lojas.map(nomeDaLoja).join(" · ")
                  : "Nenhuma loja"}
              </p>
              {f.validadorEm.length > 0 && (
                <p className="text-xs text-muted-foreground">
                  Aprova no Telegram: {f.validadorEm.map(nomeDaLoja).join(" · ")}
                </p>
              )}
              <p className="text-xs text-muted-foreground">
                {f.jornadaid
                  ? `Jornada: ${nomeDaJornada(f.jornadaid) ?? "…"}`
                  : "Sem jornada: não recebe as mensagens do dia"}
              </p>
              <p className="text-xs text-muted-foreground">
                {cpfMascarado(f.cpf) ? `CPF ${cpfMascarado(f.cpf)}` : "Sem CPF cadastrado"} ·{" "}
                {situacaoDoAcesso(acessos.data?.get(f.funcionarioid))}
              </p>
              {registroDoAcesso(acessos.data?.get(f.funcionarioid)) && (
                <p className="text-xs text-muted-foreground">{registroDoAcesso(acessos.data?.get(f.funcionarioid))}</p>
              )}
              {erroDoAcesso?.funcionarioid === f.funcionarioid && (
                <p className="mt-1 rounded-md border border-destructive px-2 py-1 text-xs text-destructive">
                  {erroDoAcesso.texto}
                </p>
              )}
              </div>
            </div>

            <div className="flex flex-wrap items-center gap-3 sm:justify-end">
              {f.saldopontos < 0 ? (
                <span
                  className="rounded-md border border-destructive px-2 py-0.5 text-sm font-semibold text-destructive"
                  title="Saldo negativo: a pessoa gastou pontos que depois foram estornados."
                >
                  {f.saldopontos} pontos (negativo)
                </span>
              ) : (
                <span className="text-sm text-muted-foreground">
                  <Pontos valor={f.saldopontos} />
                </span>
              )}
              <button
                onClick={() => {
                  setEditando(f.funcionarioid);
                  setForm({
                    nomecompleto: f.nomecompleto,
                    cpf: f.cpf ?? "",
                    cargo: f.cargo ?? "",
                    setor: f.setor ?? "",
                    telefonewhatsapp: f.telefonewhatsapp ?? "",
                    diadefolga: f.diadefolga,
                  });
                  setLojasEscolhidas(f.lojas);
                  setValidadorEm(f.validadorEm);
                }}
                className="rounded-md border border-border px-3 py-1 text-sm"
              >
                Editar
              </button>
              {f.ativo && (
                <div className="relative">
                  <button
                    onClick={() => setVinculandoJornada(vinculandoJornada === f.funcionarioid ? null : f.funcionarioid)}
                    className="rounded-md border border-border px-3 py-1 text-sm"
                  >
                    Vincular jornada
                  </button>
                  {vinculandoJornada === f.funcionarioid && (
                    <div className="absolute right-0 z-30 mt-1 w-64">
                      <EscolherDaLista
                        itens={jornadasAtivas}
                        valor={f.jornadaid}
                        mudar={(id) => vincularJornada.mutate({ ids: [f.funcionarioid], jornadaid: id })}
                        rotulo="Jornada"
                        semItem="sem jornada"
                        buscaTexto="Buscar jornada por parte do nome"
                        abertoDeInicio
                      />
                    </div>
                  )}
                </div>
              )}
              {codigoNovo && codigoNovo.nome === f.nomecompleto && (
                <span className="rounded-md border border-primary px-2 py-1 font-mono text-sm">
                  {codigoNovo.codigo}
                </span>
              )}
              {f.ativo && f.cpf && !acessos.data?.get(f.funcionarioid)?.temacesso && (
                <button
                  onClick={() => criarAcesso.mutate(f.funcionarioid)}
                  disabled={criarAcesso.isPending}
                  className="rounded-md border border-border px-3 py-1 text-sm disabled:opacity-50"
                >
                  {criarAcesso.isPending ? "Criando..." : "Criar acesso"}
                </button>
              )}
              {f.ativo && f.cpf && (
                <button
                  onClick={() =>
                    folha.mutate({
                      ids: [f.funcionarioid],
                      modo: jaEntrou(acessos.data?.get(f.funcionarioid)) ? "redefinir" : "imprimir",
                    })
                  }
                  disabled={folha.isPending}
                  title={
                    jaEntrou(acessos.data?.get(f.funcionarioid))
                      ? "Esta pessoa já entrou no app: a folha nova REDEFINE o acesso (a tela avisa antes)."
                      : "Folha de instruções de acesso. Quem já tem código recebe o mesmo."
                  }
                  className="rounded-md border border-border px-3 py-1 text-sm disabled:opacity-50"
                >
                  PDF
                </button>
              )}
              {acessos.data?.get(f.funcionarioid)?.temacesso && !jaEntrou(acessos.data?.get(f.funcionarioid)) && (
                <button
                  onClick={() => folha.mutate({ ids: [f.funcionarioid], modo: "codigonovo" })}
                  disabled={folha.isPending}
                  className="rounded-md border border-border px-3 py-1 text-sm disabled:opacity-50"
                >
                  Gerar código novo
                </button>
              )}
              {acessos.data?.get(f.funcionarioid)?.temacesso && !acessos.data?.get(f.funcionarioid)?.semsenha && (
                <button
                  onClick={() => {
                    if (confirm(`Redefinir o acesso de ${f.nomecompleto}? A senha e o PIN são apagados, quem estiver usando é desconectado e sai um código novo para ela entrar.`)) {
                      redefinirAcesso.mutate(f.funcionarioid);
                    }
                  }}
                  disabled={redefinirAcesso.isPending}
                  className="rounded-md border border-border px-3 py-1 text-sm"
                >
                  Redefinir acesso
                </button>
              )}
              {acessos.data?.get(f.funcionarioid)?.temacesso && (
                <button
                  onClick={() => {
                    const novo = prompt(`Novo CPF de ${f.nomecompleto} (o login muda junto):`, f.cpf ?? "");
                    if (novo) trocarCpf.mutate({ funcionarioid: f.funcionarioid, cpf: novo });
                  }}
                  disabled={trocarCpf.isPending}
                  className="rounded-md border border-border px-3 py-1 text-sm"
                >
                  Trocar CPF
                </button>
              )}
              {travasPin.data?.get(f.funcionarioid) && (
                <span className="flex items-center gap-2">
                  <span className="text-sm text-destructive">
                    {travasPin.data.get(f.funcionarioid)!.minutosfaltam > 0
                      ? `PIN bloqueado por mais ${travasPin.data.get(f.funcionarioid)!.minutosfaltam} min`
                      : `Errou o PIN ${travasPin.data.get(f.funcionarioid)!.erros}× seguidas`}
                  </span>
                  <button
                    onClick={() => liberarPin.mutate(f.funcionarioid)}
                    disabled={liberarPin.isPending}
                    className="rounded-md border border-border px-3 py-1 text-sm disabled:opacity-50"
                  >
                    Liberar PIN agora
                  </button>
                </span>
              )}
              <button
                onClick={() =>
                  alternarAtivo.mutate({ funcionarioid: f.funcionarioid, ativo: !f.ativo })
                }
                className="rounded-md border border-border px-3 py-1 text-sm"
              >
                {f.ativo ? "Desativar" : "Reativar"}
              </button>
              {telegramDe(f.funcionarioid) ? (
                <button
                  onClick={() => {
                    if (confirm(`Desligar o Telegram de ${f.nomecompleto}? A pessoa para de receber avisos e de usar o bot até receber um novo convite.`)) {
                      desligar.mutate(telegramDe(f.funcionarioid)!.vinculoid);
                    }
                  }}
                  disabled={desligar.isPending}
                  className="rounded-md border border-border px-3 py-1 text-sm"
                >
                  Desligar Telegram
                </button>
              ) : (
                f.ativo && (
                  <button
                    onClick={() => setConvite({ funcionarioid: f.funcionarioid, nome: f.nomecompleto })}
                    className="rounded-md border border-border px-3 py-1 text-sm"
                  >
                    Convite do Telegram
                  </button>
                )
              )}
            </div>
          </div>
        ))}

        {desligar.isError && (
          <p className="text-sm text-destructive">
            Não foi possível desligar o Telegram: {(desligar.error as Error).message}
          </p>
        )}

        {!equipe.isLoading && visiveis.length === 0 && (
          <p className="text-sm text-muted-foreground">
            {todos.length === 0
              ? "Nenhum funcionário cadastrado ainda. Use o formulário acima para começar."
              : "Nenhum funcionário ativo nesta loja."}
          </p>
        )}
      </div>

      {convite && (
        <JanelaConvite
          titulo={`Convite do Telegram: ${convite.nome}`}
          modo="link"
          gerar={() => gerarConvite(convite.funcionarioid)}
          aoFechar={() => setConvite(null)}
        />
      )}
    </Pagina>
  );
}

async function gerarConvite(funcionarioid: number) {
  const { data, error } = await supabase.rpc("criar_convite_telegram", { p_funcionarioid: funcionarioid });
  if (error) throw error;
  return data as string;
}
