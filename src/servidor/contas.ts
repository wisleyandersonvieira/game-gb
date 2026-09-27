// Funcoes de servidor do painel do administrador geral.
//
// Regras de seguranca desta pasta:
// - A chave service_role NUNCA aparece aqui. Ela e lida dentro de
//   client.server.ts, a partir de process.env (sem o prefixo VITE_), e esse
//   modulo so e carregado por import dinamico dentro do handler, para nao
//   entrar no pacote que vai para o navegador.
// - Toda funcao confere eh_admin_geral() NO SERVIDOR, com o token de quem
//   chamou. Esconder o botao na tela nao e protecao.
import { createServerFn } from "@tanstack/react-start";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import { conferirPasse, emitirPasse } from "@/servidor/segredos";

type ClienteDoUsuario = { rpc: (nome: string) => Promise<{ data: unknown; error: unknown }> };

/** Barra quem nao for o administrador geral. Checado no banco, pelo token. */
async function exigirAdminGeral(supabase: ClienteDoUsuario) {
  const { data, error } = await supabase.rpc("eh_admin_geral");
  if (error) {
    throw new Error("Não foi possível verificar a permissão.");
  }
  if (data !== true) {
    throw new Error("Acesso negado: apenas o administrador geral pode fazer isso.");
  }
}

/** Para onde o convite por e-mail leva. Definido no servidor, nunca pelo navegador. */
function urlDeDestino() {
  const base = process.env["SITE_URL"] ?? "http://localhost:8080";
  return `${base.replace(/\/$/, "")}/definir-senha`;
}

/** Procura um login pelo e-mail, sem depender de ordenação da listagem. */
async function acharUsuarioPorEmail(
  admin: { auth: { admin: { listUsers: (p: { page: number; perPage: number }) => Promise<any> } } },
  email: string,
) {
  const alvo = email.trim().toLowerCase();
  for (let pagina = 1; pagina <= 20; pagina++) {
    const { data, error } = await admin.auth.admin.listUsers({ page: pagina, perPage: 200 });
    if (error) throw new Error(error.message);
    const achado = (data?.users ?? []).find(
      (u: { email?: string }) => (u.email ?? "").toLowerCase() === alvo,
    );
    if (achado) return achado as { id: string; email?: string };
    if ((data?.users ?? []).length < 200) return null;
  }
  return null;
}

/**
 * Cria a conta do cliente e convida o usuario master por e-mail.
 * Se o convite falhar, a conta recem-criada e desfeita, para nao sobrar
 * cadastro pela metade.
 */
