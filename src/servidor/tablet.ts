// Etapa 1.12, parte B1b: o que o tablet do balcao pode fazer.
//
// O tablet fica logado como a LOJA, nao como pessoa. Ele NAO fala com o banco:
// para ele `minha_conta()` responde vazio e as ~200 regras de acesso negam
// tudo. Tudo passa por aqui, e daqui para as funcoes `visao_*`, que sao as
// unicas que ligam o contexto da visao.
//
// Toda acao com dono (pegar, entregar) e assinada com o PIN de 6 digitos:
// o servidor descobre quem e e registra em nome dela. O PIN nunca fica
// guardado em lugar nenhum — vem no pedido, e some quando ele acaba.
import { createServerFn } from "@tanstack/react-start";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import { abrirTentativa, fecharTentativa, origemDaChamada, embaralhar, resumoDoPin } from "@/servidor/segredos";
import { conferirBilhete, conferirHoraDaFoto, emitirBilhete, provaDaFoto } from "@/servidor/fotodaentrega";

type ClienteDoUsuario = {
  rpc: (nome: string, args?: Record<string, unknown>) => Promise<{ data: unknown; error: unknown }>;
};

type Tablet = { contaid: number; lojaid: number; loja: string };

export type ItemDaFila = {
  atribuicaoid: number;
  entregarid: number | null;
  titulo: string;
  pontos: number;
  tipofrequencia: string;
  aberta: boolean;
  donoid: number | null;
  quempegou: number | null;
  quempegounome: string | null;
  pegaem: string | null;
  situacao: "para_pegar" | "em_andamento" | "feita";
  atrasada: boolean;
  /** Desde quando está disponível HOJE. O cronômetro conta a partir daqui. */
  disponiveldesde: string | null;
  /** O rodízio está ligado e esta tarefa é disputada (aviso do cartão). */
  rodizio: boolean;
  /** A hora do servidor, para o aparelho acertar o relógio dele. */
  agora: string;
};

/**
 * Qual loja e este tablet — pelo TOKEN, nunca pelo que o navegador diz.
 * Pessoa desligada, loja desativada ou conta cancelada caem aqui na hora.
 */
async function tabletDoToken(supabase: ClienteDoUsuario, userId: string): Promise<Tablet> {
  const { data, error } = await supabase.rpc("meu_acesso");
  if (error) throw new Error("Não foi possível confirmar o acesso deste tablet.");
  const acesso = data as { tipo?: string; loja?: string } | null;
  if (!acesso || acesso.tipo !== "loja") throw new Error("Esta tela é do tablet da loja.");

  const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
  const { data: vinculo, error: erro } = await supabaseAdmin
    .from("contasusuarios")
    .select("contaid, lojaid")
    .eq("userid", userId)
    .single();
  if (erro || !vinculo?.lojaid) throw new Error("Este tablet não está ligado a nenhuma loja.");
  return { contaid: vinculo.contaid, lojaid: vinculo.lojaid, loja: acesso.loja ?? "" };
}

/**
 * Descobre quem digitou o PIN. Passa pela trava da parte A com tipo "tablet":
 * a trava por origem vale (é ela que segura um adivinhador), mas a trava por
 * chave não — senão um engraçadinho deixaria o balcão sem sistema por 15
 * minutos num horário de pico.
 */
async function pessoaDoPin(t: Tablet, pin: string) {
  const limpo = (pin ?? "").trim();
  if (!/^\d{6}$/.test(limpo)) throw new Error("PIN não reconhecido.");

  const chave = await embaralhar(`pintablet:${t.contaid}:${t.lojaid}`);
  const tentativa = await abrirTentativa(t.contaid, "pintablet", chave, origemDaChamada());

  const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
  const { data, error } = await supabaseAdmin.rpc("visao_pessoa_do_pin", {
    p_contaid: t.contaid,
    p_lojaid: t.lojaid,
    p_pinhash: await resumoDoPin(t.contaid, limpo),
  });
  const pessoa = data as { funcionarioid: number; nome: string } | null;
  await fecharTentativa(tentativa, !error && !!pessoa);
  if (error) throw new Error("Não foi possível conferir o PIN agora.");
  // Mensagem única: nunca diz se o PIN existe e a pessoa é que não pode.
  if (!pessoa) throw new Error("PIN não reconhecido. Confira o número — e lembre que só quem trabalha hoje nesta loja aparece na fila.");
  return pessoa;
}

