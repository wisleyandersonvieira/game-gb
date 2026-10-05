// Início: avisos que pedem atenção e a situação da rotina de hoje.
import { Link } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { CircleAlert, CircleCheck, Clock, X } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { avisosDoInicio, separarDispensados } from "./avisos-do-inicio";
import type { PainelInicio } from "./tipos";

const hora = (iso: string) => new Date(iso).toLocaleTimeString("pt-BR", { timeZone: "America/Sao_Paulo", hour: "2-digit", minute: "2-digit" });

export function SituacaoRotina({ rotina }: { rotina: PainelInicio["rotina"] }) {
  return (
    <Link to="/configuracoes" className="inline-flex items-center gap-1.5 text-xs text-muted-foreground hover:text-foreground">
      {!rotina ? (
        <>
          <Clock className="h-3.5 w-3.5" aria-hidden /> Lista de tarefas de hoje ainda não gerada
        </>
      ) : rotina.resultado === "ok" ? (
        <>
          <CircleCheck className="h-3.5 w-3.5 text-sucesso" aria-hidden /> Lista de tarefas de hoje: {hora(rotina.quando)}
          {rotina.origem === "manual" ? " (rodada à mão)" : ""} ✓
        </>
      ) : (
        <>
          <CircleAlert className="h-3.5 w-3.5 text-destructive" aria-hidden />
          <span className="text-destructive">Erro na rotina de hoje ({hora(rotina.quando)}): veja em Configurações</span>
        </>
      )}
    </Link>
  );
}

// Os avisos do topo e o X (05/10/2026): fechar dispensa AQUELE fato, só
// para quem fechou, e fica guardado no banco (vale em qualquer aparelho).
// Sempre tem volta: "N avisos dispensados · mostrar".
export function Avisos({ avisos, hoje }: { avisos: PainelInicio["avisos"]; hoje: string }) {
  const qc = useQueryClient();
  const dispensados = useQuery({
    queryKey: ["avisos-dispensados"],
    queryFn: async () => {
      const { data, error } = await supabase.rpc("avisos_dispensados");
      if (error) throw error;
      return new Set<string>(data ?? []);
    },
  });
  const fechar = useMutation({
    mutationFn: async (chaves: string[]) => {
      const { error } = await supabase.rpc("dispensar_avisos", { p_chaves: chaves });
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ["avisos-dispensados"] }),
  });
  const mostrar = useMutation({
    mutationFn: async (chaves: string[]) => {
      const { error } = await supabase.rpc("reexibir_avisos", { p_chaves: chaves });
      if (error) throw error;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ["avisos-dispensados"] }),
  });

  const itens = avisosDoInicio(avisos, hoje);
  if (itens.length === 0) return null;
  // Enquanto não sabe o que foi dispensado, mostra tudo (nada some por engano).
  const { visiveis, dispensados: fora } = separarDispensados(itens, dispensados.data ?? new Set());
  return (
    <div className="space-y-2">
      {visiveis.length > 0 && (
        <ul className="space-y-2" aria-label="Avisos">
          {visiveis.map((i) => (
            <li
              key={i.chaves.join(",")}
              className={`flex items-start gap-2 rounded-lg border px-3 py-2 text-sm ${
                i.grave ? "border-destructive/50 bg-destructive/10 text-destructive" : "border-azul/40 bg-azul-soft"
              }`}
            >
              <Link to={i.para} className="flex flex-1 items-start gap-2 hover:underline">
                <CircleAlert className={`mt-0.5 h-4 w-4 shrink-0 ${i.grave ? "" : "text-azul"}`} aria-hidden />
                <span>{i.texto}</span>
              </Link>
              <button
                type="button"
                onClick={() => fechar.mutate(i.chaves)}
                disabled={fechar.isPending}
                aria-label="Fechar este aviso"
                title="Fechar este aviso (só para você; volta se o problema mudar)"
                className="shrink-0 rounded-md p-0.5 opacity-70 hover:bg-muted hover:opacity-100"
              >
                <X className="h-4 w-4" aria-hidden />
              </button>
            </li>
          ))}
        </ul>
      )}
      {fora.length > 0 && (
        <p className="text-xs text-muted-foreground">
          {fora.length === 1 ? "1 aviso dispensado" : `${fora.length} avisos dispensados`} ·{" "}
          <button
            type="button"
            onClick={() => mostrar.mutate(fora.flatMap((i) => i.chaves))}
            disabled={mostrar.isPending}
            className="underline-offset-2 hover:underline"
          >
            mostrar
          </button>
        </p>
      )}
      {(fechar.isError || mostrar.isError) && (
        <p className="text-xs text-destructive">{((fechar.error ?? mostrar.error) as Error).message}</p>
      )}
    </div>
  );
}
