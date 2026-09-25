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
import { abrirTentativa, conferirPasse, emitirPasse, fecharTentativa, origemDaChamada, embaralhar, resumoDoPin } from "@/servidor/segredos";
import { conferirBilhete, conferirHoraDaFoto, emitirBilhete, provaDaFoto } from "@/servidor/fotodaentrega";

/**
 * Se o tablet toca som quando chega tarefa nova, em que volume, e de quantos
 * em quantos minutos ele repete o aviso enquanto ninguém aceita.
 *
 * Vem da LOJA, não da conta e não do aparelho: uma loja de shopping com música
 * alta e um quiosque silencioso não aceitam o mesmo volume, e quem regula é
 * quem está lá, ouvindo. Só o tablet recebe isto — o celular da pessoa, nunca.
 */
async function somDaLoja(
  contaid: number,
  lojaid: number,
): Promise<{ ligado: boolean; volume: number; repetirminutos: number }> {
  const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
  const { data } = await supabaseAdmin
    .from("lojas")
    .select("somtarefanova, somvolume, somrepetirminutos")
    .eq("contaid", contaid)
    .eq("lojaid", lojaid)
    .maybeSingle();
  return {
    // Loja que por algum motivo veio sem resposta: ligado no médio, como o
    // padrão da coluna. O tablet nunca fica sem aviso por falta de dado.
    ligado: data?.somtarefanova ?? true,
    volume: data?.somvolume ?? 19,
    repetirminutos: data?.somrepetirminutos ?? 0,
  };
}

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
  /** Quem entregou (nome curto), quando, e em que pé está a entrega. */
  feitapor: string | null;
  feitaem: string | null;
  feitasituacao: "Pendente" | "Aprovada" | null;
  /** false enquanto não chegou a hora de liberação. */
  liberada: boolean;
  /** Quando ela libera hoje. Vazio = o dia todo. */
  liberaas: string | null;
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
      som: await somDaLoja(t.contaid, t.lojaid),
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

/**
 * Abrir pedido (compra ou manutenção) pelo tablet.
 *
 * QUEM PEDIU e EM QUE LOJA saem daqui: a loja vem do tablet pareado e a pessoa
 * vem do PIN que este servidor conferiu. O navegador manda só o que a pessoa
 * digitou — nunca quem ela é.
 *
 * Usa a MESMA trava de tentativas do pegar tarefa: não existe um caminho de
 * PIN separado.
 */
export const abrirPedidoNoTablet = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator(
    (d: {
      passe: string;
      funcionarioid: number;
      tipo: "Compra" | "Manutencao";
      descricao?: string | null;
      quantidade?: number | null;
      unidade?: string | null;
      observacao?: string | null;
    }) => {
      if (typeof d?.passe !== "string") throw new Error("Confirme o seu PIN de novo.");
      if (!Number.isInteger(d?.funcionarioid)) throw new Error("Confirme o seu PIN de novo.");
      if (d?.tipo !== "Compra" && d?.tipo !== "Manutencao") throw new Error("Escolha Compra ou Manutenção.");
      return {
        passe: d.passe,
        funcionarioid: d.funcionarioid,
        tipo: d.tipo,
        descricao: typeof d.descricao === "string" ? d.descricao.slice(0, 500) : "",
        // Número de verdade: texto vira nulo, e o banco recusa.
        quantidade: typeof d.quantidade === "number" && Number.isFinite(d.quantidade) ? d.quantidade : null,
        unidade: typeof d.unidade === "string" ? d.unidade.slice(0, 20) : null,
        observacao: typeof d.observacao === "string" ? d.observacao.slice(0, 500) : null,
      };
    },
  )
  .handler(async ({ data, context }) => {
    const { supabase, userId } = context as unknown as { supabase: ClienteDoUsuario; userId: string };
    const t = await tabletDoToken(supabase, userId);
    // O passe prova que ESTE servidor conferiu o PIN desta pessoa, neste
    // tablet, há poucos minutos. Trocar o número aqui não adianta: a
    // assinatura não bate.
    await conferirPasse(data.passe, `pedido:${t.contaid}:${t.lojaid}`, String(data.funcionarioid));

    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { error } = await supabaseAdmin.rpc("visao_abrir_pedido", {
      p_contaid: t.contaid,
      p_lojaid: t.lojaid,
      p_funcionarioid: data.funcionarioid,
      p_tipo: data.tipo,
      p_descricao: data.descricao,
      p_quantidade: data.quantidade,
      p_unidade: data.unidade,
      p_observacao: data.observacao,
    });
    if (error) throw new Error(error.message);
    return { ok: true as const };
  });

