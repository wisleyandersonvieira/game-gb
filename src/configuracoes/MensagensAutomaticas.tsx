// Configurações → Mensagens automáticas: liga e desliga cada rotina do bot,
// loja por loja. Tudo nasce ligado; aqui só fica o que o master mudou.
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { Carregando, ErroTela } from "@/ui/Estados";
import { useLojaAtiva } from "@/lojas/loja-ativa";

type Rotina = { chave: string; nome: string; ajuda: string };

const ROTINAS: Rotina[] = [
  { chave: "inicio_jornada", nome: "Início da jornada", ajuda: "Na hora de entrada: as tarefas do dia, com o botão da foto." },
  { chave: "lembrete3", nome: "Lembrete de 3 horas", ajuda: "Só o que ainda está em aberto. Não sai se tudo foi feito." },
  { chave: "lembrete6", nome: "Lembrete de 6 horas", ajuda: "Igual ao de 3 horas, mais tarde no turno." },
  { chave: "fim_jornada", nome: "Fim da jornada", ajuda: "Resumo do dia e o convite para avaliar o dia." },
  { chave: "comunicado_novo", nome: "Comunicado novo", ajuda: "Chega com o botão \"Estou ciente\"." },
  { chave: "comunicado_lembrete", nome: "Lembrete de comunicado", ajuda: "Uma vez, 24 h depois, se ainda faltar a ciência." },
  { chave: "folga_drop", nome: "Tarefas de quem está de folga", ajuda: "No grupo da equipe, com \"Pegar\" para o primeiro que clicar." },
  { chave: "missao", nome: "Missões da equipe", ajuda: "No grupo da equipe, no horário de cada missão." },
];

export function MensagensAutomaticas({ podeAlterar }: { podeAlterar: boolean }) {
  const qc = useQueryClient();
  const { lojas } = useLojaAtiva();

  const estado = useQuery({
    queryKey: ["mensagens-rotinas"],
    queryFn: async () => {
      const { data, error } = await supabase.from("mensagensrotinas").select("lojaid, rotina, ativo");
      if (error) throw error;
      return data ?? [];
    },
  });

  const mudar = useMutation({
    mutationFn: async ({ lojaid, rotina, ativo }: { lojaid: number; rotina: string; ativo: boolean }) => {
      const { error } = await supabase.rpc("definir_rotina_mensagem", { p_lojaid: lojaid, p_rotina: rotina, p_ativo: ativo });
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ["mensagens-rotinas"] }),
  });

  const ligada = (lojaid: number, rotina: string) =>
    (estado.data ?? []).find((r) => r.lojaid === lojaid && r.rotina === rotina)?.ativo ?? true;

  return (
    <section className="space-y-3 rounded-xl border border-border bg-card p-4">
      <div>
        <h2 className="text-lg font-semibold">Mensagens automáticas</h2>
        <p className="text-sm text-muted-foreground">
          O que o bot manda sozinho, em cada loja. Quem trabalha em duas lojas recebe se estiver ligado em pelo menos uma
          delas. Ninguém recebe nada na folga, no afastamento, fora do seu turno nem no horário de silêncio.
        </p>
      </div>

      {estado.isLoading && <Carregando />}
      {estado.isError && <ErroTela erro={estado.error} />}
      {mudar.isError && <ErroTela erro={mudar.error} />}

      {lojas.length === 0 ? (
        <p className="text-sm text-muted-foreground">Cadastre uma loja para configurar as mensagens.</p>
      ) : (
        <ul className="space-y-3">
          {ROTINAS.map((r) => (
            <li key={r.chave} className="space-y-1 border-t border-border pt-3 first:border-0 first:pt-0">
              <p className="text-sm font-medium">{r.nome}</p>
              <p className="text-xs text-muted-foreground">{r.ajuda}</p>
              <div className="flex flex-wrap gap-3 pt-1">
                {lojas.map((l) => (
                  <label key={l.lojaid} className="flex items-center gap-2 text-sm">
                    <input
                      type="checkbox"
                      checked={ligada(l.lojaid, r.chave)}
                      disabled={!podeAlterar || mudar.isPending}
                      onChange={(e) => mudar.mutate({ lojaid: l.lojaid, rotina: r.chave, ativo: e.target.checked })}
                    />
                    {l.nome}
                  </label>
                ))}
              </div>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
