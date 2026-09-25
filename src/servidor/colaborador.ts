// Etapa 1.12, parte C1: o celular do colaborador.
//
// O celular NAO fala com o banco: para o colaborador `minha_conta()` responde
// vazio e as regras de acesso negam tudo. Tudo passa por aqui, e daqui para as
// funcoes `eu_*`, que sao as unicas portas.
//
// Quem e a pessoa vem SEMPRE do token, nunca do navegador. E o que impede
// alguem de pedir o extrato do colega trocando um numero.
//
// ACEITAR tarefa continua sendo so no tablet da loja. O celular entrega,
// consulta e pede.
import { createServerFn } from "@tanstack/react-start";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import { conferirBilhete, conferirHoraDaFoto, emitirBilhete, provaDaFoto } from "@/servidor/fotodaentrega";

type ClienteDoUsuario = {
  rpc: (nome: string, args?: Record<string, unknown>) => Promise<{ data: unknown; error: unknown }>;
};

type Pessoa = { contaid: number; funcionarioid: number };

/**
 * Quem esta pedindo — pelo TOKEN. Pessoa desligada, loja desativada ou conta
 * cancelada caem aqui na hora: meu_acesso responde "desligado".
 */
async function pessoaDoToken(supabase: ClienteDoUsuario, userId: string): Promise<Pessoa> {
  const { data, error } = await supabase.rpc("meu_acesso");
  if (error) throw new Error("Não foi possível confirmar o seu acesso.");
  const acesso = data as { tipo?: string } | null;
  if (acesso?.tipo === "desligado") throw new Error("Seu acesso foi encerrado. Fale com o seu gestor.");
  if (acesso?.tipo !== "colaborador") throw new Error("Esta tela é do aplicativo do colaborador.");

  // O primeiro acesso é uma PORTA, não um aviso de tela. A senha provisória
  // são os seis primeiros dígitos do CPF, que o gestor e os colegas conhecem:
  // quem entra com ela não pode ler o extrato nem entregar em nome de
  // ninguém antes de trocar a senha, escolher o PIN e dar ciência na política.
  const a = acesso as { semsenha?: boolean; sempin?: boolean; politicapendente?: boolean };
  if (a.semsenha || a.sempin || a.politicapendente) {
    throw new Error("Termine o primeiro acesso antes de usar o aplicativo.");
  }

  const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
  const { data: vinculo, error: erro } = await supabaseAdmin
    .from("contasusuarios")
    .select("contaid, funcionarioid")
    .eq("userid", userId)
    .single();
  if (erro || !vinculo?.funcionarioid) throw new Error("Cadastro não encontrado.");
  return { contaid: vinculo.contaid, funcionarioid: vinculo.funcionarioid };
}

export type MeuInicio = {
  nome: string;
  /** Sempre em PONTOS. Nunca convertido em dinheiro nesta visão. */
  saldo: number;
  nota: number | null;
  feedbackpendente: boolean;
  comunicados: number;
};

export const meuInicio = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    const { supabase, userId } = context as unknown as { supabase: ClienteDoUsuario; userId: string };
    const p = await pessoaDoToken(supabase, userId);
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { data, error } = await supabaseAdmin.rpc("eu_inicio", {
      p_contaid: p.contaid, p_funcionarioid: p.funcionarioid,
    });
    if (error) throw new Error("Não foi possível carregar agora.");
    return data as unknown as MeuInicio;
  });

export type MinhaTarefa = {
  atribuicaoid: number;
  titulo: string;
  pontos: number;
  loja: string | null;
  /** Hora em que ela pegou a tarefa no tablet. Vazio na tarefa que já é dela. */
  pegaem: string | null;
  situacao: "a_fazer" | "esperando" | "aprovada" | "recusada";
  /** false enquanto não chegou a hora de liberação. */
  liberada: boolean;
  /** Quando ela libera hoje. Vazio = o dia todo. */
  liberaas: string | null;
};

export const minhasTarefas = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    const { supabase, userId } = context as unknown as { supabase: ClienteDoUsuario; userId: string };
    const p = await pessoaDoToken(supabase, userId);
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { data, error } = await supabaseAdmin.rpc("eu_tarefas", {
      p_contaid: p.contaid, p_funcionarioid: p.funcionarioid,
    });
    if (error) throw new Error("Não foi possível carregar as suas tarefas agora.");
    return (data ?? []) as unknown as MinhaTarefa[];
  });