export const criarContaEConvidar = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator(
    (d: {
      nome: string;
      nomefantasia?: string;
      responsavel?: string;
      cnpj?: string;
      redeid?: number | null;
      codigo?: string;
      email: string;
      telefone?: string;
      cidade?: string;
      limitelojas: number;
      observacoes?: string;
    }) => d,
  )
  .handler(async ({ data, context }) => {
    await exigirAdminGeral(context.supabase as unknown as ClienteDoUsuario);

    const email = data.email.trim().toLowerCase();
    const nome = data.nome.trim();
    if (!nome) throw new Error("Informe a razão social do cliente.");
    if (!email) throw new Error("Informe o e-mail do usuário master.");
    if (!Number.isInteger(data.limitelojas) || data.limitelojas < 1) {
      throw new Error("O limite de lojas precisa ser um número inteiro de 1 para cima.");
    }

    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");

    // O login ja existe? Entao ou ele ja e de outro cliente (recusa), ou e um
    // login solto que podemos aproveitar.
    const jaExiste = await acharUsuarioPorEmail(supabaseAdmin as any, email);
    if (jaExiste) {
      const { data: vinculo } = await supabaseAdmin
        .from("contasusuarios")
        .select("contaid")
        .eq("userid", jaExiste.id)
        .maybeSingle();
      if (vinculo) {
        throw new Error(
          `O e-mail ${email} já pertence a outro cliente. Um login pertence a uma única conta.`,
        );
      }
    }

    // A conta e criada com o token do admin, passando pela RLS.
    const { data: conta, error: erroConta } = await (context.supabase as any)
      .from("contas")
      .insert({
        nome,
        // Vazio: o banco usa a razão social. Os gatilhos também limpam o CNPJ
        // (só dígitos, conferidos, sem repetir) e conferem o código.
        nomefantasia: data.nomefantasia?.trim() || null,
        responsavel: data.responsavel?.trim() || null,
        cnpj: data.cnpj?.trim() || null,
        redeid: Number.isInteger(data.redeid) ? data.redeid : null,
        codigo: data.codigo?.trim().toLowerCase() || null,
        email,
        telefone: data.telefone?.trim() || null,
        cidade: data.cidade?.trim() || null,
        limitelojas: data.limitelojas,
        observacoes: data.observacoes?.trim() || null,
      })
      .select("contaid")
      .single();

    if (erroConta) {
      if ((erroConta as { code?: string }).code === "23505") {
        throw new Error(`Já existe um cliente cadastrado com o e-mail ${email}.`);
      }
      throw new Error(`Não foi possível criar o cliente: ${erroConta.message}`);
    }

    const desfazer = async () => {
      await supabaseAdmin.from("contas").delete().eq("contaid", conta.contaid);
    };

    let userid: string;
    try {
      if (jaExiste) {
        userid = jaExiste.id;
        const { error } = await supabaseAdmin.auth.resetPasswordForEmail(email, {
          redirectTo: urlDeDestino(),
        });
        if (error) throw new Error(error.message);
      } else {
        const { data: convidado, error } = await supabaseAdmin.auth.admin.inviteUserByEmail(email, {
          redirectTo: urlDeDestino(),
        });
        if (error) throw new Error(error.message);
        if (!convidado?.user?.id) throw new Error("O convite não retornou o login criado.");
        userid = convidado.user.id;
      }
    } catch (e) {
      await desfazer();
      throw new Error(`Cliente não criado: falha ao enviar o convite. ${(e as Error).message}`);
    }

    const { error: erroVinculo } = await supabaseAdmin
      .from("contasusuarios")
      .insert({ contaid: conta.contaid, userid, papel: "master" });

    if (erroVinculo) {
      await desfazer();
      throw new Error(`Cliente não criado: falha ao ligar o login à conta. ${erroVinculo.message}`);
    }

    // Cada cliente novo comeca com as configuracoes padrao e com as 6 tarefas
    // do sistema (feedback, leitura, meta, nota fiscal e os 2 modelos), cujos
    // IDs vao para configuracoes. A ordem importa: as tarefas preenchem
    // chaves criadas pelo passo anterior.
    const { error: erroConfig } = await supabaseAdmin.rpc("cria_configuracoes_padrao", {
      p_contaid: conta.contaid,
    });
    if (erroConfig) {
      throw new Error(
        `O cliente foi criado e o convite enviado, mas as configurações padrão falharam: ${erroConfig.message}`,
      );
    }

    const { error: erroTarefas } = await supabaseAdmin.rpc("cria_tarefas_do_sistema", {
      p_contaid: conta.contaid,
    });
    if (erroTarefas) {
      throw new Error(
        `O cliente foi criado e o convite enviado, mas as tarefas do sistema falharam: ${erroTarefas.message}`,
      );
    }

    // E com o prêmio do sistema "Abate na comanda", escondido do catálogo.
    const { error: erroPremios } = await supabaseAdmin.rpc("cria_produtos_do_sistema", {
      p_contaid: conta.contaid,
    });
    if (erroPremios) {
      throw new Error(
        `O cliente foi criado e o convite enviado, mas o prêmio do sistema falhou: ${erroPremios.message}`,
      );
    }

    // E com um único tipo de evento genérico na agenda; o cliente cadastra os dele.
    const { error: erroTipos } = await supabaseAdmin.rpc("cria_tipos_evento_padrao", {
      p_contaid: conta.contaid,
    });
    if (erroTipos) {
      throw new Error(
        `O cliente foi criado e o convite enviado, mas o tipo de evento padrão falhou: ${erroTipos.message}`,
      );
    }

    // E com as 6 etapas genéricas do onboarding (a conta edita depois).
    const { error: erroEtapas } = await supabaseAdmin.rpc("cria_etapas_onboarding_padrao", {
      p_contaid: conta.contaid,
    });
    if (erroEtapas) {
      throw new Error(
        `O cliente foi criado e o convite enviado, mas as etapas do onboarding falharam: ${erroEtapas.message}`,
      );
    }

    return { contaid: conta.contaid as number, email, reaproveitouLogin: Boolean(jaExiste) };
  });

