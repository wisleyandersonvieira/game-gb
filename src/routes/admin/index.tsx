import { createFileRoute } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import {
  criarContaEConvidar,
  reenviarConvite,
  situacaoDosLogins,
} from "@/servidor/contas";
import { Pagina } from "@/ui/Pagina";
import { Anexos } from "@/admin/Anexos";
import { EscolherRede } from "@/admin/EscolherRede";
import { cnpjValido, codigoNoFormato, formatarCnpj, soDigitos } from "@/admin/cnpj";

export const Route = createFileRoute("/admin/")({
  component: PainelAdmin,
});

// Razão social (coluna "nome") só em contrato e cobrança. No produto — o
// cabeçalho do gestor, o celular, a folha de acesso e os recibos — aparece o
// NOME FANTASIA. O tablet e a TV mostram o nome da LOJA.
const FORM_VAZIO = {
  nome: "",
  nomefantasia: "",
  responsavel: "",
  cnpj: "",
  email: "",
  telefone: "",
  cidade: "",
  limitelojas: 1,
  observacoes: "",
  redeid: null as number | null,
  codigo: "",
};

const campo =
  "rounded-lg border border-border bg-background px-3 py-2 text-sm placeholder:text-muted-foreground";

const CORES_STATUS: Record<string, string> = {
  ativa: "text-sucesso",
  suspensa: "text-azul",
  cancelada: "text-destructive",
};

const dataBr = (iso: string) =>
  new Intl.DateTimeFormat("pt-BR", { timeZone: "America/Sao_Paulo", day: "2-digit", month: "2-digit", year: "numeric" }).format(
    new Date(iso),
  );

/** Sugestão e disponibilidade do código da empresa, perguntadas ao banco. */
function useCodigoDaEmpresa(texto: string, codigoAtual: string | null) {
  const [adiado, setAdiado] = useState(texto);
  useEffect(() => {
    const t = setTimeout(() => setAdiado(texto), 300);
    return () => clearTimeout(t);
  }, [texto]);
  return useQuery({
    queryKey: ["codigo-disponivel", adiado, codigoAtual],
    enabled: adiado.length > 0,
    queryFn: async () => {
      const { data, error } = await supabase.rpc("codigo_empresa_disponivel", {
        p_codigo: adiado,
        p_codigoatual: codigoAtual ?? undefined,
      });
      if (error) throw error;
      return data as { formato: boolean; livre: boolean };
    },
  });
}

async function sugerirCodigo(nome: string, codigoAtual?: string) {
  const { data } = await supabase.rpc("sugerir_codigo_empresa", { p_nome: nome, p_codigoatual: codigoAtual });
  return ((data as { sugestao?: string } | null)?.sugestao ?? "") as string;
}

