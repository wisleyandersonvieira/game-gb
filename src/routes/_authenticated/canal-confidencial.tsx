import { createFileRoute } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Nav } from "@/components/Nav";

export const Route = createFileRoute("/_authenticated/canal-confidencial")({
  component: CanalConfidencial,
});

const dia = (iso: string) => `${iso.slice(8, 10)}/${iso.slice(5, 7)}/${iso.slice(0, 4)}`;

const COR: Record<string, string> = {
  Nova: "border-accent text-accent",
  "Em análise": "border-primary text-primary",
  Tratada: "border-border text-muted-foreground",
};

type Relato = {
  denunciaid: number;
  mensagem: string;
  dataregistro: string;
  status: string;
  resposta: string | null;
  respondidoem: string | null;
};

function CanalConfidencial() {
  const [filtro, setFiltro] = useState<"abertos" | "tratados" | "todos">("abertos");

  const master = useQuery({
    queryKey: ["sou-master"],
    queryFn: async () => {
      const { data, error } = await supabase.rpc("sou_master");
      if (error) throw error;
      return data === true;
    },
  });

  const relatos = useQuery({
    queryKey: ["canal-confidencial"],
    enabled: master.data === true,
    queryFn: async () => {
      const { data, error } = await supabase
        .from("denunciasanonimas")
        .select("denunciaid, mensagem, dataregistro, status, resposta, respondidoem")
        .order("dataregistro", { ascending: false })
        .limit(500);
      if (error) throw error;
      return (data ?? []) as Relato[];
    },
  });

  const lista = (relatos.data ?? []).filter((r) =>
    filtro === "todos" ? true : filtro === "tratados" ? r.status === "Tratada" : r.status !== "Tratada",
  );

  return (
    <main className="mx-auto min-h-screen max-w-3xl space-y-6 p-4 sm:p-6">
      <Nav />
      <h1 className="text-3xl font-bold">Canal confidencial</h1>

      <div className="space-y-1 rounded-xl border border-border bg-card p-4 text-sm text-muted-foreground">
        <p>
          🔒 <strong className="text-foreground">Anônimo de verdade.</strong> O sistema não guarda quem enviou: nem nome, nem
          login, nem telefone, nem a hora (só o dia). Só o responsável pela conta lê esta tela.
        </p>
        <p>
          Os relatos chegam pelo bot (Etapa 1.13). Quem enviou recebe um protocolo e, com ele, acompanha a resposta sem se
          identificar.
        </p>
      </div>

      {master.isLoading && <p className="text-muted-foreground">Carregando...</p>}
      {master.data === false && (
        <p className="rounded-lg border border-accent bg-card px-4 py-3 text-sm text-accent">
          Só o responsável pela conta acessa o canal confidencial.
        </p>
      )}

      {master.data && (
        <>
          <div className="flex gap-1">
            {(
              [
                ["abertos", "A tratar"],
                ["tratados", "Tratados"],
                ["todos", "Todos"],
              ] as const
            ).map(([id, rotulo]) => (
              <button
                key={id}
                onClick={() => setFiltro(id)}
                className={`rounded-lg px-3 py-1.5 text-sm ${filtro === id ? "bg-card font-semibold" : "text-muted-foreground"}`}
              >
                {rotulo}
              </button>
            ))}
          </div>

          {relatos.isLoading && <p className="text-muted-foreground">Carregando...</p>}
          {relatos.isError && <p className="text-sm text-destructive">{(relatos.error as Error).message}</p>}
          <div className="space-y-3">
            {lista.map((r) => (
              <CartaoRelato key={r.denunciaid} relato={r} />
            ))}
            {!relatos.isLoading && lista.length === 0 && (
              <p className="text-sm text-muted-foreground">Nenhum relato aqui.</p>
            )}
          </div>
        </>
      )}
    </main>
  );
}

function CartaoRelato({ relato }: { relato: Relato }) {
  const qc = useQueryClient();
  const [resposta, setResposta] = useState(relato.resposta ?? "");
  const [ok, setOk] = useState<string | null>(null);

  const tratar = useMutation({
    mutationFn: async (status: "Em análise" | "Tratada") => {
      const { error } = await supabase.rpc("tratar_relato", {
        p_denunciaid: relato.denunciaid,
        p_status: status,
        p_resposta: resposta,
      });
      if (error) throw error;
      return status;
    },
    onSuccess: (status) => {
      setOk(status === "Tratada" ? "Marcado como tratado." : "Salvo.");
      qc.invalidateQueries({ queryKey: ["canal-confidencial"] });
    },
  });

  return (
    <div className="space-y-3 rounded-lg border border-border bg-card px-4 py-3">
      <div className="flex items-center justify-between gap-2">
        <span className={`rounded-md border px-2 py-0.5 text-xs ${COR[relato.status] ?? ""}`}>{relato.status}</span>
        <span className="text-sm text-muted-foreground">{dia(relato.dataregistro)}</span>
      </div>
      <p className="whitespace-pre-wrap">{relato.mensagem}</p>
      <textarea
        rows={2}
        placeholder="Resposta (quem enviou vê pelo protocolo)"
        value={resposta}
        onChange={(e) => setResposta(e.target.value)}
        className="w-full rounded-lg border border-border bg-background px-3 py-2 text-sm"
      />
      {relato.respondidoem && (
        <p className="text-xs text-muted-foreground">Respondido em {dia(relato.respondidoem)}</p>
      )}
      <div className="flex flex-wrap gap-2">
        <button
          disabled={tratar.isPending}
          onClick={() => tratar.mutate("Em análise")}
          className="rounded-md border border-border px-3 py-1 text-sm"
        >
          {relato.status === "Tratada" ? "Reabrir (em análise)" : "Salvar como em análise"}
        </button>
        <button
          disabled={tratar.isPending}
          onClick={() => tratar.mutate("Tratada")}
          className="rounded-md bg-primary px-3 py-1 text-sm font-semibold text-primary-foreground"
        >
          Marcar como tratado
        </button>
      </div>
      {ok && <p className="text-xs text-primary">{ok}</p>}
      {tratar.isError && <p className="text-xs text-destructive">{(tratar.error as Error).message}</p>}
    </div>
  );
}
