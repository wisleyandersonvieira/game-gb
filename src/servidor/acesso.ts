// Funcoes de servidor da Etapa 1.12, parte A: os acessos de LOJA e de
// COLABORADOR.
//
// Regras desta pasta (iguais as de contas.ts):
// - A chave service_role NUNCA aparece aqui: e lida dentro de client.server.ts,
//   por import dinamico dentro do handler.
// - Quem confere permissao e o SERVIDOR, com o token de quem chamou.
//
// Por que tudo passa por aqui:
// - O PIN e embaralhado com uma chave que so o servidor tem
//   (STGAME_PIN_PEPPER). O banco nunca ve o numero, e quem tiver so o banco
//   nao consegue testar numero nenhum.
// - A trava de tentativas (5 erros) e nossa, nao do Supabase.
// - Os acessos novos nao leem nenhuma tabela pelo endereco: minha_conta()
//   responde vazio para eles.
import { createServerFn } from "@tanstack/react-start";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import { SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY } from "@/integrations/supabase/config-publica";

const DOMINIO_COLABORADOR = "colaborador.stgame.local";
const DOMINIO_LOJA = "loja.stgame.local";

type ClienteDoUsuario = { rpc: (nome: string, args?: Record<string, unknown>) => Promise<{ data: unknown; error: unknown }> };

/** Barra quem nao for o master da conta. Checado no banco, pelo token. */
async function exigirMaster(supabase: ClienteDoUsuario) {
  const { data, error } = await supabase.rpc("sou_master");
  if (error) throw new Error("Não foi possível verificar a permissão.");
  if (data !== true) throw new Error("Acesso negado: só o dono da conta pode fazer isso.");
}

async function contaDoMaster(supabase: ClienteDoUsuario) {
  const { data, error } = await supabase.rpc("minha_conta");
  if (error || typeof data !== "number") throw new Error("Não foi possível descobrir a sua conta.");
  return data;
}

/**
 * Embaralha com a chave do servidor (HMAC-SHA256). O resultado e sempre o
 * mesmo para o mesmo numero, e so por isso o banco acha a pessoa direto pelo
 * indice — sem comparar uma a uma, que ficaria lento com 20+ pessoas.
 */