/**
 * Autorizacao de envio da foto: vale por poucos minutos e so para a pasta da
 * loja daquela tarefa. A chave secreta nunca sai do servidor.
 */
/**
 * Os tipos do TypeScript somem na compilação: quem chama por fora manda o que
 * quiser. Estas conferências são as que valem de verdade.
 */
function numeroDeTarefa(v: unknown): number {
  if (!Number.isInteger(v) || (v as number) <= 0) throw new Error("Tarefa inválida.");
  return v as number;
}

function textoCurto(v: unknown, limite: number): string | null {
  if (v === null || v === undefined || v === "") return null;
  if (typeof v !== "string") throw new Error("Texto inválido.");
  return v.slice(0, limite);
}

export const autorizacaoDeFotoDoCelular = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((d: { atribuicaoid: number }) => ({ atribuicaoid: numeroDeTarefa(d?.atribuicaoid) }))
  .handler(async ({ data, context }) => {
    const { supabase, userId } = context as unknown as { supabase: ClienteDoUsuario; userId: string };
    const p = await pessoaDoToken(supabase, userId);
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");

    // A loja sai da TAREFA, e a tarefa tem de ser dela: o navegador não
    // escolhe a pasta.
    const { data: tarefa } = await supabaseAdmin
      .from("tarefasatribuidas")
      .select("lojaid")
      .eq("contaid", p.contaid)
      .eq("atribuicaoid", data.atribuicaoid)
      .eq("funcionarioid", p.funcionarioid)
      .maybeSingle();
    if (!tarefa?.lojaid) throw new Error("Esta tarefa não é sua.");

    const caminho = `${p.contaid}/${tarefa.lojaid}/${crypto.randomUUID()}.jpg`;
    const { data: envio, error } = await supabaseAdmin.storage.from("entregas").createSignedUploadUrl(caminho);
    if (error || !envio) throw new Error("Não foi possível preparar o envio da foto.");

    // O bilhete amarra este caminho a esta pessoa, a esta tarefa e a este
    // instante. Sem ele, dava para declarar uma foto que nunca subiu.
    const bilhete = await emitirBilhete(caminho, data.atribuicaoid, p.funcionarioid);
    return { caminho, token: envio.token, bilhete };
  });

export const entregarPeloCelular = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((d: { atribuicaoid: number; caminho?: string | null; bilhete?: string | null; observacao?: string | null }) => ({
    atribuicaoid: numeroDeTarefa(d?.atribuicaoid),
    caminho: textoCurto(d?.caminho, 300),
    bilhete: textoCurto(d?.bilhete, 200),
    observacao: textoCurto(d?.observacao, 1000),
  }))
  .handler(async ({ data, context }) => {
    const { supabase, userId } = context as unknown as { supabase: ClienteDoUsuario; userId: string };
    const p = await pessoaDoToken(supabase, userId);

    // A foto: NADA do que o navegador diz sobre ela é aceito. O caminho tem de
    // vir com o bilhete que este servidor emitiu, e as duas provas — a
    // impressão digital e a hora em que foi tirada — saem do arquivo, aqui.
    let fotoidunico: string | null = null;
    let semhorafoto = false;
    if (data.caminho) {
      if (!data.bilhete) throw new Error("Envio de foto inválido.");
      await conferirBilhete(data.bilhete, data.caminho, data.atribuicaoid, p.funcionarioid);
      const prova = await provaDaFoto(data.caminho);
      fotoidunico = prova.fotoidunico;
      ({ semhorafoto } = await conferirHoraDaFoto(p.contaid, prova.horafoto));
    }

    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { data: id, error } = await supabaseAdmin.rpc("eu_entregar", {
      p_contaid: p.contaid,
      p_funcionarioid: p.funcionarioid,
      p_atribuicaoid: data.atribuicaoid,
      p_caminho: data.caminho,
      p_observacao: data.observacao,
      p_fotoidunico: fotoidunico,
      p_semhorafoto: semhorafoto,
    });
    if (error) throw new Error(error.message);
    return { entregaid: id as number, semhorafoto };
  });

export type MeuExtrato = {
  saldo: number;
  linhas: { quando: string; pontos: number; tipo: string; descricao: string }[];
};

