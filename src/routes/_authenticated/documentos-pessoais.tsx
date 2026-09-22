import { createFileRoute } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { validarArquivo } from "@/rh/arquivos";
import { dataHoraBr } from "@/rh/pdf";

export const Route = createFileRoute("/_authenticated/documentos-pessoais")({
  component: DocumentosPessoais,
});

const campo =
  "rounded-lg border border-border bg-background px-3 py-2 text-sm placeholder:text-muted-foreground";
const TIPOS = ["Holerite", "Recibo", "Contrato", "Atestado", "Advertência", "Cartão de ponto", "Documento de admissão", "Outro"];
const BUCKET = "documentos-rh";

type Doc = {
  documentoid: number;
  funcionarioid: number;
  tipodocumento: string;
  mesano: string | null;
  descricao: string | null;
  nomearquivo: string | null;
  tamanho: number | null;
  dataupload: string;
  situacao: string;
  substituidopor: number | null;
  motivoexclusao: string | null;
  excluidoem: string | null;
};

const referencia = (d: string | null) => (d ? `${d.slice(5, 7)}/${d.slice(0, 4)}` : "");

/** Envia o arquivo ao Storage (com o acesso liberado e registrado antes). */
async function enviar(funcionarioid: number, arquivo: File) {
  const tipo = await validarArquivo(arquivo);
  const { data: caminho, error: e1 } = await supabase.rpc("preparar_envio_documento", {
    p_funcionarioid: funcionarioid,
    p_nomearquivo: arquivo.name,
  });
  if (e1) throw e1;
  const { error: e2 } = await supabase.storage.from(BUCKET).upload(caminho as string, arquivo, { contentType: tipo });
  if (e2) throw e2;
  return { caminho: caminho as string, tipo };
}

function DocumentosPessoais() {
  const master = useQuery({
    queryKey: ["sou-master"],
    queryFn: async () => (await supabase.rpc("sou_master")).data === true,
  });

  return (
    <div className="mx-auto max-w-5xl space-y-6">
      <h1 className="font-display text-2xl font-semibold tracking-tight sm:text-3xl">Documentos pessoais</h1>
      <p className="text-sm text-muted-foreground">
        Holerites, recibos, contratos, atestados e outros documentos de cada pessoa. Só o responsável pela conta vê esta
        tela, e cada vez que um documento é aberto fica registrado quem abriu e quando. Documentos com ciência ou com
        mais de 7 dias não se apagam: envie uma nova versão ou arquive.
      </p>
      {master.isLoading && <p className="text-muted-foreground">Carregando...</p>}
      {master.data === false && (
        <p className="rounded-lg border border-azul/40 bg-azul-soft px-4 py-3 text-sm text-azul">
          Só o responsável pela conta acessa os documentos pessoais.
        </p>
      )}
      {master.data && <Conteudo />}
    </div>
  );
}

