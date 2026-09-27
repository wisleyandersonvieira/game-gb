// Anexos da administração (contratos), de um cliente ou de uma rede.
//
// Documento SIGILOSO: o arquivo sobe direto para um bucket privado, com uma
// autorização de poucos minutos para um único caminho, e o servidor confere
// tamanho e tipo antes de registrar. Para abrir, um link que vale 5 minutos.
// Não há "apagar": contrato anexado fica no histórico.
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { abrirAnexoAdmin, autorizarAnexoAdmin, registrarAnexoAdmin } from "@/servidor/contas";
import { dataHoraBr } from "@/rh/datas";

const TIPOS = ["application/pdf", "image/jpeg", "image/png", "image/webp"];
const MAXIMO = 10 * 1024 * 1024;

const tamanhoLegivel = (b: number) => (b >= 1024 * 1024 ? `${(b / 1024 / 1024).toFixed(1)} MB` : `${Math.ceil(b / 1024)} KB`);

export function Anexos({ alvo, id }: { alvo: "conta" | "rede"; id: number }) {
  const qc = useQueryClient();
  const [erro, setErro] = useState<string | null>(null);
  const chave = ["anexos-admin", alvo, id];

  const lista = useQuery({
    queryKey: chave,
    queryFn: async () => {
      const coluna = alvo === "conta" ? "contaid" : "redeid";
      const { data, error } = await supabase
        .from("anexosadmin")
        .select("anexoid, nomearquivo, tipo, tamanho, enviadoem")
        .eq(coluna, id)
        .order("enviadoem", { ascending: false });
      if (error) throw error;
      return data ?? [];
    },
  });

  const enviar = useMutation({
    mutationFn: async (arquivo: File) => {
      if (!TIPOS.includes(arquivo.type)) throw new Error("Só PDF ou imagem (JPG, PNG, WEBP).");
      if (arquivo.size > MAXIMO) throw new Error("O arquivo passa de 10 MB.");
      const a = await autorizarAnexoAdmin({ data: { alvo, id, tipo: arquivo.type, tamanho: arquivo.size } });
      const { error } = await supabase.storage.from("administracao").uploadToSignedUrl(a.caminho, a.token, arquivo);
      if (error) throw new Error("O arquivo não subiu. Tente de novo.");
      await registrarAnexoAdmin({
        data: { alvo, id, caminho: a.caminho, passe: a.passe, nome: arquivo.name, tipo: arquivo.type, tamanho: arquivo.size },
      });
    },
    onMutate: () => setErro(null),
    onError: (e) => setErro((e as Error).message),
    onSuccess: () => qc.invalidateQueries({ queryKey: chave }),
  });

  const abrir = useMutation({
    mutationFn: async (anexoid: number) => {
      // A janela abre ANTES da resposta: navegador bloqueia janela aberta
      // depois de uma espera.
      const janela = window.open("about:blank", "_blank");
      try {
        const { url } = await abrirAnexoAdmin({ data: { anexoid } });
        if (janela) janela.location.href = url;
        else window.location.href = url;
      } catch (e) {
        janela?.close();
        throw e;
      }
    },
    onError: (e) => setErro((e as Error).message),
  });

  return (
    <div className="space-y-2 rounded-lg border border-border bg-background p-3">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="text-sm font-semibold">Anexos (contratos)</p>
        <label className="cursor-pointer rounded-md border border-border px-3 py-1 text-sm">
          {enviar.isPending ? "Enviando..." : "Anexar PDF ou imagem"}
          <input
            type="file"
            accept="application/pdf,image/jpeg,image/png,image/webp"
            className="hidden"
            disabled={enviar.isPending}
            onChange={(e) => {
              const f = e.target.files?.[0];
              e.target.value = "";
              if (f) enviar.mutate(f);
            }}
          />
        </label>
      </div>
      <p className="text-xs text-muted-foreground">
        Sigiloso: só você abre, e o link de abertura vale 5 minutos. Até 10 MB.
      </p>
      {erro && <p className="text-sm text-destructive">{erro}</p>}
      {lista.isLoading && <p className="text-xs text-muted-foreground">Carregando...</p>}
      {lista.data?.length === 0 && <p className="text-xs text-muted-foreground">Nenhum anexo.</p>}
      <ul className="space-y-1">
        {lista.data?.map((a) => (
          <li key={a.anexoid} className="flex flex-wrap items-center justify-between gap-2 text-sm">
            <span className="min-w-0 truncate">
              {a.nomearquivo}{" "}
              <span className="text-xs text-muted-foreground">
                · {tamanhoLegivel(a.tamanho)} · enviado em {dataHoraBr(a.enviadoem)}
              </span>
            </span>
            <button
              onClick={() => abrir.mutate(a.anexoid)}
              disabled={abrir.isPending}
              className="rounded-md border border-border px-2 py-0.5 text-xs"
            >
              Abrir
            </button>
          </li>
        ))}
      </ul>
    </div>
  );
}
