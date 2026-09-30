// O que cada tela de gestão pede para ser VISTA (parte 4, 29/09/2026).
//
// O menu esconde o que a pessoa não pode ver, e quem digita o endereço direto
// recebe uma mensagem clara. Isto é só a tela: quem decide é o banco (pode(),
// e as leituras do gerente), que confere de novo em toda leitura e gravação.
// "master" = tela só do dono da conta, nunca delegável.
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { ESTAVEL } from "@/ui/prazos";
import type { GrupoMenu, ItemMenu } from "./menu";

export const CODIGO_DA_TELA: Record<string, string | "master" | "todos"> = {
  "/inicio": "inicio.ver",
  "/operacional": "painel.ver",
  "/painel": "quadro.ver",
  "/tarefas": "tarefas.ver",
  "/solicitacoes": "solicitacoes.ver",
  "/relatorios": "relatorios.ver",
  "/estornos": "master",
  "/funcionarios": "equipe.ver",
  "/jornada": "jornada.ver",
  "/feedbacks": "feedbacks.ver",
  "/justificativas": "justificativas.ver",
  "/ranking": "ranking.ver",
  "/conquistas": "conquistas.ver",
  "/premios": "premios.ver",
  "/extrato": "extrato.ver",
  "/metas": "metas.ver",
  "/agenda": "agenda.ver",
  "/comunicados": "comunicados.ver",
  "/documentos-pessoais": "master",
  "/onboarding": "onboarding.ver",
  "/canal-confidencial": "master",
  "/gestao": "lojas.ver",
  "/configuracoes": "master",
  "/usuarios": "master",
  "/perfil": "todos",
  "/medir": "master",
};

export type MinhasPermissoes = { master: boolean; codigos: string[] };

/** O que quem está logado pode ver (pergunta ao banco; só diz de quem pergunta). */
export function useMinhasPermissoes() {
  return useQuery({
    queryKey: ["minhas-permissoes"],
    staleTime: ESTAVEL,
    queryFn: async () => {
      const { data, error } = await supabase.rpc("minhas_permissoes");
      if (error) throw error;
      return data as unknown as MinhasPermissoes;
    },
  });
}

/** A tela do endereço pode ser vista? Endereço sem regra: só o master (negado por padrão). */
export function podeVerTela(p: MinhasPermissoes | undefined, caminho: string): boolean {
  if (!p) return false;
  const raiz = "/" + (caminho.split("/")[1] ?? "");
  const regra = CODIGO_DA_TELA[raiz];
  if (p.master) return true;
  if (regra === undefined || regra === "master") return false;
  if (regra === "todos") return true;
  return p.codigos.includes(regra);
}

export function filtrarMenu(menu: GrupoMenu[], p: MinhasPermissoes | undefined): GrupoMenu[] {
  return menu
    .map((g) => ({ ...g, itens: g.itens.filter((i) => podeVerTela(p, i.to)) }))
    .filter((g) => g.itens.length > 0);
}

export function filtrarBarra(itens: ItemMenu[], p: MinhasPermissoes | undefined): ItemMenu[] {
  return itens.filter((i) => podeVerTela(p, i.to));
}

/**
 * Pode ver (e, pela regra geral, gravar) valores em R$? Só para esconder o
 * campo: quem decide, loja por loja, é o banco (pode('valores.ver_rs', loja)).
 */
export function usePodeVerValores(): boolean {
  const p = useMinhasPermissoes().data;
  return p?.master === true || (p?.codigos.includes("valores.ver_rs") ?? false);
}
