import { createFileRoute } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import {
  criarAcessoColaborador,
  desativarColaborador,
  gerarCodigoDeAcesso,
  redefinirAcessoColaborador,
  trocarCpfDoColaborador,
} from "@/servidor/acesso";
import { AvisoSemLoja, useLojaAtiva } from "@/lojas/loja-ativa";
import { Pontos } from "@/ui/Pontos";
import { IconeTelegram, JanelaConvite, useDesligarTelegram, useVinculosTelegram } from "@/telegram/Telegram";
import { Pagina } from "@/ui/Pagina";

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
};

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
  // Horário da jornada: dá para marcar várias pessoas e aplicar de uma vez.
  const [selecionados, setSelecionados] = useState<number[]>([]);
  const [horaEntrada, setHoraEntrada] = useState("");
  const [horaSaida, setHoraSaida] = useState("");

  const equipe = useQuery({
    queryKey: ["equipe"],
    queryFn: async () => {
      // As duas não dependem uma da outra: vão juntas. Em fila, eram duas
      // idas ao servidor a cada abertura da tela (medido em 24/09/2026).
      const [{ data: pessoas, error }, { data: vinculos, error: erroVinculos }] = await Promise.all([
        supabase
          .from("funcionarios")
          .select(
            "funcionarioid, nomecompleto, cpf, cargo, setor, telefonewhatsapp, diadefolga, saldopontos, ativo, horarionotificacao, horariosaida",
          )
          .order("nomecompleto"),
        supabase.from("funcionarioslojas").select("funcionarioid, lojaid, ativo, validador"),
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

  /**
   * Acerta em quais lojas a pessoa trabalha.
   * Sair de uma loja é desativar o vínculo, nunca apagar: o histórico de
   * tarefas e entregas daquela loja aponta para ele.
   */
  async function sincronizarLojas(funcionarioid: number, escolhidas: number[], validador: number[]) {
    if (escolhidas.length > 0) {
      const { error } = await supabase.from("funcionarioslojas").upsert(
        escolhidas.map((lojaid) => ({ funcionarioid, lojaid, ativo: true, validador: validador.includes(lojaid) })),
        { onConflict: "funcionarioid,lojaid" },
      );
      if (error) throw error;
    }

    const desativar = supabase
      .from("funcionarioslojas")
      .update({ ativo: false, validador: false })
      .eq("funcionarioid", funcionarioid);

    const { error } =
      escolhidas.length > 0
        ? await desativar.not("lojaid", "in", `(${escolhidas.join(",")})`)
        : await desativar;
    if (error) throw error;
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

      let funcionarioid = editando;
      if (funcionarioid === null) {
        const { data, error } = await supabase
          .from("funcionarios")
          .insert(dados)
          .select("funcionarioid")
          .single();
        if (error) throw error;
        funcionarioid = data.funcionarioid;
      } else {
        const { error } = await supabase
          .from("funcionarios")
          .update(dados)
          .eq("funcionarioid", funcionarioid);
        if (error) throw error;
      }

      await sincronizarLojas(funcionarioid, lojasEscolhidas, validadorEm);
    },
    onSuccess: () => {
      limparFormulario();
      qc.invalidateQueries({ queryKey: ["equipe"] });
    },
  });

  const aplicarHorario = useMutation({
    mutationFn: async () => {
      if (selecionados.length === 0) throw new Error("Marque pelo menos uma pessoa.");
      // Vazio = tirar o horário; o banco aceita nulo nos dois campos.
      const { error } = await supabase.rpc("definir_horario_equipe", {
        p_funcionarios: selecionados,
        p_entrada: (horaEntrada || null) as unknown as string,
        p_saida: (horaEntrada && horaSaida ? horaSaida : null) as unknown as string,
      });
      if (error) throw error;
    },
    onSuccess: () => {
      setSelecionados([]);
      qc.invalidateQueries({ queryKey: ["equipe"] });
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

  const novoCodigo = useMutation({
    onError: (e, funcionarioid) => setErroDoAcesso({ funcionarioid, texto: (e as Error).message }),
    mutationFn: (funcionarioid: number) => gerarCodigoDeAcesso({ data: { funcionarioid } }),
    onSuccess: aoGerarCodigo,
  });

  const trocarCpf = useMutation({
    mutationFn: ({ funcionarioid, cpf }: { funcionarioid: number; cpf: string }) =>
      trocarCpfDoColaborador({ data: { funcionarioid, cpf } }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["equipe"] });
      qc.invalidateQueries({ queryKey: ["acessos-equipe"] });
    },
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
  const hhmm = (h: string | null) => (h ? h.slice(0, 5) : null);

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

      <section className="space-y-2 rounded-xl border border-border bg-card p-4">
        <div>
          <h2 className="text-sm font-semibold">Horário da jornada</h2>
          <p className="text-xs text-muted-foreground">
            O bot usa este horário para mandar as tarefas do dia, os lembretes e o resumo do fim do expediente. Quem
            fica sem horário não recebe essas mensagens (continua recebendo os avisos). Saída em branco = entrada + 8h20.
            Saída menor que a entrada = turno da noite.
          </p>
        </div>
        <div className="flex flex-wrap items-end gap-3">
          <label className="text-sm">
            Entrada
            <input type="time" value={horaEntrada} onChange={(e) => setHoraEntrada(e.target.value)} className={`${campo} ml-2`} />
          </label>
          <label className="text-sm">
            Saída
            <input type="time" value={horaSaida} onChange={(e) => setHoraSaida(e.target.value)} className={`${campo} ml-2`} />
          </label>
          <button
            onClick={() => aplicarHorario.mutate()}
            disabled={aplicarHorario.isPending || selecionados.length === 0}
            className="rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground disabled:opacity-50"
          >
            Aplicar a {selecionados.length} {selecionados.length === 1 ? "pessoa" : "pessoas"}
          </button>
          <button
            onClick={() => setSelecionados(visiveis.filter((f) => f.ativo).map((f) => f.funcionarioid))}
            className="rounded-lg border border-border px-3 py-2 text-sm"
          >
            Marcar todos
          </button>
          {selecionados.length > 0 && (
            <button onClick={() => setSelecionados([])} className="rounded-lg border border-border px-3 py-2 text-sm">
              Limpar
            </button>
          )}
        </div>
        <p className="text-xs text-muted-foreground">
          Deixe a entrada em branco e aplique para tirar o horário das pessoas marcadas.
        </p>
        {aplicarHorario.isError && (
          <p className="text-sm text-destructive">{(aplicarHorario.error as Error).message}</p>
        )}
      </section>

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
                aria-label={`Escolher ${f.nomecompleto} para aplicar horário`}
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
                {hhmm(f.horarionotificacao)
                  ? `Jornada: ${hhmm(f.horarionotificacao)} às ${hhmm(f.horariosaida) ?? "(entrada + 8h20)"}`
                  : "Sem horário: não recebe as mensagens da jornada"}
              </p>
              <p className="text-xs text-muted-foreground">
                {cpfMascarado(f.cpf) ? `CPF ${cpfMascarado(f.cpf)}` : "Sem CPF cadastrado"} ·{" "}
                {situacaoDoAcesso(acessos.data?.get(f.funcionarioid))}
              </p>
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
              {acessos.data?.get(f.funcionarioid)?.temacesso && acessos.data?.get(f.funcionarioid)?.semsenha && (
                <button
                  onClick={() => novoCodigo.mutate(f.funcionarioid)}
                  disabled={novoCodigo.isPending}
                  className="rounded-md border border-border px-3 py-1 text-sm disabled:opacity-50"
                >
                  {novoCodigo.isPending ? "Gerando..." : "Gerar código novo"}
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