/** Reenvia o convite para o master de uma conta que ainda nao entrou. */
export const reenviarConvite = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((d: { contaid: number }) => d)
  .handler(async ({ data, context }) => {
    await exigirAdminGeral(context.supabase as unknown as ClienteDoUsuario);

    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");

    const { data: conta, error } = await supabaseAdmin
      .from("contas")
      .select("email")
      .eq("contaid", data.contaid)
      .single();
    if (error || !conta) throw new Error("Cliente não encontrado.");

    const { error: erroEnvio } = await supabaseAdmin.auth.resetPasswordForEmail(conta.email, {
      redirectTo: urlDeDestino(),
    });
    if (erroEnvio) throw new Error(`Não foi possível reenviar: ${erroEnvio.message}`);

    return { email: conta.email };
  });

/** Situacao do login de cada cliente: ja definiu a senha ou ainda nao entrou. */
export const situacaoDosLogins = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    await exigirAdminGeral(context.supabase as unknown as ClienteDoUsuario);

    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");

    const { data: vinculos, error } = await supabaseAdmin
      .from("contasusuarios")
      .select("contaid, userid");
    if (error) throw new Error(error.message);

    const { data: usuarios, error: erroUsuarios } = await supabaseAdmin.auth.admin.listUsers({
      page: 1,
      perPage: 200,
    });
    if (erroUsuarios) throw new Error(erroUsuarios.message);

    const porId = new Map(
      (usuarios?.users ?? []).map((u: any) => [u.id as string, Boolean(u.last_sign_in_at)]),
    );

    return (vinculos ?? []).map((v) => ({
      contaid: v.contaid as number,
      jaEntrou: porId.get(v.userid as string) ?? false,
    }));
  });

// ---------------------------------------------------------------------------
// Anexos da administração e logotipo das redes (27/09/2026)
// ---------------------------------------------------------------------------
// Contratos têm dado pessoal dentro: são tratados como documento SIGILOSO.
// Os dois buckets são privados e não têm regra de acesso para ninguém — só o
// servidor chega neles, e só depois de conferir que quem pediu é o admin
// geral. O arquivo sobe direto do navegador para o Storage, com uma
// autorização de poucos minutos para UM caminho; o registro só é gravado
// depois que o servidor confere, no próprio Storage, tamanho e tipo.

const BUCKET_ANEXOS = "administracao";
const BUCKET_LOGOS = "logos-redes";
export const TIPOS_ANEXO: Record<string, string> = {
  "application/pdf": "pdf",
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
};
export const TIPOS_LOGO: Record<string, string> = { "image/png": "png", "image/jpeg": "jpg", "image/webp": "webp" };
export const MAXIMO_ANEXO = 10 * 1024 * 1024;
export const MAXIMO_LOGO = 512 * 1024;
/** O link para abrir um anexo ou ver um logotipo vale isto (segundos). */
const LINK_SEGUNDOS = 300;

type Alvo = { alvo: "conta" | "rede"; id: number };
const assuntoDoEnvio = (caminho: string, tipo: string, tamanho: number) => `envio:${caminho}:${tipo}:${tamanho}`;

function conferirAlvo(d: Partial<Alvo>): Alvo {
  if (d?.alvo !== "conta" && d?.alvo !== "rede") throw new Error("Diga de quem é o anexo.");
  if (!Number.isInteger(d.id) || (d.id as number) <= 0) throw new Error("Cliente ou rede inválido.");
  return { alvo: d.alvo, id: d.id as number };
}

/** Confere no próprio Storage que o arquivo chegou com o tamanho e o tipo prometidos. */
async function conferirArquivo(bucket: string, caminho: string, tipo: string, tamanho: number) {
  const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
  const pasta = caminho.slice(0, caminho.lastIndexOf("/"));
  const nome = caminho.slice(caminho.lastIndexOf("/") + 1);
  const { data } = await supabaseAdmin.storage.from(bucket).list(pasta, { search: nome, limit: 5 });
  const obj = (data ?? []).find((o) => o.name === nome) as
    | { metadata?: { size?: number; mimetype?: string } }
    | undefined;
  if (!obj) throw new Error("O arquivo não chegou. Tente enviar de novo.");
  const real = obj.metadata?.size ?? -1;
  if (real !== tamanho || (obj.metadata?.mimetype && obj.metadata.mimetype !== tipo)) {
    await supabaseAdmin.storage.from(bucket).remove([caminho]).catch(() => undefined);
    throw new Error("O arquivo que chegou não é o que foi autorizado. Envie de novo.");
  }
}

