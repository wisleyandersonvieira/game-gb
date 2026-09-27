// "Que dia é hoje", do lado das TELAS (27/09/2026).
//
// Quem decide é o BANCO (hoje_da_conta / fuso_da_conta): a hora do servidor e
// o fuso da conta. A tela só recebe a resposta — pela fila (colunas hoje e
// fuso) ou por meu_hoje() — e escreve. Nada aqui olha o relógio nem o fuso do
// aparelho: um tablet com a data errada, ou um navegador em UTC, não muda o
// que aparece.
//
// Por que existe: "Feitas hoje" mostrou entregas de ontem, e só dava para
// perceber estranhando a hora. Agora uma hora que não é de hoje vem com o
// dia escrito ("ontem às 19h47"), e o erro fica à vista.
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";

export type HojeDaConta = { hoje: string; fuso: string; agora: string };

/** O dia (AAAA-MM-DD) em que um instante cai, no fuso dado. */
export function diaNoFuso(iso: string, fuso: string): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: fuso,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date(iso));
}

/** "19h47", no fuso dado. */
export function horaNoFuso(iso: string, fuso: string): string {
  return new Intl.DateTimeFormat("pt-BR", { timeZone: fuso, hour: "2-digit", minute: "2-digit" })
    .format(new Date(iso))
    .replace(":", "h");
}

/** Dias entre duas datas AAAA-MM-DD (b − a). Conta de calendário, sem fuso. */
function diasEntre(a: string, b: string) {
  return Math.round((Date.parse(`${b}T00:00:00Z`) - Date.parse(`${a}T00:00:00Z`)) / 86_400_000);
}

/**
 * "às 19h47" quando é de hoje; "ontem às 19h47"; "amanhã às 08h00"; e
 * "25/09 às 19h47" quando é de outro dia. `hoje` e `fuso` vêm do servidor.
 */
export function quandoFoi(iso: string | null, hoje: string | null | undefined, fuso: string | null | undefined): string {
  if (!iso) return "";
  const f = fuso || "America/Sao_Paulo";
  const hora = horaNoFuso(iso, f);
  if (!hoje) return `às ${hora}`;
  const dia = diaNoFuso(iso, f);
  const d = diasEntre(hoje, dia);
  if (d === 0) return `às ${hora}`;
  if (d === -1) return `ontem às ${hora}`;
  if (d === 1) return `amanhã às ${hora}`;
  const [, mes, dd] = dia.split("-");
  return `${dd}/${mes} às ${hora}`;
}

/** O primeiro dia do mês de uma data AAAA-MM-DD. */
export const primeiroDoMes = (dia: string) => `${dia.slice(0, 7)}-01`;

/**
 * O dia de hoje DA CONTA de quem está logado, perguntado ao banco. Reconsulta
 * a cada minuto: uma tela aberta de um dia para o outro vira o dia sozinha.
 */
export function useHojeDaConta() {
  return useQuery({
    queryKey: ["hoje-da-conta"],
    queryFn: async () => {
      const { data, error } = await supabase.rpc("meu_hoje");
      if (error) throw error;
      return data as unknown as HojeDaConta;
    },
    staleTime: 60_000,
    refetchInterval: 60_000,
  });
}
