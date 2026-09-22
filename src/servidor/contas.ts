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
    if (!nome) throw new Error("Informe o nome do cliente.");
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