function PainelAdmin() {
  const qc = useQueryClient();
  const [form, setForm] = useState(FORM_VAZIO);
  const [editando, setEditando] = useState<number | null>(null);
  const [recado, setRecado] = useState<string | null>(null);
  // O código é sugerido a partir do nome fantasia até o admin mexer nele.
  const [codigoMexido, setCodigoMexido] = useState(false);
  const [anexosDe, setAnexosDe] = useState<number | null>(null);
  const [trocandoCodigo, setTrocandoCodigo] = useState<{ contaid: number; atual: string; nome: string } | null>(null);

  const contas = useQuery({
    queryKey: ["contas"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("contas")
        .select("contaid, nome, nomefantasia, responsavel, cnpj, redeid, codigo, email, telefone, cidade, limitelojas, status, observacoes, criadoem")
        .order("nomefantasia");
      if (error) throw error;
      return data ?? [];
    },
  });

  const redes = useQuery({
    queryKey: ["redes-para-escolher"],
    queryFn: async () => {
      const { data, error } = await supabase.from("redes").select("redeid, nome");
      if (error) throw error;
      return data ?? [];
    },
  });

  // Situação das rotinas automáticas de cada cliente (só ok/erro, sem detalhes).
  const rotinas = useQuery({
    queryKey: ["rotinas-resumo-admin"],
    refetchInterval: 60_000,
    queryFn: async () => {
      const { data, error } = await supabase.rpc("rotinas_resumo_admin");
      if (error) throw error;
      const porConta = new Map<number, { rotina: string; ultimaem: string; situacao: string }[]>();
      for (const r of data ?? []) porConta.set(r.contaid, [...(porConta.get(r.contaid) ?? []), r]);
      return porConta;
    },
  });

  // Lojas ativas e códigos de acesso pendentes, por cliente. Só números.
  const resumo = useQuery({
    queryKey: ["resumo-admin-das-contas"],
    queryFn: async () => {
      const { data, error } = await supabase.rpc("resumo_admin_das_contas");
      if (error) throw error;
      return new Map((data ?? []).map((r) => [r.contaid, r]));
    },
  });

  const logins = useQuery({
    queryKey: ["situacao-logins"],
    queryFn: async () => {
      const lista = await situacaoDosLogins();
      return new Map(lista.map((l) => [l.contaid, l.jaEntrou]));
    },
  });

  // Cliente NOVO: o código acompanha o nome fantasia (ou a razão social),
  // até o admin escrever o dele.
  const nomeParaCodigo = form.nomefantasia.trim() || form.nome.trim();
  useEffect(() => {
    if (editando !== null || codigoMexido || !nomeParaCodigo) return;
    const t = setTimeout(() => {
      void sugerirCodigo(nomeParaCodigo).then((s) => setForm((f) => ({ ...f, codigo: s })));
    }, 400);
    return () => clearTimeout(t);
  }, [nomeParaCodigo, editando, codigoMexido]);
  const codigoNovo = useCodigoDaEmpresa(editando === null ? form.codigo : "", null);

  function limpar() {
    setForm(FORM_VAZIO);
    setEditando(null);
    setCodigoMexido(false);
  }

  const cnpjDigitado = soDigitos(form.cnpj);
  const cnpjErrado = cnpjDigitado.length > 0 && !cnpjValido(cnpjDigitado);

  const salvar = useMutation({
    mutationFn: async () => {
      if (cnpjErrado) throw new Error("CNPJ inválido: confira os números (ou deixe em branco).");
      if (editando === null) {
        if (!codigoNoFormato(form.codigo)) {
          throw new Error("O código da empresa usa só letras minúsculas e números, de 4 a 20.");
        }
        return await criarContaEConvidar({
          data: {
            ...form,
            cnpj: cnpjDigitado,
            limitelojas: Number(form.limitelojas),
            redeid: form.redeid,
          },
        });
      }
      const { error } = await supabase
        .from("contas")
        .update({
          nome: form.nome.trim(),
          nomefantasia: form.nomefantasia.trim() || form.nome.trim(),
          responsavel: form.responsavel.trim() || null,
          cnpj: cnpjDigitado || null,
          redeid: form.redeid,
          telefone: form.telefone.trim() || null,
          cidade: form.cidade.trim() || null,
          limitelojas: Number(form.limitelojas),
          observacoes: form.observacoes.trim() || null,
        })
        .eq("contaid", editando);
      if (error) throw error;
      return null;
    },
    onSuccess: (r) => {
      setRecado(r ? `Cliente criado. Convite enviado para ${r.email}.` : "Cadastro do cliente atualizado.");
      limpar();
      qc.invalidateQueries({ queryKey: ["contas"] });
      qc.invalidateQueries({ queryKey: ["situacao-logins"] });
      qc.invalidateQueries({ queryKey: ["redes-admin"] });
    },
  });

  const mudarStatus = useMutation({
    mutationFn: async ({ contaid, status }: { contaid: number; status: string }) => {
      const { error } = await supabase.from("contas").update({ status }).eq("contaid", contaid);
      if (error) throw error;
    },
    onSuccess: () => {
      setRecado(null);
      qc.invalidateQueries({ queryKey: ["contas"] });
    },
  });

  const convidarDeNovo = useMutation({
    mutationFn: async (contaid: number) => await reenviarConvite({ data: { contaid } }),
    onSuccess: (r) => setRecado(`Convite reenviado para ${r.email}.`),
  });

  const lista = contas.data ?? [];
  const nomeDaRede = (id: number | null) => redes.data?.find((r) => r.redeid === id)?.nome;

  return (
    <Pagina titulo="Clientes" descricao="Clientes da plataforma. Você não vê os dados operacionais de nenhum deles.">
      {recado && <p className="rounded-lg border border-border bg-card px-4 py-3 text-sm">{recado}</p>}

      <form
        onSubmit={(e) => {
          e.preventDefault();
          setRecado(null);
          salvar.mutate();
        }}
        className="space-y-3 rounded-xl border border-border bg-card p-4"
      >
        <p className="text-sm font-semibold">{editando === null ? "Novo cliente" : "Editando cadastro do cliente"}</p>

        <div className="grid gap-3 md:grid-cols-3">
          <label className="space-y-1 text-xs text-muted-foreground md:col-span-2">
            Razão social (só em contrato e cobrança)
            <input
              required
              value={form.nome}
              onChange={(e) => setForm({ ...form, nome: e.target.value })}
              className={`${campo} w-full`}
            />
          </label>
          <label className="space-y-1 text-xs text-muted-foreground">
            Nome fantasia (o que aparece no sistema)
            <input
              placeholder="Igual à razão social, se ficar em branco"
              value={form.nomefantasia}
              onChange={(e) => setForm({ ...form, nomefantasia: e.target.value })}
              className={`${campo} w-full`}
            />
          </label>
          <label className="space-y-1 text-xs text-muted-foreground">
            Responsável
            <input value={form.responsavel} onChange={(e) => setForm({ ...form, responsavel: e.target.value })} className={`${campo} w-full`} />
          </label>
          <label className="space-y-1 text-xs text-muted-foreground">
            CNPJ (pode ficar em branco)
            <input
              inputMode="numeric"
              value={formatarCnpj(form.cnpj)}
              onChange={(e) => setForm({ ...form, cnpj: soDigitos(e.target.value).slice(0, 14) })}
              className={`${campo} w-full ${cnpjErrado && cnpjDigitado.length === 14 ? "border-destructive" : ""}`}
            />
            {cnpjErrado && cnpjDigitado.length === 14 && <span className="text-destructive">CNPJ inválido: confira os números.</span>}
          </label>
          <label className="space-y-1 text-xs text-muted-foreground">
            E-mail do responsável (login master)
            <input
              required
              type="email"
              value={form.email}
              disabled={editando !== null}
              onChange={(e) => setForm({ ...form, email: e.target.value })}
              className={`${campo} w-full disabled:opacity-50`}
            />
          </label>
          <input placeholder="Telefone" value={form.telefone} onChange={(e) => setForm({ ...form, telefone: e.target.value })} className={campo} />
          <input placeholder="Cidade" value={form.cidade} onChange={(e) => setForm({ ...form, cidade: e.target.value })} className={campo} />
          <label className="flex items-center gap-2 text-sm text-muted-foreground">
            Lojas liberadas:
            <input
              required
              type="number"
              min={1}
              value={form.limitelojas}
              onChange={(e) => setForm({ ...form, limitelojas: Number(e.target.value) })}
              className={`${campo} w-24`}
            />
          </label>
          <EscolherRede redes={redes.data ?? []} valor={form.redeid} mudar={(redeid) => setForm({ ...form, redeid })} />
          {editando === null && (
            <label className="space-y-1 text-xs text-muted-foreground md:col-span-2">
              Código da empresa (entra no link e na folha da equipe; só minúsculas e números, 4 a 20)
              <input
                required
                value={form.codigo}
                onChange={(e) => {
                  setCodigoMexido(true);
                  setForm({ ...form, codigo: e.target.value.toLowerCase().replace(/[^a-z0-9]/g, "").slice(0, 20) });
                }}
                className={`${campo} w-full font-mono`}
              />
              {form.codigo && !codigoNoFormato(form.codigo) && <span className="text-destructive">Use de 4 a 20 letras minúsculas e números.</span>}
              {codigoNoFormato(form.codigo) && codigoNovo.data && !codigoNovo.data.livre && (
                <span className="text-destructive">Este código já é (ou já foi) de outro cliente.</span>
              )}
              {codigoNoFormato(form.codigo) && codigoNovo.data?.livre && <span className="text-sucesso">Disponível.</span>}
            </label>
          )}
          <input
            placeholder="Observações"
            value={form.observacoes}
            onChange={(e) => setForm({ ...form, observacoes: e.target.value })}
            className={`${campo} md:col-span-3`}
          />
        </div>

        {editando === null && (
          <p className="text-xs text-muted-foreground">
            Ao salvar, enviamos um convite por e-mail para o responsável definir a senha dele.
          </p>
        )}

        <div className="flex flex-wrap items-center gap-2">
          <button
            type="submit"
            disabled={salvar.isPending}
            className="rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground disabled:opacity-60"
          >
            {salvar.isPending ? "Salvando..." : editando === null ? "Cadastrar e convidar" : "Salvar"}
          </button>
          {editando !== null && (
            <button type="button" onClick={limpar} className="rounded-lg border border-border px-4 py-2 text-sm">
              Cancelar
            </button>
          )}
        </div>

        {salvar.isError && <p className="text-sm text-destructive">{(salvar.error as Error).message}</p>}
      </form>

      <div className="space-y-2">
        {contas.isLoading && <p className="text-muted-foreground">Carregando...</p>}
        {contas.isError && (
          <p className="text-sm text-destructive">Não foi possível carregar: {(contas.error as Error).message}</p>
        )}

        {lista.map((c) => {
          const usadas = resumo.data?.get(c.contaid)?.lojasativas ?? 0;
          const jaEntrou = logins.data?.get(c.contaid);
          return (
            <div key={c.contaid} className="space-y-2 rounded-lg border border-border bg-card px-4 py-3">
              <div className="flex flex-wrap items-center justify-between gap-3">
                <div className="min-w-0">
                  <p className="font-medium">
                    {c.nomefantasia}
                    <span className={`ml-2 text-xs font-normal ${CORES_STATUS[c.status] ?? ""}`}>{c.status}</span>
                    {jaEntrou === false && (
                      <span className="ml-2 rounded-md border border-border px-2 py-0.5 text-xs font-normal text-muted-foreground">
                        convite pendente
                      </span>
                    )}
                  </p>
                  <p className="text-xs text-muted-foreground">
                    {c.nome}
                    {c.cnpj && ` · CNPJ ${formatarCnpj(c.cnpj)}`}
                    {c.redeid && ` · rede ${nomeDaRede(c.redeid) ?? ""}`}
                    {` · cliente desde ${dataBr(c.criadoem)}`}
                  </p>
                  <p className="text-sm text-muted-foreground">
                    {c.responsavel && `${c.responsavel} · `}
                    {c.email}
                    {c.cidade && ` · ${c.cidade}`}
                    {c.telefone && ` · ${c.telefone}`}
                  </p>
                  <CodigoDaEmpresa
                    codigo={c.codigo}
                    trocar={() => setTrocandoCodigo({ contaid: c.contaid, atual: c.codigo, nome: c.nomefantasia })}
                  />
                  <SituacaoRotinas itens={rotinas.data?.get(c.contaid)} />
                </div>

                <div className="flex flex-wrap items-center gap-2">
                  <span className="text-sm text-muted-foreground">
                    <strong className={usadas >= c.limitelojas ? "text-azul" : "text-foreground"}>{usadas}</strong> de{" "}
                    {c.limitelojas} lojas
                  </span>
                  <button
                    onClick={() => {
                      setRecado(null);
                      setEditando(c.contaid);
                      setCodigoMexido(true);
                      setForm({
                        nome: c.nome,
                        nomefantasia: c.nomefantasia,
                        responsavel: c.responsavel ?? "",
                        cnpj: c.cnpj ?? "",
                        email: c.email,
                        telefone: c.telefone ?? "",
                        cidade: c.cidade ?? "",
                        limitelojas: c.limitelojas,
                        observacoes: c.observacoes ?? "",
                        redeid: c.redeid,
                        codigo: c.codigo,
                      });
                    }}
                    className="rounded-md border border-border px-3 py-1 text-sm"
                  >
                    Editar
                  </button>
                  <button
                    onClick={() => setAnexosDe(anexosDe === c.contaid ? null : c.contaid)}
                    className="rounded-md border border-border px-3 py-1 text-sm"
                  >
                    Anexos
                  </button>
                  <button
                    onClick={() => convidarDeNovo.mutate(c.contaid)}
                    disabled={convidarDeNovo.isPending}
                    className="rounded-md border border-border px-3 py-1 text-sm disabled:opacity-60"
                  >
                    Reenviar convite
                  </button>
                  <button
                    onClick={() => mudarStatus.mutate({ contaid: c.contaid, status: c.status === "ativa" ? "suspensa" : "ativa" })}
                    className="rounded-md border border-border px-3 py-1 text-sm"
                  >
                    {c.status === "ativa" ? "Suspender" : "Reativar"}
                  </button>
                </div>
              </div>
              {anexosDe === c.contaid && <Anexos alvo="conta" id={c.contaid} />}
            </div>
          );
        })}

        {!contas.isLoading && lista.length === 0 && (
          <p className="text-sm text-muted-foreground">
            Nenhum cliente cadastrado ainda. Use o formulário acima para criar o primeiro.
          </p>
        )}

        {convidarDeNovo.isError && <p className="text-sm text-destructive">{(convidarDeNovo.error as Error).message}</p>}
        {mudarStatus.isError && <p className="text-sm text-destructive">{(mudarStatus.error as Error).message}</p>}
      </div>

      {trocandoCodigo && (
        <TrocarCodigo
          {...trocandoCodigo}
          pendentes={resumo.data?.get(trocandoCodigo.contaid)?.codigospendentes ?? 0}
          fechar={() => setTrocandoCodigo(null)}
          pronto={(novo) => {
            setTrocandoCodigo(null);
            setRecado(`Código trocado para "${novo}". O anterior continua abrindo a empresa por 30 dias.`);
            qc.invalidateQueries({ queryKey: ["contas"] });
          }}
        />
      )}
    </Pagina>
  );
}