export const autorizarAnexoAdmin = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((d: { alvo: "conta" | "rede"; id: number; tipo: string; tamanho: number }) => {
    const a = conferirAlvo(d);
    if (!TIPOS_ANEXO[d?.tipo]) throw new Error("Só PDF ou imagem (JPG, PNG, WEBP).");
    if (!Number.isInteger(d?.tamanho) || d.tamanho <= 0 || d.tamanho > MAXIMO_ANEXO) {
      throw new Error("O arquivo passa de 10 MB.");
    }
    return { ...a, tipo: d.tipo, tamanho: d.tamanho };
  })
  .handler(async ({ data, context }) => {
    await exigirAdminGeral(context.supabase as unknown as ClienteDoUsuario);
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { data: existe } =
      data.alvo === "conta"
        ? await supabaseAdmin.from("contas").select("contaid").eq("contaid", data.id).maybeSingle()
        : await supabaseAdmin.from("redes").select("redeid").eq("redeid", data.id).maybeSingle();
    if (!existe) throw new Error(data.alvo === "conta" ? "Cliente não encontrado." : "Rede não encontrada.");

    const caminho = `${data.alvo}s/${data.id}/${crypto.randomUUID()}.${TIPOS_ANEXO[data.tipo]}`;
    const { data: envio, error } = await supabaseAdmin.storage.from(BUCKET_ANEXOS).createSignedUploadUrl(caminho);
    if (error || !envio) throw new Error("Não foi possível preparar o envio.");
    const { userId } = context as unknown as { userId: string };
    return {
      caminho,
      token: envio.token,
      passe: await emitirPasse(assuntoDoEnvio(caminho, data.tipo, data.tamanho), `${data.alvo}:${data.id}:${userId}`),
    };
  });

export const registrarAnexoAdmin = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator(
    (d: { alvo: "conta" | "rede"; id: number; caminho: string; passe: string; nome: string; tipo: string; tamanho: number }) => {
      const a = conferirAlvo(d);
      if (typeof d?.caminho !== "string" || typeof d?.passe !== "string") throw new Error("Envio inválido.");
      return {
        ...a,
        caminho: d.caminho.slice(0, 300),
        passe: d.passe.slice(0, 200),
        nome: (typeof d.nome === "string" ? d.nome : "arquivo").slice(0, 200),
        tipo: String(d.tipo),
        tamanho: Number(d.tamanho),
      };
    },
  )
  .handler(async ({ data, context }) => {
    await exigirAdminGeral(context.supabase as unknown as ClienteDoUsuario);
    const { userId } = context as unknown as { userId: string };
    // O passe prova que ESTE servidor autorizou este caminho, com este tipo e
    // este tamanho, para este cliente (ou rede), há menos de 15 minutos.
    await conferirPasse(data.passe, assuntoDoEnvio(data.caminho, data.tipo, data.tamanho), `${data.alvo}:${data.id}:${userId}`, 15);
    await conferirArquivo(BUCKET_ANEXOS, data.caminho, data.tipo, data.tamanho);

    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { error } = await supabaseAdmin.from("anexosadmin").insert({
      contaid: data.alvo === "conta" ? data.id : null,
      redeid: data.alvo === "rede" ? data.id : null,
      nomearquivo: data.nome,
      caminho: data.caminho,
      tipo: data.tipo,
      tamanho: data.tamanho,
      enviadopor: userId,
    });
    if (error) throw new Error(`Não foi possível registrar o anexo: ${error.message}`);
    return { ok: true as const };
  });

/** Um link para abrir o anexo, que vale 5 minutos. */
export const abrirAnexoAdmin = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((d: { anexoid: number }) => {
    if (!Number.isInteger(d?.anexoid)) throw new Error("Anexo inválido.");
    return { anexoid: d.anexoid };
  })
  .handler(async ({ data, context }) => {
    await exigirAdminGeral(context.supabase as unknown as ClienteDoUsuario);
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { data: anexo } = await supabaseAdmin
      .from("anexosadmin").select("caminho").eq("anexoid", data.anexoid).maybeSingle();
    if (!anexo) throw new Error("Anexo não encontrado.");
    const { data: link, error } = await supabaseAdmin.storage
      .from(BUCKET_ANEXOS).createSignedUrl(anexo.caminho, LINK_SEGUNDOS);
    if (error || !link) throw new Error("Não foi possível abrir o anexo agora.");
    return { url: link.signedUrl };
  });