async function embaralhar(valor: string) {
  const chave = process.env["STGAME_PIN_PEPPER"];
  if (!chave || chave.length < 16) {
    throw new Error("Falta a chave STGAME_PIN_PEPPER no servidor (Secrets do Lovable).");
  }
  const codificador = new TextEncoder();
  const material = await crypto.subtle.importKey(
    "raw",
    codificador.encode(chave),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const assinatura = await crypto.subtle.sign("HMAC", material, codificador.encode(valor));
  return [...new Uint8Array(assinatura)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

const soNumeros = (v: string) => (v ?? "").replace(/\D/g, "");

/** PIN e senha inicial: os 6 primeiros digitos do CPF. */
const inicialDoCpf = (cpf: string) => soNumeros(cpf).slice(0, 6);

/** E-mail interno, montado pelo sistema. Nao recebe e-mail nenhum. */
const emailDoColaborador = (cpf: string, contaid: number) => `${soNumeros(cpf)}.${contaid}@${DOMINIO_COLABORADOR}`;
const emailDaLoja = (lojaid: number, contaid: number) => `loja${lojaid}.${contaid}@${DOMINIO_LOJA}`;

/** Recusa senha e PIN faceis de adivinhar. */
function conferirSegredo(valor: string, minimo: number, cpf: string | null, oQue: "senha" | "PIN") {
  const v = (valor ?? "").trim();
  if (v.length < minimo) throw new Error(`A ${oQue === "senha" ? "senha" : "o PIN"} precisa ter pelo menos ${minimo} ${oQue === "senha" ? "caracteres" : "dígitos"}.`);
  if (oQue === "PIN" && !/^\d{6}$/.test(v)) throw new Error("O PIN precisa ter 6 dígitos, só números.");
  if (cpf && v === inicialDoCpf(cpf)) throw new Error(`Não use os primeiros números do seu CPF como ${oQue === "senha" ? "senha" : "PIN"}.`);
  if (/^(\d)\1+$/.test(v)) throw new Error("Não use o mesmo número repetido.");
  const digitos = v.split("").map(Number);
  if (/^\d+$/.test(v) && digitos.every((d, i) => i === 0 || d === digitos[i - 1] + 1)) {
    throw new Error("Não use uma sequência (123456).");
  }
  if (/^\d+$/.test(v) && digitos.every((d, i) => i === 0 || d === digitos[i - 1] - 1)) {
    throw new Error("Não use uma sequência (654321).");
  }
  return v;
}

/** Sorteia a senha da loja: mostrada uma vez, nunca guardada em texto. */
function senhaSorteada() {
  const letras = "abcdefghijkmnopqrstuvwxyz23456789";
  const bytes = crypto.getRandomValues(new Uint8Array(12));
  return [...bytes].map((b) => letras[b % letras.length]).join("");
}

/** Cliente sem poder nenhum, só para tentar a senha (é ele que valida). */
async function clienteDeLogin() {
  const { createClient } = await import("@supabase/supabase-js");
  return createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

/** Mensagem única para qualquer erro de entrada: não diz se o CPF existe. */
const ERRO_LOGIN = "CPF ou senha inválidos.";

// ---------------------------------------------------------------------------
// Entrar
// ---------------------------------------------------------------------------

/** A tela de login pergunta que empresa é esta (pelo código do link ou digitado). */
export const empresaPeloCodigo = createServerFn({ method: "POST" })
  .validator((d: { codigo: string }) => d)
  .handler(async ({ data }) => {
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { data: conta, error } = await supabaseAdmin.rpc("conta_por_codigo", {
      p_codigo: (data.codigo ?? "").trim().toLowerCase(),
    });
    if (error) throw new Error("Não foi possível procurar a empresa.");
    if (!conta) throw new Error("Empresa não encontrada. Confira o código com o seu gestor.");
    return conta as { contaid: number; nome: string };
  });

/**
 * Entrada do colaborador: CPF + senha, dentro de uma empresa.
 * A trava de tentativas é nossa: 5 erros travam por alguns minutos, contados
 * pelo CPF e pela origem. A resposta é sempre a mesma, para não dizer se o CPF
 * existe.
 */
export const entrarColaborador = createServerFn({ method: "POST" })
  .validator((d: { codigo: string; cpf: string; senha: string; origem?: string }) => d)
  .handler(async ({ data }) => {
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const cpf = soNumeros(data.cpf);
    const origem = (data.origem ?? "login").slice(0, 40);

    const { data: conta } = await supabaseAdmin.rpc("conta_por_codigo", {
      p_codigo: (data.codigo ?? "").trim().toLowerCase(),
    });
    if (!conta) throw new Error(ERRO_LOGIN);
    const contaid = (conta as { contaid: number }).contaid;

    const chave = await embaralhar(`cpf:${contaid}:${cpf}`);
    const { data: travado } = await supabaseAdmin.rpc("acesso_travado", {
      p_contaid: contaid, p_tipo: "senha", p_chave: chave, p_origem: origem,
    });
    if (travado === true) {
      throw new Error("Muitas tentativas. Espere um minuto e tente de novo.");
    }

    const login = await clienteDeLogin();
    const { data: sessao, error } = await login.auth.signInWithPassword({
      email: emailDoColaborador(cpf, contaid),
      password: data.senha ?? "",
    });
    await supabaseAdmin.rpc("registrar_tentativa", {
      p_contaid: contaid, p_tipo: "senha", p_chave: chave, p_origem: origem, p_sucesso: !error,
    });
    if (error || !sessao?.session) throw new Error(ERRO_LOGIN);

    return {
      access_token: sessao.session.access_token,
      refresh_token: sessao.session.refresh_token,
    };
  });

/** Entrada do master: mesma trava de tentativas (antes não havia nenhuma). */
export const entrarMaster = createServerFn({ method: "POST" })
  .validator((d: { email: string; senha: string; origem?: string }) => d)
  .handler(async ({ data }) => {
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const email = (data.email ?? "").trim().toLowerCase();
    const origem = (data.origem ?? "login").slice(0, 40);
    const chave = await embaralhar(`email:${email}`);

    const { data: travado } = await supabaseAdmin.rpc("acesso_travado", {
      // Ainda não se sabe a conta: a trava do master conta por e-mail e origem.
      p_contaid: null as unknown as number, p_tipo: "senha", p_chave: chave, p_origem: origem,
    });
    if (travado === true) {
      throw new Error("Muitas tentativas. Espere alguns minutos e tente de novo.");
    }

    const login = await clienteDeLogin();
    const { data: sessao, error } = await login.auth.signInWithPassword({
      email, password: data.senha ?? "",
    });
    await supabaseAdmin.rpc("registrar_tentativa", {
      // Ainda não se sabe a conta: a trava do master conta por e-mail e origem.
      p_contaid: null as unknown as number, p_tipo: "senha", p_chave: chave, p_origem: origem, p_sucesso: !error,
    });
    if (error || !sessao?.session) throw new Error("E-mail ou senha inválidos.");

    return {
      access_token: sessao.session.access_token,
      refresh_token: sessao.session.refresh_token,
    };
  });

// ---------------------------------------------------------------------------
// Primeiro acesso: trocar a senha e escolher o PIN
// ---------------------------------------------------------------------------

/** Quem é o colaborador que está chamando (pelo token). */
async function colaboradorDoToken(supabase: ClienteDoUsuario) {
  const { data, error } = await supabase.rpc("meu_acesso");
  if (error) throw new Error("Não foi possível confirmar quem é você.");
  const acesso = data as { tipo?: string } | null;
  if (!acesso || acesso.tipo !== "colaborador") throw new Error("Esta ação é do aplicativo do colaborador.");
  return acesso;
}

export const trocarMinhaSenha = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((d: { senha: string }) => d)
  .handler(async ({ data, context }) => {
    const { supabase, userId } = context as unknown as { supabase: ClienteDoUsuario; userId: string };
    await colaboradorDoToken(supabase);
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");

    const { data: pessoa, error: erroPessoa } = await supabaseAdmin
      .from("contasusuarios")
      .select("contaid, funcionarioid, funcionarios(cpf)")
      .eq("userid", userId)
      .single();
    if (erroPessoa || !pessoa) throw new Error("Cadastro não encontrado.");
    const cpf = (pessoa as any).funcionarios?.cpf ?? null;

    const senha = conferirSegredo(data.senha, 6, cpf, "senha");
    const { error } = await supabaseAdmin.auth.admin.updateUserById(userId, { password: senha });
    if (error) throw new Error(`Não foi possível trocar a senha: ${error.message}`);

    await supabaseAdmin.rpc("marcar_senha_trocada", {
      p_contaid: (pessoa as any).contaid, p_funcionarioid: (pessoa as any).funcionarioid,
    });
    return { ok: true };
  });

export const definirMeuPin = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((d: { pin: string }) => d)
  .handler(async ({ data, context }) => {
    const { supabase, userId } = context as unknown as { supabase: ClienteDoUsuario; userId: string };
    await colaboradorDoToken(supabase);
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");

    const { data: pessoa, error: erroPessoa } = await supabaseAdmin
      .from("contasusuarios")
      .select("contaid, funcionarioid, funcionarios(cpf)")
      .eq("userid", userId)
      .single();
    if (erroPessoa || !pessoa) throw new Error("Cadastro não encontrado.");
    const cpf = (pessoa as any).funcionarios?.cpf ?? null;

    const pin = conferirSegredo(data.pin, 6, cpf, "PIN");
    const contaid = (pessoa as any).contaid;
    const { error } = await supabaseAdmin.rpc("definir_pin", {
      p_contaid: contaid,
      p_funcionarioid: (pessoa as any).funcionarioid,
      p_pinhash: await embaralhar(`pin:${contaid}:${pin}`),
      p_provisorio: false,
    });
    // O banco nunca diz de quem é o número repetido.
    if (error) throw new Error(error.message.includes("Escolha outro") ? "Escolha outro número." : error.message);
    return { ok: true };
  });

// ---------------------------------------------------------------------------
// O gestor: criar e redefinir acessos
// ---------------------------------------------------------------------------

export const criarAcessoColaborador = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((d: { funcionarioid: number }) => d)
  .handler(async ({ data, context }) => {
    const { supabase, userId } = context as unknown as { supabase: ClienteDoUsuario; userId: string };
    await exigirMaster(supabase);
    const contaid = await contaDoMaster(supabase);
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");

    const { data: pessoa, error: erroPessoa } = await supabaseAdmin
      .from("funcionarios")
      .select("funcionarioid, nomecompleto, cpf, ativo")
      .eq("contaid", contaid)
      .eq("funcionarioid", data.funcionarioid)
      .single();
    if (erroPessoa || !pessoa) throw new Error("Pessoa não encontrada.");
    if (!pessoa.ativo) throw new Error("Pessoa desativada não recebe acesso.");
    if (!pessoa.cpf) throw new Error("Cadastre o CPF antes de criar o acesso.");

    const inicial = inicialDoCpf(pessoa.cpf);
    const { data: criado, error } = await supabaseAdmin.auth.admin.createUser({
      email: emailDoColaborador(pessoa.cpf, contaid),
      password: inicial,
      email_confirm: true,
    });
    if (error || !criado?.user) throw new Error(`Não foi possível criar o acesso: ${error?.message ?? ""}`);

    const { data: comPin, error: erroVinculo } = await supabaseAdmin.rpc("criar_acesso_colaborador", {
      p_contaid: contaid,
      p_funcionarioid: pessoa.funcionarioid,
      p_userid: criado.user.id,
      p_pinhash: await embaralhar(`pin:${contaid}:${inicial}`),
      p_quem: userId,
    });
    if (erroVinculo) {
      await supabaseAdmin.auth.admin.deleteUser(criado.user.id);
      throw new Error(`Não foi possível criar o acesso: ${erroVinculo.message}`);
    }
    return { nome: pessoa.nomecompleto, inicial, pinPendente: comPin === false };
  });

export const redefinirAcessoColaborador = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((d: { funcionarioid: number }) => d)
  .handler(async ({ data, context }) => {
    const { supabase, userId } = context as unknown as { supabase: ClienteDoUsuario; userId: string };
    await exigirMaster(supabase);
    const contaid = await contaDoMaster(supabase);
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");

    const { data: pessoa } = await supabaseAdmin
      .from("funcionarios")
      .select("funcionarioid, nomecompleto, cpf")
      .eq("contaid", contaid)
      .eq("funcionarioid", data.funcionarioid)
      .single();
    if (!pessoa?.cpf) throw new Error("Pessoa sem CPF cadastrado.");

    const { data: acesso } = await supabaseAdmin
      .from("contasusuarios")
      .select("userid")
      .eq("contaid", contaid)
      .eq("funcionarioid", pessoa.funcionarioid)
      .single();
    if (!acesso) throw new Error("Esta pessoa ainda não tem acesso.");

    const inicial = inicialDoCpf(pessoa.cpf);
    const { error } = await supabaseAdmin.auth.admin.updateUserById(acesso.userid, { password: inicial });
    if (error) throw new Error(`Não foi possível redefinir: ${error.message}`);
    // Derruba as sessões abertas: quem estava dentro é desconectado.
    await supabaseAdmin.auth.admin.signOut(acesso.userid, "global").catch(() => undefined);

    const { data: comPin, error: erroBanco } = await supabaseAdmin.rpc("redefinir_acesso", {
      p_contaid: contaid,
      p_funcionarioid: pessoa.funcionarioid,
      p_pinhash: await embaralhar(`pin:${contaid}:${inicial}`),
      p_quem: userId,
    });
    if (erroBanco) throw new Error(erroBanco.message);
    return { nome: pessoa.nomecompleto, inicial, pinPendente: comPin === false };
  });

export const criarAcessoLoja = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((d: { lojaid: number }) => d)
  .handler(async ({ data, context }) => {
    const { supabase, userId } = context as unknown as { supabase: ClienteDoUsuario; userId: string };
    await exigirMaster(supabase);
    const contaid = await contaDoMaster(supabase);
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");

    const senha = senhaSorteada();
    const { data: criado, error } = await supabaseAdmin.auth.admin.createUser({
      email: emailDaLoja(data.lojaid, contaid),
      password: senha,
      email_confirm: true,
    });
    if (error || !criado?.user) throw new Error(`Não foi possível criar o acesso: ${error?.message ?? ""}`);

    const { error: erroVinculo } = await supabaseAdmin.rpc("criar_acesso_loja", {
      p_contaid: contaid, p_lojaid: data.lojaid, p_userid: criado.user.id, p_quem: userId,
    });
    if (erroVinculo) {
      await supabaseAdmin.auth.admin.deleteUser(criado.user.id);
      throw new Error(`Não foi possível criar o acesso: ${erroVinculo.message}`);
    }
    // A senha aparece UMA vez, como o link da TV.
    return { usuario: emailDaLoja(data.lojaid, contaid), senha };
  });

export const redefinirSenhaLoja = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((d: { lojaid: number }) => d)
  .handler(async ({ data, context }) => {
    const { supabase } = context as unknown as { supabase: ClienteDoUsuario };
    await exigirMaster(supabase);
    const contaid = await contaDoMaster(supabase);
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");

    const { data: acesso } = await supabaseAdmin
      .from("contasusuarios")
      .select("userid")
      .eq("contaid", contaid)
      .eq("lojaid", data.lojaid)
      .single();
    if (!acesso) throw new Error("Esta loja ainda não tem acesso.");

    const senha = senhaSorteada();
    const { error } = await supabaseAdmin.auth.admin.updateUserById(acesso.userid, { password: senha });
    if (error) throw new Error(`Não foi possível redefinir: ${error.message}`);
    // Derruba os tablets que estavam abertos com a senha antiga.
    await supabaseAdmin.auth.admin.signOut(acesso.userid, "global").catch(() => undefined);
    return { usuario: emailDaLoja(data.lojaid, contaid), senha };
  });

/** Ciência da política no primeiro acesso: usa a mesma função de ciência das telas do gestor. */
export const aceitarPolitica = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((d: { assinaturaid: number }) => d)
  .handler(async ({ data, context }) => {
    const { supabase, userId } = context as unknown as { supabase: ClienteDoUsuario; userId: string };
    await colaboradorDoToken(supabase);
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");

    const { data: pessoa, error: erroPessoa } = await supabaseAdmin
      .from("contasusuarios")
      .select("contaid, funcionarioid")
      .eq("userid", userId)
      .single();
    if (erroPessoa || !pessoa?.funcionarioid) throw new Error("Cadastro não encontrado.");

    const { error } = await supabaseAdmin.rpc("politica_dar_ciencia", {
      p_contaid: pessoa.contaid,
      p_funcionarioid: pessoa.funcionarioid,
      p_assinaturaid: data.assinaturaid,
    });
    if (error) throw new Error(error.message);
    return { ok: true };
  });