/** A fila do dia. Não precisa de PIN: é o que está no balcão, à vista de todos. */
export const filaDoTablet = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    const { supabase, userId } = context as unknown as { supabase: ClienteDoUsuario; userId: string };
    const t = await tabletDoToken(supabase, userId);
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { data, error } = await supabaseAdmin.rpc("visao_fila", { p_contaid: t.contaid, p_lojaid: t.lojaid });
    if (error) throw new Error("Não foi possível carregar a fila agora.");

    // A partir de quantos minutos o cartão fica marcado como parado.
    const { data: cfg } = await supabaseAdmin
      .from("configuracoes")
      .select("valor")
      .eq("contaid", t.contaid)
      .eq("chave", "MINUTOS_TAREFA_PARADA")
      .maybeSingle();

    return {
      loja: t.loja,
      minutosParada: Number(cfg?.valor ?? 30) || 30,
      itens: (data ?? []) as unknown as ItemDaFila[],
    };
  });

export const pegarNoTablet = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((d: { pin: string; atribuicaoid: number }) => d)
  .handler(async ({ data, context }) => {
    const { supabase, userId } = context as unknown as { supabase: ClienteDoUsuario; userId: string };
    const t = await tabletDoToken(supabase, userId);
    const pessoa = await pessoaDoPin(t, data.pin);

    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { error } = await supabaseAdmin.rpc("visao_pegar", {
      p_contaid: t.contaid,
      p_lojaid: t.lojaid,
      p_funcionarioid: pessoa.funcionarioid,
      p_atribuicaoid: data.atribuicaoid,
    });
    if (error) throw new Error(error.message);
    return { nome: pessoa.nome };
  });

/**
 * Autorizacao de envio da foto: vale por poucos minutos e so para a pasta
 * desta loja. A chave secreta nunca sai do servidor, e o tablet nao consegue
 * escrever na pasta de outra loja nem de outra conta.
 */
export const autorizacaoDeFoto = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((d: { atribuicaoid: number }) => {
    if (!Number.isInteger(d?.atribuicaoid) || d.atribuicaoid <= 0) throw new Error("Tarefa inválida.");
    return { atribuicaoid: d.atribuicaoid };
  })
  .handler(async ({ data: { atribuicaoid }, context }) => {
    const { supabase, userId } = context as unknown as { supabase: ClienteDoUsuario; userId: string };
    const t = await tabletDoToken(supabase, userId);
    const caminho = `${t.contaid}/${t.lojaid}/${crypto.randomUUID()}.jpg`;

    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { data, error } = await supabaseAdmin.storage.from("entregas").createSignedUploadUrl(caminho);
    if (error || !data) throw new Error("Não foi possível preparar o envio da foto.");

    // O bilhete amarra o caminho a esta loja e a esta tarefa, por 10 minutos.
    // Quem assina de verdade a entrega e o PIN; aqui o tablet nao e uma
    // pessoa, entao a loja entra no lugar dela.
    const bilhete = await emitirBilhete(caminho, atribuicaoid, -t.lojaid);
    return { caminho, token: data.token, bilhete };
  });

export const entregarNoTablet = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator(
    (d: { pin: string; atribuicaoid: number; caminho?: string | null; bilhete?: string | null; observacao?: string | null }) => {
      if (typeof d?.pin !== "string") throw new Error("PIN inválido.");
      if (!Number.isInteger(d?.atribuicaoid) || d.atribuicaoid <= 0) throw new Error("Tarefa inválida.");
      return {
        pin: d.pin,
        atribuicaoid: d.atribuicaoid,
        caminho: typeof d.caminho === "string" ? d.caminho.slice(0, 300) : null,
        bilhete: typeof d.bilhete === "string" ? d.bilhete.slice(0, 200) : null,
        observacao: typeof d.observacao === "string" ? d.observacao.slice(0, 1000) : null,
      };
    },
  )
  .handler(async ({ data, context }) => {
    const { supabase, userId } = context as unknown as { supabase: ClienteDoUsuario; userId: string };
    const t = await tabletDoToken(supabase, userId);
    const pessoa = await pessoaDoPin(t, data.pin);

    // A prova da foto sai do ARQUIVO, aqui no servidor — como no celular.
    // Antes, o tablet nem mandava a impressao digital, entao a mesma foto
    // provava duas tarefas por ali.
    let fotoidunico: string | null = null;
    let semhorafoto = false;
    if (data.caminho) {
      if (!data.bilhete) throw new Error("Envio de foto inválido.");
      await conferirBilhete(data.bilhete, data.caminho, data.atribuicaoid, -t.lojaid);
      const prova = await provaDaFoto(data.caminho);
      fotoidunico = prova.fotoidunico;
      ({ semhorafoto } = await conferirHoraDaFoto(t.contaid, prova.horafoto));
    }

    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { error } = await supabaseAdmin.rpc("visao_entregar", {
      p_contaid: t.contaid,
      p_lojaid: t.lojaid,
      p_funcionarioid: pessoa.funcionarioid,
      p_atribuicaoid: data.atribuicaoid,
      p_caminho: data.caminho,
      p_observacao: data.observacao,
      p_fotoidunico: fotoidunico,
      p_semhorafoto: semhorafoto,
    });
    if (error) throw new Error(error.message);
    return { nome: pessoa.nome };
  });
