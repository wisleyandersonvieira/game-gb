// Política de uso: o texto que cada pessoa aceita no primeiro acesso.
// Cada publicação é uma versão nova (um comunicado novo). As ciências antigas
// continuam guardadas, ligadas à versão que valia na época.
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { MODELO_POLITICA } from "./modelo-politica";

export function PoliticaDeUso({ podeAlterar }: { podeAlterar: boolean }) {
  const qc = useQueryClient();
  const [texto, setTexto] = useState("");
  const [aberto, setAberto] = useState(false);

  const emVigor = useQuery({
    queryKey: ["politica-em-vigor"],
    queryFn: async () => {
      const { data: config, error } = await supabase
        .from("configuracoes")
        .select("valor")
        .eq("chave", "POLITICA_USO_DOCUMENTOID")
        .maybeSingle();
      if (error) throw error;
      const id = Number(config?.valor ?? "");
      if (!id) return null;
      const { data: doc } = await supabase
        .from("documentos")
        .select("documentoid, titulo, conteudo, datacriacao")
        .eq("documentoid", id)
        .maybeSingle();
      if (!doc) return null;
      const { count: total } = await supabase
        .from("documentosassinaturas")
        .select("assinaturaid", { count: "exact", head: true })
        .eq("documentoid", id);
      const { count: cientes } = await supabase
        .from("documentosassinaturas")
        .select("assinaturaid", { count: "exact", head: true })
        .eq("documentoid", id)
        .eq("statusassinatura", "Ciente");
      return { ...doc, total: total ?? 0, cientes: cientes ?? 0 };
    },
  });

  const conta = useQuery({
    queryKey: ["nome-e-contato"],
    queryFn: async () => {
      const { data: c } = await supabase.from("contas").select("nome").single();
      const { data: contato } = await supabase
        .from("configuracoes")
        .select("valor")
        .eq("chave", "CONTATO_PRIVACIDADE")
        .maybeSingle();
      return { nome: c?.nome ?? "", contato: contato?.valor ?? "" };
    },
  });

  useEffect(() => {
    if (!aberto) return;
    const base = emVigor.data?.conteudo ?? MODELO_POLITICA;
    setTexto(
      base
        .replaceAll("[EMPRESA]", conta.data?.nome ?? "[EMPRESA]")
        .replaceAll("[NOME DO RESPONSÁVEL] — [E-MAIL OU TELEFONE]", conta.data?.contato || "[preencha o responsável em Configurações]"),
    );
  }, [aberto, emVigor.data, conta.data]);

  const publicar = useMutation({
    mutationFn: async () => {
      const { error } = await supabase.rpc("publicar_politica_de_uso", { p_conteudo: texto });
      if (error) throw error;
    },
    onSuccess: () => {
      setAberto(false);
      qc.invalidateQueries({ queryKey: ["politica-em-vigor"] });
      qc.invalidateQueries({ queryKey: ["comunicados"] });
    },
  });

  return (
    <section className="space-y-3">
      <div>
        <h2 className="text-sm font-semibold">Política de uso</h2>
        <p className="text-xs text-muted-foreground">
          Cada pessoa aceita esta política no primeiro acesso ao aplicativo. Publicar uma versão nova pede a
          ciência de todo mundo de novo; as ciências antigas continuam guardadas.
        </p>
      </div>

      <div className="rounded-lg border border-border bg-card p-3 text-sm">
        {emVigor.data ? (
          <>
            <p className="font-medium">{emVigor.data.titulo}</p>
            <p className="text-xs text-muted-foreground">
              {emVigor.data.cientes} de {emVigor.data.total} pessoas já deram ciência nesta versão.
            </p>
          </>
        ) : (
          <p className="text-muted-foreground">Nenhuma versão publicada ainda.</p>
        )}
      </div>

      {podeAlterar && !aberto && (
        <button onClick={() => setAberto(true)} className="rounded-md border border-border px-3 py-1 text-sm">
          {emVigor.data ? "Publicar nova versão" : "Publicar a política"}
        </button>
      )}

      {aberto && (
        <div className="space-y-2">
          <textarea
            value={texto}
            onChange={(e) => setTexto(e.target.value)}
            rows={18}
            className="w-full rounded-lg border border-border bg-background p-3 font-mono text-xs"
          />
          {publicar.isError && <p className="text-sm text-destructive">{(publicar.error as Error).message}</p>}
          <div className="flex gap-2">
            <button
              onClick={() => publicar.mutate()}
              disabled={publicar.isPending}
              className="rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground disabled:opacity-50"
            >
              Publicar
            </button>
            <button onClick={() => setAberto(false)} className="rounded-md border border-border px-3 py-1 text-sm">
              Cancelar
            </button>
          </div>
        </div>
      )}
    </section>
  );
}
