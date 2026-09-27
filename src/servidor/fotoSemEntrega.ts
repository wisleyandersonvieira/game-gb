// Tentativa que falha não deixa nada para trás (29/09/2026, regra do Wisley).
//
// A foto sobe para o armazenamento ANTES de o servidor conferir o PIN (ou a
// senha): é o que deixa a entrega rápida. Se a entrega não acontece — PIN
// errado, trava, foto velha, tarefa recusada —, o arquivo ficava lá, órfão:
// nenhuma entrega aponta para ele e a rotina de apagar fotos nunca o acha.
// Agora ele sai junto com a recusa. Fica só a contagem da trava.
//
// Dois cuidados:
//   * só se apaga arquivo que ESTE servidor autorizou para esta tentativa (o
//     bilhete conferido) — quem chama garante isso;
//   * nunca se apaga arquivo que uma entrega usa: se a recusa veio depois de
//     a entrega ter sido gravada (a resposta se perdeu no caminho), a foto
//     fica.

export type DependenciasDoDescarte = {
  /** Alguma entrega aponta para este arquivo? */
  temEntrega: (caminho: string) => Promise<boolean>;
  apagar: (caminho: string) => Promise<void>;
};

/** Apaga a foto de uma tentativa que falhou. Devolve true se apagou. */
export async function descartarFotoSemEntrega(caminho: string, d: DependenciasDoDescarte): Promise<boolean> {
  if (await d.temEntrega(caminho)) return false;
  await d.apagar(caminho);
  return true;
}

/** O descarte de verdade, com a chave de servidor. Nunca derruba a resposta. */
export async function descartarFotoDaTentativa(caminho: string): Promise<void> {
  try {
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    await descartarFotoSemEntrega(caminho, {
      temEntrega: async (c) => {
        const { data, error } = await supabaseAdmin.from("entregas").select("entregaid").eq("pathfotoevidencia", c).limit(1);
        // Na dúvida, a foto fica: apagar a prova de uma entrega é pior do que
        // deixar um arquivo sobrando.
        if (error) return true;
        return (data ?? []).length > 0;
      },
      apagar: async (c) => {
        await supabaseAdmin.storage.from("entregas").remove([c]);
      },
    });
  } catch {
    // Sem descarte agora: a recusa que a pessoa vê é o que importa.
  }
}