export const meuExtrato = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((d: { de: string; ate: string }) => {
    const dia = (v: unknown) => {
      if (typeof v !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(v)) throw new Error("Data inválida.");
      return v;
    };
    return { de: dia(d?.de), ate: dia(d?.ate) };
  })
  .handler(async ({ data, context }) => {
    const { supabase, userId } = context as unknown as { supabase: ClienteDoUsuario; userId: string };
    const p = await pessoaDoToken(supabase, userId);
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { data: extrato, error } = await supabaseAdmin.rpc("eu_extrato", {
      p_contaid: p.contaid, p_funcionarioid: p.funcionarioid, p_de: data.de, p_ate: data.ate,
    });
    if (error) throw new Error("Não foi possível carregar o extrato agora.");
    return extrato as unknown as MeuExtrato;
  });

export type PremioParaMim = { produtoid: number; nome: string; custo: number; estoque: number | null; cabe: boolean };
export type CatalogoDela = { saldo: number; premios: PremioParaMim[] };

export const meusPremios = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    const { supabase, userId } = context as unknown as { supabase: ClienteDoUsuario; userId: string };
    const p = await pessoaDoToken(supabase, userId);
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { data, error } = await supabaseAdmin.rpc("eu_premios", {
      p_contaid: p.contaid, p_funcionarioid: p.funcionarioid,
    });
    if (error) throw new Error("Não foi possível carregar os prêmios agora.");
    return data as unknown as CatalogoDela;
  });

export type MeuResgate = {
  resgateid: number;
  nome: string;
  pontos: number;
  quando: string;
  status: string;
};

export const meusResgates = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    const { supabase, userId } = context as unknown as { supabase: ClienteDoUsuario; userId: string };
    const p = await pessoaDoToken(supabase, userId);
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { data, error } = await supabaseAdmin.rpc("eu_resgates", {
      p_contaid: p.contaid, p_funcionarioid: p.funcionarioid,
    });
    if (error) throw new Error("Não foi possível carregar os seus pedidos agora.");
    return (data ?? []) as unknown as MeuResgate[];
  });

/**
 * Pedir resgate. Quem pede sai do TOKEN, nunca do navegador.
 *
 * O saldo e o estoque são conferidos no banco, no momento do pedido, lendo o
 * livro de pontos — nunca um saldo que a tela calculou.
 */
export const pedirResgate = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((d: { produtoid?: number | null; valorreais?: number | null }) => ({
    produtoid: Number.isInteger(d?.produtoid) ? (d.produtoid as number) : null,
    valorreais:
      typeof d?.valorreais === "number" && Number.isFinite(d.valorreais) ? d.valorreais : null,
  }))
  .handler(async ({ data, context }) => {
    const { supabase, userId } = context as unknown as { supabase: ClienteDoUsuario; userId: string };
    const p = await pessoaDoToken(supabase, userId);
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");

    // A LOJA do pedido, quando não há dúvida: quem trabalha numa loja só tem
    // o pedido atribuído a ela, e o gestor vê de onde veio na lista de
    // resgates. Quem trabalha em várias fica sem loja, porque adivinhar seria
    // pior do que deixar em branco. Quem decide é o servidor, nunca a tela.
    const { data: lojas } = await supabaseAdmin
      .from("funcionarioslojas")
      .select("lojaid")
      .eq("contaid", p.contaid)
      .eq("funcionarioid", p.funcionarioid)
      .eq("ativo", true);
    const umaLojaSo = (lojas ?? []).length === 1 ? (lojas![0].lojaid as number) : null;

    const { data: id, error } = await supabaseAdmin.rpc("eu_pedir_resgate", {
      p_contaid: p.contaid,
      p_funcionarioid: p.funcionarioid,
      p_produtoid: data.produtoid,
      p_valorreais: data.valorreais,
      p_lojaid: umaLojaSo,
    });
    // A mensagem do banco sobe inteira: ela diz o motivo (saldo, estoque,
    // limite), e é o que a pessoa precisa ler.
    if (error) throw new Error(error.message);
    return { resgateid: id as number };
  });

/** Desistir enquanto está pendente: devolve pontos e estoque. */
export const desistirDoResgate = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((d: { resgateid: number }) => {
    if (!Number.isInteger(d?.resgateid) || d.resgateid <= 0) throw new Error("Pedido não encontrado.");
    return { resgateid: d.resgateid };
  })
  .handler(async ({ data, context }) => {
    const { supabase, userId } = context as unknown as { supabase: ClienteDoUsuario; userId: string };
    const p = await pessoaDoToken(supabase, userId);
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { error } = await supabaseAdmin.rpc("eu_cancelar_resgate", {
      p_contaid: p.contaid, p_funcionarioid: p.funcionarioid, p_resgateid: data.resgateid,
    });
    if (error) throw new Error(error.message);
    return { ok: true as const };
  });
