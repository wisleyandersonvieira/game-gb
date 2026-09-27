// Redes de franquia (só o administrador geral).
//
// "Lojas": o número CONTRATADO é digitado aqui; ao lado, a contagem REAL (as
// lojas ativas dos clientes da rede) é calculada pelo banco. É assim que se vê
// quem está usando menos do que contratou.
//
// O logotipo, por enquanto, aparece só nesta lista.
import { createFileRoute } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { autorizarLogoRede, logosDasRedes, registrarLogoRede } from "@/servidor/contas";
import { Pagina } from "@/ui/Pagina";
import { Anexos } from "@/admin/Anexos";

export const Route = createFileRoute("/admin/redes")({ component: Redes });

const VAZIO = { nome: "", responsavel: "", endereco: "", telefone: "", email: "", lojascontratadas: 0 };
const campo = "rounded-lg border border-border bg-background px-3 py-2 text-sm placeholder:text-muted-foreground";
const TIPOS_LOGO = ["image/png", "image/jpeg", "image/webp"];
const MAXIMO_LOGO = 512 * 1024;

function Redes() {
  const qc = useQueryClient();
  const [form, setForm] = useState(VAZIO);
  const [editando, setEditando] = useState<number | null>(null);
  const [anexosDe, setAnexosDe] = useState<number | null>(null);
  const [erro, setErro] = useState<string | null>(null);

  const redes = useQuery({
    queryKey: ["redes-admin"],
    queryFn: async () => {
      const { data, error } = await supabase.rpc("redes_admin");
      if (error) throw error;
      return data ?? [];
    },
  });
  // Links de 5 minutos: o bucket é privado. Renova antes de vencer.
  const logos = useQuery({ queryKey: ["logos-redes"], queryFn: () => logosDasRedes(), refetchInterval: 240_000 });

  const invalidar = () => {
    qc.invalidateQueries({ queryKey: ["redes-admin"] });
    qc.invalidateQueries({ queryKey: ["redes-para-escolher"] });
    qc.invalidateQueries({ queryKey: ["logos-redes"] });
  };

  const salvar = useMutation({
    mutationFn: async () => {
      const dados = {
        nome: form.nome.trim(),
        responsavel: form.responsavel.trim() || null,
        endereco: form.endereco.trim() || null,
        telefone: form.telefone.trim() || null,
        email: form.email.trim() || null,
        lojascontratadas: Number(form.lojascontratadas) || 0,
      };
      const { error } =
        editando === null
          ? await supabase.from("redes").insert(dados)
          : await supabase.from("redes").update(dados).eq("redeid", editando);
      if (error) throw new Error(error.code === "23505" ? "Já existe uma rede com esse nome." : error.message);
    },
    onMutate: () => setErro(null),
    onSuccess: () => {
      setForm(VAZIO);
      setEditando(null);
      invalidar();
    },
  });

  const apagar = useMutation({
    mutationFn: async (r: { redeid: number; nome: string; clientes: number }) => {
      // O banco recusa de qualquer jeito; a tela avisa antes, com o número.
      if (r.clientes > 0) {
        throw new Error(
          `A rede "${r.nome}" tem ${r.clientes} ${r.clientes === 1 ? "cliente ligado" : "clientes ligados"}. Mova ${r.clientes === 1 ? "esse cliente" : "esses clientes"} para outra rede (ou "sem rede") em Clientes antes de apagar.`,
        );
      }
      if (!confirm(`Apagar a rede "${r.nome}"?`)) return;
      const { error } = await supabase.from("redes").delete().eq("redeid", r.redeid);
      if (error) throw error;
    },
    onMutate: () => setErro(null),
    onError: (e) => setErro((e as Error).message),
    onSuccess: invalidar,
  });

  const logo = useMutation({
    mutationFn: async ({ redeid, arquivo }: { redeid: number; arquivo: File }) => {
      if (!TIPOS_LOGO.includes(arquivo.type)) throw new Error("O logotipo tem de ser PNG, JPG ou WEBP.");
      if (arquivo.size > MAXIMO_LOGO) throw new Error("O logotipo passa de 512 KB. Use uma imagem menor.");
      const a = await autorizarLogoRede({ data: { redeid, tipo: arquivo.type, tamanho: arquivo.size } });
      const { error } = await supabase.storage.from("logos-redes").uploadToSignedUrl(a.caminho, a.token, arquivo);
      if (error) throw new Error("O logotipo não subiu. Tente de novo.");
      await registrarLogoRede({ data: { redeid, caminho: a.caminho, passe: a.passe, tipo: arquivo.type, tamanho: arquivo.size } });
    },
    onMutate: () => setErro(null),
    onError: (e) => setErro((e as Error).message),
    onSuccess: invalidar,
  });

  return (
    <Pagina titulo="Redes" descricao="Redes de franquia. Nenhum cliente vê esta página nem os dados dela.">
      <form
        onSubmit={(e) => {
          e.preventDefault();
          salvar.mutate();
        }}
        className="space-y-3 rounded-xl border border-border bg-card p-4"
      >
        <p className="text-sm font-semibold">{editando === null ? "Nova rede" : "Editando rede"}</p>
        <div className="grid gap-3 md:grid-cols-3">
          <input required placeholder="Nome da rede" value={form.nome} onChange={(e) => setForm({ ...form, nome: e.target.value })} className={`${campo} md:col-span-2`} />
          <input placeholder="Responsável" value={form.responsavel} onChange={(e) => setForm({ ...form, responsavel: e.target.value })} className={campo} />
          <input placeholder="Endereço" value={form.endereco} onChange={(e) => setForm({ ...form, endereco: e.target.value })} className={`${campo} md:col-span-2`} />
          <input placeholder="Telefone" value={form.telefone} onChange={(e) => setForm({ ...form, telefone: e.target.value })} className={campo} />
          <input type="email" placeholder="E-mail" value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} className={campo} />
          <label className="flex items-center gap-2 text-sm text-muted-foreground">
            Lojas contratadas:
            <input
              type="number"
              min={0}
              value={form.lojascontratadas}
              onChange={(e) => setForm({ ...form, lojascontratadas: Number(e.target.value) })}
              className={`${campo} w-24`}
            />
          </label>
        </div>
        <div className="flex gap-2">
          <button type="submit" disabled={salvar.isPending} className="rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground disabled:opacity-60">
            {salvar.isPending ? "Salvando..." : editando === null ? "Cadastrar rede" : "Salvar"}
          </button>
          {editando !== null && (
            <button type="button" onClick={() => { setForm(VAZIO); setEditando(null); }} className="rounded-lg border border-border px-4 py-2 text-sm">
              Cancelar
            </button>
          )}
        </div>
        {salvar.isError && <p className="text-sm text-destructive">{(salvar.error as Error).message}</p>}
      </form>

      {erro && <p className="rounded-lg border border-destructive px-4 py-3 text-sm text-destructive">{erro}</p>}

      <div className="space-y-2">
        {redes.isLoading && <p className="text-muted-foreground">Carregando...</p>}
        {redes.data?.length === 0 && <p className="text-sm text-muted-foreground">Nenhuma rede cadastrada.</p>}
        {redes.data?.map((r) => {
          const url = logos.data?.[r.redeid];
          const abaixo = r.lojasreais < r.lojascontratadas;
          return (
            <div key={r.redeid} className="space-y-2 rounded-lg border border-border bg-card px-4 py-3">
              <div className="flex flex-wrap items-center justify-between gap-3">
                <div className="flex min-w-0 items-center gap-3">
                  <div className="flex h-12 w-12 shrink-0 items-center justify-center overflow-hidden rounded-md border border-border bg-background text-xs text-muted-foreground">
                    {url ? <img src={url} alt={`Logotipo de ${r.nome}`} className="h-full w-full object-contain" /> : "logo"}
                  </div>
                  <div className="min-w-0">
                    <p className="font-medium">{r.nome}</p>
                    <p className="text-sm text-muted-foreground">
                      {[r.responsavel, r.email, r.telefone].filter(Boolean).join(" · ") || "Sem contato cadastrado"}
                    </p>
                    {r.endereco && <p className="text-xs text-muted-foreground">{r.endereco}</p>}
                    <p className="text-sm">
                      Lojas: <strong>{r.lojascontratadas}</strong> contratadas ·{" "}
                      <strong className={abaixo ? "text-azul" : ""}>{r.lojasreais}</strong> em uso
                      {abaixo && <span className="text-azul"> (usando menos do que contratou)</span>}
                      <span className="text-muted-foreground"> · {r.clientes} {r.clientes === 1 ? "cliente" : "clientes"}</span>
                    </p>
                  </div>
                </div>
                <div className="flex flex-wrap items-center gap-2">
                  <label className="cursor-pointer rounded-md border border-border px-3 py-1 text-sm">
                    {logo.isPending ? "Enviando..." : r.temlogo ? "Trocar logotipo" : "Enviar logotipo"}
                    <input
                      type="file"
                      accept="image/png,image/jpeg,image/webp"
                      className="hidden"
                      onChange={(e) => {
                        const f = e.target.files?.[0];
                        e.target.value = "";
                        if (f) logo.mutate({ redeid: r.redeid, arquivo: f });
                      }}
                    />
                  </label>
                  <button
                    onClick={() => {
                      setEditando(r.redeid);
                      setForm({
                        nome: r.nome,
                        responsavel: r.responsavel ?? "",
                        endereco: r.endereco ?? "",
                        telefone: r.telefone ?? "",
                        email: r.email ?? "",
                        lojascontratadas: r.lojascontratadas,
                      });
                    }}
                    className="rounded-md border border-border px-3 py-1 text-sm"
                  >
                    Editar
                  </button>
                  <button onClick={() => setAnexosDe(anexosDe === r.redeid ? null : r.redeid)} className="rounded-md border border-border px-3 py-1 text-sm">
                    Anexos
                  </button>
                  <button onClick={() => apagar.mutate(r)} className="rounded-md border border-border px-3 py-1 text-sm">
                    Apagar
                  </button>
                </div>
              </div>
              {anexosDe === r.redeid && <Anexos alvo="rede" id={r.redeid} />}
            </div>
          );
        })}
      </div>
      <p className="text-xs text-muted-foreground">Logotipo: PNG, JPG ou WEBP, até 512 KB. Por enquanto aparece só nesta lista.</p>
    </Pagina>
  );
}