function Conteudo() {
  const qc = useQueryClient();
  const [inativos, setInativos] = useState(false);
  const [funcionarioid, setFuncionarioid] = useState<number | "">("");
  const [vista, setVista] = useState<"ativos" | "arquivados" | "historico">("ativos");
  const [aviso, setAviso] = useState<{ texto: string; grave: boolean } | null>(null);
  const [form, setForm] = useState({ tipo: "Holerite", referencia: "", descricao: "" });
  const [arquivo, setArquivo] = useState<File | null>(null);

  const pessoas = useQuery({
    queryKey: ["pessoas-documentos"],
    queryFn: async () => {
      const { data, error } = await supabase.from("funcionarios").select("funcionarioid, nomecompleto, ativo").order("nomecompleto");
      if (error) throw error;
      return data ?? [];
    },
  });

  const docs = useQuery({
    queryKey: ["documentos-pessoais", funcionarioid],
    enabled: funcionarioid !== "",
    queryFn: async () => {
      const [{ data, error }, { data: ciencias }, { data: acessos }] = await Promise.all([
        supabase
          .from("documentospessoais")
          .select("documentoid, funcionarioid, tipodocumento, mesano, descricao, nomearquivo, tamanho, dataupload, situacao, substituidopor, motivoexclusao, excluidoem")
          .eq("funcionarioid", Number(funcionarioid))
          .order("dataupload", { ascending: false }),
        supabase.from("documentospessoaisciencia").select("documentoid, status, dataciencia").eq("funcionarioid", Number(funcionarioid)),
        supabase.from("documentosacessos").select("documentoid, acao, acessadoem").eq("acao", "visualizacao").order("acessadoem", { ascending: false }).limit(500),
      ]);
      if (error) throw error;
      return {
        lista: (data ?? []) as Doc[],
        ciencia: new Map((ciencias ?? []).map((c) => [c.documentoid, c])),
        acessos: acessos ?? [],
      };
    },
  });

  const atualizar = () => qc.invalidateQueries({ queryKey: ["documentos-pessoais"] });

  const acao = useMutation({
    mutationFn: async (fazer: () => Promise<string | void>) => fazer(),
    onSuccess: (texto) => {
      setAviso({ texto: typeof texto === "string" ? texto : "Salvo.", grave: false });
      atualizar();
    },
    onError: (e) => setAviso({ texto: (e as Error).message, grave: true }),
  });

  function novo() {
    if (funcionarioid === "" || !arquivo) {
      setAviso({ texto: "Escolha a pessoa e o arquivo.", grave: true });
      return;
    }
    acao.mutate(async () => {
      const { caminho, tipo } = await enviar(Number(funcionarioid), arquivo);
      const { error } = await supabase.rpc("registrar_documento_pessoal", {
        p_funcionarioid: Number(funcionarioid),
        p_tipo: form.tipo,
        p_referencia: form.referencia ? `${form.referencia}-01` : (null as unknown as string),
        p_descricao: form.descricao || (null as unknown as string),
        p_caminho: caminho,
        p_nomearquivo: arquivo.name,
        p_tipoarquivo: tipo,
        p_tamanho: arquivo.size,
      });
      if (error) {
        await supabase.storage.from(BUCKET).remove([caminho]);
        throw error;
      }
      setArquivo(null);
      setForm({ ...form, referencia: "", descricao: "" });
      return "Documento enviado.";
    });
  }

  function novaVersao(d: Doc, file: File) {
    acao.mutate(async () => {
      const { caminho, tipo } = await enviar(d.funcionarioid, file);
      const { error } = await supabase.rpc("registrar_documento_pessoal", {
        p_funcionarioid: d.funcionarioid,
        p_tipo: d.tipodocumento,
        p_referencia: d.mesano ?? (null as unknown as string),
        p_descricao: d.descricao ?? (null as unknown as string),
        p_caminho: caminho,
        p_nomearquivo: file.name,
        p_tipoarquivo: tipo,
        p_tamanho: file.size,
        p_substitui: d.documentoid,
      });
      if (error) {
        await supabase.storage.from(BUCKET).remove([caminho]);
        throw error;
      }
      return "Nova versão enviada; a anterior ficou guardada como substituída.";
    });
  }

  async function abrir(documentoid: number) {
    // Registra o acesso e libera o arquivo; o link vale 5 minutos.
    const { data: caminho, error } = await supabase.rpc("liberar_documento_pessoal", { p_documentoid: documentoid });
    if (error) {
      setAviso({ texto: error.message, grave: true });
      return;
    }
    const { data, error: e2 } = await supabase.storage.from(BUCKET).createSignedUrl(caminho as string, 300);
    if (e2 || !data) {
      setAviso({ texto: "Não foi possível abrir o arquivo.", grave: true });
      return;
    }
    window.open(data.signedUrl, "_blank", "noopener");
    atualizar();
  }

  const r = docs.data;
  const lista = (r?.lista ?? []).filter((d) =>
    vista === "ativos" ? d.situacao === "Ativo" : vista === "arquivados" ? d.situacao === "Arquivado" : true,
  );
  const pessoasVisiveis = (pessoas.data ?? []).filter((p) => inativos || p.ativo);
  const botao = "rounded-md border border-border px-2 py-1 text-xs";

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-3">
        <select
          value={funcionarioid}
          onChange={(e) => setFuncionarioid(e.target.value === "" ? "" : Number(e.target.value))}
          className={`${campo} w-full sm:w-auto`}
        >
          <option value="">Escolha a pessoa...</option>
          {pessoasVisiveis.map((p) => (
            <option key={p.funcionarioid} value={p.funcionarioid}>
              {p.nomecompleto}
              {p.ativo ? "" : " (desativado)"}
            </option>
          ))}
        </select>
        <label className="flex items-center gap-2 text-sm text-muted-foreground">
          <input type="checkbox" checked={inativos} onChange={(e) => setInativos(e.target.checked)} />
          Mostrar pessoas desativadas
        </label>
      </div>

      {funcionarioid !== "" && (
        <>
          <form
            onSubmit={(e) => {
              e.preventDefault();
              novo();
            }}
            className="space-y-3 rounded-xl border border-border bg-card p-4"
          >
            <p className="text-sm font-semibold">Enviar documento</p>
            <div className="grid gap-3 sm:grid-cols-3">
              <select value={form.tipo} onChange={(e) => setForm({ ...form, tipo: e.target.value })} className={campo}>
                {TIPOS.map((t) => (
                  <option key={t}>{t}</option>
                ))}
              </select>
              <label className="flex items-center gap-2 text-sm text-muted-foreground">
                Referência
                <input type="month" value={form.referencia} onChange={(e) => setForm({ ...form, referencia: e.target.value })} className={campo} />
              </label>
              <input placeholder="Descrição (opcional)" maxLength={200} value={form.descricao} onChange={(e) => setForm({ ...form, descricao: e.target.value })} className={campo} />
              <input
                type="file"
                accept="application/pdf,image/jpeg,image/png"
                onChange={(e) => setArquivo(e.target.files?.[0] ?? null)}
                className="text-sm sm:col-span-3"
              />
            </div>
            <p className="text-xs text-muted-foreground">PDF, JPG ou PNG, até 10 MB. O sistema confere o conteúdo do arquivo, não só a extensão.</p>
            <button type="submit" disabled={acao.isPending} className="rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground disabled:opacity-60">
              {acao.isPending ? "Enviando..." : "Enviar"}
            </button>
          </form>

          {aviso && <p className={`text-sm ${aviso.grave ? "text-destructive" : "text-sucesso"}`}>{aviso.texto}</p>}

          <div className="flex gap-1">
            {(
              [
                ["ativos", "Ativos"],
                ["arquivados", "Arquivados"],
                ["historico", "Histórico completo"],
              ] as const
            ).map(([id, rotulo]) => (
              <button key={id} onClick={() => setVista(id)} className={`rounded-lg px-3 py-1.5 text-sm ${vista === id ? "bg-card font-semibold" : "text-muted-foreground"}`}>
                {rotulo}
              </button>
            ))}
          </div>

          {docs.isLoading && <p className="text-muted-foreground">Carregando...</p>}
          <div className="space-y-2">
            {lista.map((d) => {
              const ci = r?.ciencia.get(d.documentoid);
              const ciente = ci?.status === "Ciente";
              const recente = Date.now() - new Date(d.dataupload).getTime() <= 7 * 24 * 3600 * 1000;
              const acessos = (r?.acessos ?? []).filter((a) => a.documentoid === d.documentoid);
              return (
                <div key={d.documentoid} className={`space-y-1 rounded-lg border border-border bg-card px-4 py-3 ${d.situacao === "Excluido" ? "opacity-60" : ""}`}>
                  <div className="flex flex-wrap items-baseline justify-between gap-2">
                    <p className="font-medium">
                      {d.tipodocumento}
                      {d.mesano && ` · ${referencia(d.mesano)}`}
                      {d.descricao && <span className="font-normal text-muted-foreground"> · {d.descricao}</span>}
                      {d.situacao !== "Ativo" && (
                        <span className="ml-2 rounded-md border border-border px-2 py-0.5 text-xs font-normal text-muted-foreground">
                          {d.situacao === "Substituido" ? "substituído por nova versão" : d.situacao === "Excluido" ? "excluído por engano" : "arquivado"}
                        </span>
                      )}
                    </p>
                    <p className="text-xs text-muted-foreground">
                      {d.nomearquivo} · enviado em {dataHoraBr(d.dataupload)}
                    </p>
                  </div>
                  <p className="text-xs text-muted-foreground">
                    {ciente ? `✓ ciência registrada em ${dataHoraBr(ci!.dataciencia!)}` : "Ciência pendente"}
                    {acessos.length > 0 && ` · aberto ${acessos.length} ${acessos.length === 1 ? "vez" : "vezes"} (último em ${dataHoraBr(acessos[0].acessadoem)})`}
                    {d.motivoexclusao && ` · excluído em ${dataHoraBr(d.excluidoem!)}: ${d.motivoexclusao}`}
                  </p>
                  {d.situacao !== "Excluido" && (
                    <div className="flex flex-wrap gap-2 pt-1">
                      <button onClick={() => abrir(d.documentoid)} className={botao}>
                        Abrir (link de 5 min)
                      </button>
                      {!ciente && (d.situacao === "Ativo" || d.situacao === "Arquivado") && (
                        <button
                          onClick={() =>
                            acao.mutate(async () => {
                              const { error } = await supabase.rpc("registrar_ciencia_documento", { p_documentoid: d.documentoid });
                              if (error) throw error;
                              return "Ciência registrada.";
                            })
                          }
                          className={botao}
                        >
                          Registrar ciência
                        </button>
                      )}
                      {(d.situacao === "Ativo" || d.situacao === "Arquivado") && (
                        <label className={`${botao} cursor-pointer`}>
                          Nova versão
                          <input
                            type="file"
                            accept="application/pdf,image/jpeg,image/png"
                            className="hidden"
                            onChange={(e) => {
                              const f = e.target.files?.[0];
                              e.target.value = "";
                              if (f) novaVersao(d, f);
                            }}
                          />
                        </label>
                      )}
                      {d.situacao === "Ativo" && (
                        <button
                          onClick={() =>
                            acao.mutate(async () => {
                              const { error } = await supabase.rpc("arquivar_documento_pessoal", { p_documentoid: d.documentoid });
                              if (error) throw error;
                              return "Documento arquivado (continua guardado).";
                            })
                          }
                          className={botao}
                        >
                          Arquivar
                        </button>
                      )}
                      {d.situacao === "Ativo" && !ciente && recente && (
                        <button
                          onClick={() => {
                            const motivo = window.prompt("Por que este documento foi enviado por engano?");
                            if (motivo === null) return;
                            if (!motivo.trim()) {
                              setAviso({ texto: "O motivo é obrigatório.", grave: true });
                              return;
                            }
                            acao.mutate(async () => {
                              const { data: caminho, error } = await supabase.rpc("excluir_documento_por_engano", {
                                p_documentoid: d.documentoid,
                                p_motivo: motivo.trim(),
                              });
                              if (error) throw error;
                              await supabase.storage.from(BUCKET).remove([caminho as string]);
                              return "Arquivo excluído; o registro da exclusão ficou guardado.";
                            });
                          }}
                          className="rounded-md border border-destructive px-2 py-1 text-xs text-destructive"
                        >
                          Excluir (enviado por engano)
                        </button>
                      )}
                    </div>
                  )}
                </div>
              );
            })}
            {r && lista.length === 0 && <p className="text-sm text-muted-foreground">Nenhum documento aqui.</p>}
          </div>
        </>
      )}
    </div>
  );
}