/** O código da empresa no cartão, com copiar e trocar. */
function CodigoDaEmpresa({ codigo, trocar }: { codigo: string; trocar: () => void }) {
  const [copiado, setCopiado] = useState(false);
  return (
    <p className="mt-1 flex flex-wrap items-center gap-2 text-sm">
      Código da empresa: <span className="rounded-md border border-border px-2 py-0.5 font-mono">{codigo}</span>
      <button
        onClick={() =>
          void navigator.clipboard.writeText(codigo).then(() => {
            setCopiado(true);
            setTimeout(() => setCopiado(false), 2000);
          })
        }
        className="rounded-md border border-border px-2 py-0.5 text-xs"
      >
        {copiado ? "Copiado" : "Copiar"}
      </button>
      <button onClick={trocar} className="rounded-md border border-border px-2 py-0.5 text-xs">
        Trocar
      </button>
    </p>
  );
}

/**
 * Trocar o código quebra o que já foi impresso e o link colado no mural. A
 * tela diz isso ANTES, com o número de pessoas com código de acesso pendente,
 * e o código antigo continua abrindo a empresa por 30 dias.
 */
function TrocarCodigo({
  contaid,
  atual,
  nome,
  pendentes,
  fechar,
  pronto,
}: {
  contaid: number;
  atual: string;
  nome: string;
  pendentes: number;
  fechar: () => void;
  pronto: (novo: string) => void;
}) {
  const [novo, setNovo] = useState("");
  useEffect(() => {
    void sugerirCodigo(nome, atual).then((s) => setNovo(s === atual ? "" : s));
  }, [nome, atual]);
  const disponivel = useCodigoDaEmpresa(novo, atual);
  const ok = codigoNoFormato(novo) && novo !== atual && disponivel.data?.livre === true;

  const trocar = useMutation({
    mutationFn: async () => {
      const { error } = await supabase.from("contas").update({ codigo: novo }).eq("contaid", contaid);
      if (error) throw error;
    },
    onSuccess: () => pronto(novo),
  });

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4">
      <div className="w-full max-w-lg space-y-3 rounded-2xl bg-card p-5">
        <p className="text-lg font-semibold">Trocar o código de {nome}</p>
        <p className="text-sm">
          Hoje: <span className="font-mono">{atual}</span>
        </p>
        <div className="space-y-1 rounded-lg border border-destructive p-3 text-sm">
          <p className="font-semibold text-destructive">Antes de trocar</p>
          <p>
            As folhas de acesso já impressas e o link colado no mural da loja usam o código atual. Ele continua abrindo a
            empresa por <strong>30 dias</strong>; depois disso, só o novo funciona (o antigo fica reservado para esta
            empresa, ninguém mais pode usá-lo).
          </p>
          <p>
            {pendentes === 0
              ? "Ninguém desta empresa está com código de acesso pendente agora."
              : `${pendentes} ${pendentes === 1 ? "pessoa ainda tem" : "pessoas ainda têm"} código de acesso pendente — a folha delas traz o código atual da empresa.`}
          </p>
        </div>
        <label className="block space-y-1 text-xs text-muted-foreground">
          Código novo (só minúsculas e números, 4 a 20)
          <input
            value={novo}
            onChange={(e) => setNovo(e.target.value.toLowerCase().replace(/[^a-z0-9]/g, "").slice(0, 20))}
            className={`${campo} w-full font-mono`}
          />
        </label>
        {novo && !codigoNoFormato(novo) && <p className="text-xs text-destructive">Use de 4 a 20 letras minúsculas e números.</p>}
        {codigoNoFormato(novo) && disponivel.data && !disponivel.data.livre && (
          <p className="text-xs text-destructive">Este código já é (ou já foi) de outro cliente.</p>
        )}
        {trocar.isError && <p className="text-sm text-destructive">{(trocar.error as Error).message}</p>}
        <div className="flex gap-2">
          <button
            disabled={!ok || trocar.isPending}
            onClick={() => trocar.mutate()}
            className="rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground disabled:opacity-50"
          >
            {trocar.isPending ? "Trocando..." : "Trocar o código"}
          </button>
          <button onClick={fechar} className="rounded-lg border border-border px-4 py-2 text-sm">
            Cancelar
          </button>
        </div>
      </div>
    </div>
  );
}

const NOME_ROTINA: Record<string, string> = {
  lista_do_dia: "lista do dia",
  fechamento_mensal: "fechamento",
  conferencia_livro: "livro de pontos",
  limpeza: "limpeza",
};

function SituacaoRotinas({ itens }: { itens?: { rotina: string; ultimaem: string; situacao: string }[] }) {
  if (!itens || itens.length === 0) {
    return <p className="text-xs text-muted-foreground">Rotinas: ainda não rodaram.</p>;
  }
  const problemas = itens.filter((i) => i.situacao !== "ok");
  const ultima = itens.reduce((a, b) => (a.ultimaem > b.ultimaem ? a : b));
  const quando = new Date(ultima.ultimaem).toLocaleString("pt-BR", {
    timeZone: "America/Sao_Paulo",
    day: "2-digit",
    month: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  });
  return problemas.length === 0 ? (
    <p className="text-xs text-sucesso">Rotinas ok · última {quando}</p>
  ) : (
    <p className="text-xs text-destructive">
      Rotinas com problema:{" "}
      {problemas.map((p) => `${NOME_ROTINA[p.rotina] ?? p.rotina} (${p.situacao === "diferenca" ? "diferença" : "erro"})`).join(", ")}
    </p>
  );
}