/** Só confere o PIN e devolve o nome: é o que abre a tela do pedido. */
export const conferirPinNoTablet = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((d: { pin: string; assunto?: string }) => ({
    pin: typeof d?.pin === "string" ? d.pin : "",
    // Só os assuntos que existem: o navegador não inventa um.
    assunto: d?.assunto === "mural" ? "mural" : "pedido",
  }))
  .handler(async ({ data, context }) => {
    const { supabase, userId } = context as unknown as { supabase: ClienteDoUsuario; userId: string };
    const t = await tabletDoToken(supabase, userId);
    const pessoa = await pessoaDoPin(t, data.pin);
    // O passe substitui o PIN enquanto a pessoa preenche: a tela não guarda o
    // número. Dois minutos cobrem os 90 segundos da tela com folga.
    return {
      nome: pessoa.nome,
      // Um passe por ASSUNTO: o de pedido não abre o mural, e vice-versa.
      passe: await emitirPasse(`${data.assunto}:${t.contaid}:${t.lojaid}`, String(pessoa.funcionarioid)),
      funcionarioid: pessoa.funcionarioid,
    };
  });

export type ComunicadoDoMural = {
  assinaturaid: number;
  titulo: string;
  conteudo: string;
  pontos: number;
  quando: string;
};

/**
 * O mural DELA: só os comunicados que ainda esperam ciência.
 *
 * Nada de lista dos colegas nem de histórico — o tablet é compartilhado, e o
 * que aparece nele é visto por quem passa. Quem é a pessoa vem do PASSE que
 * este servidor assinou depois de conferir o PIN.
 */
export const muralDoTablet = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((d: { passe: string; funcionarioid: number }) => {
    if (typeof d?.passe !== "string") throw new Error("Confirme o seu PIN de novo.");
    if (!Number.isInteger(d?.funcionarioid)) throw new Error("Confirme o seu PIN de novo.");
    return { passe: d.passe, funcionarioid: d.funcionarioid };
  })
  .handler(async ({ data, context }) => {
    const { supabase, userId } = context as unknown as { supabase: ClienteDoUsuario; userId: string };
    const t = await tabletDoToken(supabase, userId);
    await conferirPasse(data.passe, `mural:${t.contaid}:${t.lojaid}`, String(data.funcionarioid));

    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { data: lista, error } = await supabaseAdmin.rpc("visao_mural", {
      p_contaid: t.contaid, p_lojaid: t.lojaid, p_funcionarioid: data.funcionarioid,
    });
    if (error) throw new Error("Não foi possível abrir o mural agora.");
    return (lista ?? []) as unknown as ComunicadoDoMural[];
  });

/** Dar ciência. Paga o bônus quando há, e nunca paga duas vezes. */
export const darCienciaNoTablet = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((d: { passe: string; funcionarioid: number; assinaturaid: number }) => {
    if (typeof d?.passe !== "string") throw new Error("Confirme o seu PIN de novo.");
    if (!Number.isInteger(d?.funcionarioid) || !Number.isInteger(d?.assinaturaid)) {
      throw new Error("Comunicado não encontrado.");
    }
    return { passe: d.passe, funcionarioid: d.funcionarioid, assinaturaid: d.assinaturaid };
  })
  .handler(async ({ data, context }) => {
    const { supabase, userId } = context as unknown as { supabase: ClienteDoUsuario; userId: string };
    const t = await tabletDoToken(supabase, userId);
    await conferirPasse(data.passe, `mural:${t.contaid}:${t.lojaid}`, String(data.funcionarioid));

    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { data: novo, error } = await supabaseAdmin.rpc("visao_dar_ciencia", {
      p_contaid: t.contaid,
      p_lojaid: t.lojaid,
      p_funcionarioid: data.funcionarioid,
      p_assinaturaid: data.assinaturaid,
    });
    if (error) throw new Error(error.message);
    return { novo: novo === true };
  });
