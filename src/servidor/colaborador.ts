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
export const autorizacaoDeFotoDoCelular = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((d: { atribuicaoid: number }) => d)
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
    return { caminho, url: envio.signedUrl, token: envio.token };
  });

export const entregarPeloCelular = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator(
    (d: {
      atribuicaoid: number;
      caminho?: string | null;
      observacao?: string | null;
      /** Impressão digital da imagem, calculada no navegador. */
      fotoidunico?: string | null;
      /**
       * Hora em que a foto foi tirada (EXIF), quando o arquivo traz. Vem como
       * texto ISO. Vazio quando o celular apagou esse dado — e aí a entrega
       * entra MARCADA, que é o pior dos dois lados para quem quisesse burlar.
       */
      horafoto?: string | null;
      /** Quando a tela abriu a entrega: a janela de 10 min é conferida aqui. */
      abertaem?: number;
    }) => d,
  )
  .handler(async ({ data, context }) => {
    const { supabase, userId } = context as unknown as { supabase: ClienteDoUsuario; userId: string };
    const p = await pessoaDoToken(supabase, userId);

    // Janela de 10 minutos entre abrir a entrega e enviar, como no bot.
    if (data.abertaem && Date.now() - data.abertaem > 10 * 60_000) {
      throw new Error("Passaram-se mais de 10 minutos. Abra a entrega de novo e tire outra foto.");
    }

    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");

    // Quem decide se a foto é recente é o SERVIDOR, com a tolerância da conta.
    // O navegador só conta o que leu do arquivo.
    let semhorafoto = true;
    if (data.horafoto) {
      const { data: cfg } = await supabaseAdmin
        .from("configuracoes")
        .select("valor")
        .eq("contaid", p.contaid)
        .eq("chave", "MAX_DIFERENCA_FOTO_SEGUNDOS")
        .maybeSingle();
      const tolerancia = Number(cfg?.valor ?? 120) * 1000;
      const diferenca = Math.abs(Date.now() - new Date(data.horafoto).getTime());
      if (Number.isNaN(diferenca)) throw new Error("Não foi possível ler a hora da foto.");
      if (diferenca > tolerancia) {
        throw new Error("Esta foto não é de agora. Tire a foto na hora de entregar.");
      }
      semhorafoto = false;
    }

    const { data: id, error } = await supabaseAdmin.rpc("eu_entregar", {
      p_contaid: p.contaid,
      p_funcionarioid: p.funcionarioid,
      p_atribuicaoid: data.atribuicaoid,
      p_caminho: data.caminho ?? null,
      p_observacao: data.observacao ?? null,
      p_fotoidunico: data.fotoidunico ?? null,
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
  .validator((d: { de: string; ate: string }) => d)
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