export const autorizarLogoRede = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((d: { redeid: number; tipo: string; tamanho: number }) => {
    if (!Number.isInteger(d?.redeid)) throw new Error("Rede inválida.");
    if (!TIPOS_LOGO[d?.tipo]) throw new Error("O logotipo tem de ser PNG, JPG ou WEBP.");
    if (!Number.isInteger(d?.tamanho) || d.tamanho <= 0 || d.tamanho > MAXIMO_LOGO) {
      throw new Error("O logotipo passa de 512 KB. Use uma imagem menor.");
    }
    return { redeid: d.redeid, tipo: d.tipo, tamanho: d.tamanho };
  })
  .handler(async ({ data, context }) => {
    await exigirAdminGeral(context.supabase as unknown as ClienteDoUsuario);
    const { userId } = context as unknown as { userId: string };
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const caminho = `redes/${data.redeid}/${crypto.randomUUID()}.${TIPOS_LOGO[data.tipo]}`;
    const { data: envio, error } = await supabaseAdmin.storage.from(BUCKET_LOGOS).createSignedUploadUrl(caminho);
    if (error || !envio) throw new Error("Não foi possível preparar o envio.");
    return {
      caminho,
      token: envio.token,
      passe: await emitirPasse(assuntoDoEnvio(caminho, data.tipo, data.tamanho), `rede:${data.redeid}:${userId}`),
    };
  });

export const registrarLogoRede = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((d: { redeid: number; caminho: string; passe: string; tipo: string; tamanho: number }) => {
    if (!Number.isInteger(d?.redeid) || typeof d?.caminho !== "string" || typeof d?.passe !== "string") {
      throw new Error("Envio inválido.");
    }
    return { redeid: d.redeid, caminho: d.caminho.slice(0, 300), passe: d.passe.slice(0, 200), tipo: String(d.tipo), tamanho: Number(d.tamanho) };
  })
  .handler(async ({ data, context }) => {
    await exigirAdminGeral(context.supabase as unknown as ClienteDoUsuario);
    const { userId } = context as unknown as { userId: string };
    await conferirPasse(data.passe, assuntoDoEnvio(data.caminho, data.tipo, data.tamanho), `rede:${data.redeid}:${userId}`, 15);
    await conferirArquivo(BUCKET_LOGOS, data.caminho, data.tipo, data.tamanho);

    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { data: antes } = await supabaseAdmin.from("redes").select("logocaminho").eq("redeid", data.redeid).maybeSingle();
    const { error } = await supabaseAdmin.from("redes").update({ logocaminho: data.caminho }).eq("redeid", data.redeid);
    if (error) throw new Error(`Não foi possível salvar o logotipo: ${error.message}`);
    // O logotipo anterior sai do Storage: não fica arquivo órfão.
    if (antes?.logocaminho) await supabaseAdmin.storage.from(BUCKET_LOGOS).remove([antes.logocaminho]).catch(() => undefined);
    return { ok: true as const };
  });

/** Os logotipos das redes, com links de 5 minutos (o bucket é privado). */
export const logosDasRedes = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    await exigirAdminGeral(context.supabase as unknown as ClienteDoUsuario);
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { data: redes } = await supabaseAdmin.from("redes").select("redeid, logocaminho").not("logocaminho", "is", null);
    const lista = (redes ?? []) as { redeid: number; logocaminho: string }[];
    if (lista.length === 0) return {} as Record<number, string>;
    const { data: links } = await supabaseAdmin.storage
      .from(BUCKET_LOGOS).createSignedUrls(lista.map((r) => r.logocaminho), LINK_SEGUNDOS);
    const porCaminho = new Map((links ?? []).map((l) => [l.path, l.signedUrl]));
    return Object.fromEntries(lista.map((r) => [r.redeid, porCaminho.get(r.logocaminho) ?? ""])) as Record<number, string>;
  });
