// Funcoes de servidor da Etapa 1.12, parte A: os acessos de LOJA e de
// COLABORADOR. Reescrito em 23/09/2026 depois da revisao adversarial.
//
// Regras desta pasta (iguais as de contas.ts):
// - A chave service_role NUNCA aparece aqui: e lida dentro de client.server.ts,
//   por import dinamico dentro do handler.
// - Quem confere permissao e o SERVIDOR, com o token de quem chamou.
//
// O desenho do acesso do colaborador, depois da revisao:
// - A SENHA e conferida por nos: guardamos so o resumo dela (PBKDF2 com sal por
//   pessoa) em funcionarios.senhahashapp. A senha que o Supabase guarda e um
//   valor derivado de uma chave que so o servidor tem (STGAME_PIN_PEPPER) e do
//   identificador interno do login: ninguem digita nem adivinha.
//   Resultado: falar direto com o Supabase nao serve de nada, e TODA tentativa
//   passa pela nossa trava.
// - Nao existe senha padrao. Quem ainda nao criou senha entra uma vez com um
//   CODIGO sorteado pelo gestor (uso unico, validade curta).
// - O PIN tambem e escolhido pela pessoa, e cada tentativa passa pela trava.
import { createServerFn } from "@tanstack/react-start";
import { getRequest } from "@tanstack/react-start/server";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import { SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY } from "@/integrations/supabase/config-publica";

const DOMINIO_COLABORADOR = "colaborador.stgame.local";
const DOMINIO_LOJA = "loja.stgame.local";
const DIAS_DO_CODIGO = 7;
const ITERACOES_SENHA = 210_000;

type ClienteDoUsuario = {
  rpc: (nome: string, args?: Record<string, unknown>) => Promise<{ data: unknown; error: unknown }>;
};

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

// ---------------------------------------------------------------------------
// Segredos: tudo com a chave do servidor
// ---------------------------------------------------------------------------

function chaveDoServidor() {
  const chave = process.env["STGAME_PIN_PEPPER"];
  if (!chave || chave.length < 16) {
    throw new Error("Falta a chave STGAME_PIN_PEPPER no servidor (Secrets do Lovable).");
  }
  return chave;
}

const hex = (b: ArrayBuffer) => [...new Uint8Array(b)].map((x) => x.toString(16).padStart(2, "0")).join("");
const deHex = (s: string) => Uint8Array.from((s.match(/../g) ?? []).map((h) => parseInt(h, 16)));

/**
 * Embaralha com a chave do servidor (HMAC-SHA256). O resultado e sempre o mesmo
 * para a mesma entrada, e so por isso o banco acha a pessoa pelo PIN direto no
 * indice — sem comparar uma a uma, que ficaria lento com 20+ pessoas.
 */
async function embaralhar(valor: string) {
  const material = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(chaveDoServidor()),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return hex(await crypto.subtle.sign("HMAC", material, new TextEncoder().encode(valor)));
}

/**
 * A senha que o Supabase guarda. Ninguem digita nem conhece: e derivada da
 * chave do servidor e do identificador interno do login. Trocar essa chave
 * significa refazer os acessos (esta anotado no plano).
 */
const senhaInterna = (userid: string) => embaralhar(`auth:${userid}`);

/** Resumo da senha do app: PBKDF2-SHA256 com sal por pessoa. */
async function resumoDaSenha(senha: string) {
  const sal = crypto.getRandomValues(new Uint8Array(16));
  const material = await crypto.subtle.importKey("raw", new TextEncoder().encode(senha), "PBKDF2", false, ["deriveBits"]);
  const bits = await crypto.subtle.deriveBits(
    { name: "PBKDF2", salt: sal, iterations: ITERACOES_SENHA, hash: "SHA-256" },
    material,
    256,
  );
  return `pbkdf2$${ITERACOES_SENHA}$${hex(sal.buffer as ArrayBuffer)}$${hex(bits)}`;
}

/** Confere a senha comparando sempre tudo (para o tempo nao dar pista). */
async function senhaConfere(senha: string, guardado: string | null) {
  if (!guardado) return false;
  const [tipo, iteracoes, sal, esperado] = guardado.split("$");
  if (tipo !== "pbkdf2" || !sal || !esperado) return false;
  const material = await crypto.subtle.importKey("raw", new TextEncoder().encode(senha), "PBKDF2", false, ["deriveBits"]);
  const bits = await crypto.subtle.deriveBits(
    { name: "PBKDF2", salt: deHex(sal), iterations: Number(iteracoes), hash: "SHA-256" },
    material,
    256,
  );
  const calculado = hex(bits);
  if (calculado.length !== esperado.length) return false;
  let diferenca = 0;
  for (let i = 0; i < calculado.length; i++) diferenca |= calculado.charCodeAt(i) ^ esperado.charCodeAt(i);
  return diferenca === 0;
}

const soNumeros = (v: string) => (v ?? "").replace(/\D/g, "");

/** E-mail interno, montado pelo sistema. Nao recebe e-mail nenhum. */
const emailDoColaborador = (cpf: string, contaid: number) => `${soNumeros(cpf)}.${contaid}@${DOMINIO_COLABORADOR}`;
const emailDaLoja = (lojaid: number, contaid: number) => `loja${lojaid}.${contaid}@${DOMINIO_LOJA}`;

/**
 * De onde veio a tentativa. Definido pelo SERVIDOR (o navegador nao escolhe),
 * senao bastaria mandar um valor novo a cada tentativa para zerar a trava.
 */
function origemDaChamada() {
  try {
    const req = getRequest();
    const ip =
      req?.headers.get("cf-connecting-ip") ??
      req?.headers.get("x-real-ip") ??
      (req?.headers.get("x-forwarded-for") ?? "").split(",")[0].trim();
    return (ip || "desconhecida").slice(0, 40);
  } catch {
    return "desconhecida";
  }
}

/** Codigo de primeiro acesso: 8 caracteres, sem letras que se confundem. */
function codigoSorteado() {
  const letras = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const bytes = crypto.getRandomValues(new Uint8Array(8));
  const c = [...bytes].map((b) => letras[b % letras.length]).join("");
  return `${c.slice(0, 4)}-${c.slice(4)}`;
}

/** Senha do tablet: sorteada, mostrada uma vez. */
function senhaSorteada() {
  const letras = "abcdefghijkmnopqrstuvwxyz23456789";
  const bytes = crypto.getRandomValues(new Uint8Array(12));
  return [...bytes].map((b) => letras[b % letras.length]).join("");
}

/** Recusa senha e PIN faceis de adivinhar. */
function conferirSegredo(valor: string, minimo: number, cpf: string | null, oQue: "senha" | "PIN") {
  const v = (valor ?? "").trim();
  const nome = oQue === "senha" ? "A senha" : "O PIN";
  if (v.length < minimo) {
    throw new Error(`${nome} precisa ter pelo menos ${minimo} ${oQue === "senha" ? "caracteres" : "dígitos"}.`);
  }
  if (oQue === "PIN" && !/^\d{6}$/.test(v)) throw new Error("O PIN precisa ter 6 dígitos, só números.");
  if (cpf && /^\d+$/.test(v) && soNumeros(cpf).includes(v)) {
    throw new Error(`${nome} não pode ser uma parte do seu CPF.`);
  }
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

/** Cliente sem poder nenhum, so para abrir a sessao com a senha interna. */
async function clienteDeLogin() {
  const { createClient } = await import("@supabase/supabase-js");
  return createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

/** Abre a sessao do colaborador depois de NOS conferirmos quem e. */
async function abrirSessao(userid: string, email: string) {
  const login = await clienteDeLogin();
  const { data, error } = await login.auth.signInWithPassword({ email, password: await senhaInterna(userid) });
  if (error || !data?.session) {
    throw new Error("Não foi possível abrir a sessão. Peça ao gestor para redefinir o seu acesso.");
  }
  return { access_token: data.session.access_token, refresh_token: data.session.refresh_token };
}

/** Mensagens únicas: nunca dizem se o CPF existe. */
const ERRO_LOGIN = "CPF ou senha inválidos.";
const ERRO_CODIGO = "CPF ou código inválidos.";
const ERRO_TRAVADO = "Muitas tentativas. Espere um pouco e tente de novo.";

// ---------------------------------------------------------------------------
// Entrar
// ---------------------------------------------------------------------------

/** Entrada do colaborador: CPF + senha, dentro de uma empresa. */
export const entrarColaborador = createServerFn({ method: "POST" })
  .validator((d: { codigo: string; cpf: string; senha: string }) => d)
  .handler(async ({ data }) => {
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const cpf = soNumeros(data.cpf);
    const origem = origemDaChamada();

    const { data: contaid } = await supabaseAdmin.rpc("conta_do_codigo", {
      p_codigo: (data.codigo ?? "").trim().toLowerCase(),
    });
    if (typeof contaid !== "number") throw new Error(ERRO_LOGIN);

    const chave = await embaralhar(`cpf:${contaid}:${cpf}`);
    const { data: travado } = await supabaseAdmin.rpc("acesso_travado", {
      p_contaid: contaid, p_tipo: "senha", p_chave: chave, p_origem: origem,
    });
    if (travado === true) throw new Error(ERRO_TRAVADO);

    const { data: pessoa } = await supabaseAdmin.rpc("senha_app_de", { p_contaid: contaid, p_cpf: cpf });
    const dados = pessoa as { funcionarioid: number; userid: string; senhahash: string | null } | null;
    const ok = await senhaConfere(data.senha ?? "", dados?.senhahash ?? null);

    await supabaseAdmin.rpc("registrar_tentativa", {
      p_contaid: contaid, p_tipo: "senha", p_chave: chave, p_origem: origem, p_sucesso: ok,
    });
    if (!ok || !dados) throw new Error(ERRO_LOGIN);

    return abrirSessao(dados.userid, emailDoColaborador(cpf, contaid));
  });

/** Primeiro acesso: CPF + código do gestor. Uso único. */
export const entrarComCodigo = createServerFn({ method: "POST" })
  .validator((d: { codigo: string; cpf: string; codigoacesso: string }) => d)
  .handler(async ({ data }) => {
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const cpf = soNumeros(data.cpf);
    const origem = origemDaChamada();

    const { data: contaid } = await supabaseAdmin.rpc("conta_do_codigo", {
      p_codigo: (data.codigo ?? "").trim().toLowerCase(),
    });
    if (typeof contaid !== "number") throw new Error(ERRO_CODIGO);

    const chave = await embaralhar(`cpf:${contaid}:${cpf}`);
    const { data: travado } = await supabaseAdmin.rpc("acesso_travado", {
      p_contaid: contaid, p_tipo: "senha", p_chave: chave, p_origem: origem,
    });
    if (travado === true) throw new Error(ERRO_TRAVADO);

    const codigoLimpo = (data.codigoacesso ?? "").trim().toUpperCase().replace(/\s/g, "");
    const { data: usado } = await supabaseAdmin.rpc("usar_codigo_acesso", {
      p_contaid: contaid,
      p_cpf: cpf,
      p_codigohash: await embaralhar(`codigo:${contaid}:${codigoLimpo}`),
    });
    await supabaseAdmin.rpc("registrar_tentativa", {
      p_contaid: contaid, p_tipo: "senha", p_chave: chave, p_origem: origem, p_sucesso: !!usado,
    });
    if (!usado) throw new Error(ERRO_CODIGO);

    const { data: pessoa } = await supabaseAdmin.rpc("senha_app_de", { p_contaid: contaid, p_cpf: cpf });
    const dados = pessoa as { userid: string } | null;
    if (!dados) throw new Error(ERRO_CODIGO);
    return abrirSessao(dados.userid, emailDoColaborador(cpf, contaid));
  });

/** Entrada do master: e-mail e senha do Supabase, com a nossa trava por cima. */
export const entrarMaster = createServerFn({ method: "POST" })
  .validator((d: { email: string; senha: string }) => d)
  .handler(async ({ data }) => {
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const email = (data.email ?? "").trim().toLowerCase();
    const origem = origemDaChamada();
    const chave = await embaralhar(`email:${email}`);

    const { data: travado } = await supabaseAdmin.rpc("acesso_travado", {
      p_contaid: null as unknown as number, p_tipo: "senha", p_chave: chave, p_origem: origem,
    });
    if (travado === true) throw new Error(ERRO_TRAVADO);

    const login = await clienteDeLogin();
    const { data: sessao, error } = await login.auth.signInWithPassword({ email, password: data.senha ?? "" });
    await supabaseAdmin.rpc("registrar_tentativa", {
      p_contaid: null as unknown as number, p_tipo: "senha", p_chave: chave, p_origem: origem, p_sucesso: !error,
    });
    if (error || !sessao?.session) throw new Error("E-mail ou senha inválidos.");

    return { access_token: sessao.session.access_token, refresh_token: sessao.session.refresh_token };
  });

// ---------------------------------------------------------------------------
// Primeiro acesso: criar a senha, escolher o PIN, aceitar a política
// ---------------------------------------------------------------------------

/** Quem é o colaborador que está chamando (pelo token). */
async function colaboradorDoToken(supabase: ClienteDoUsuario) {
  const { data, error } = await supabase.rpc("meu_acesso");
  if (error) throw new Error("Não foi possível confirmar quem é você.");
  const acesso = data as { tipo?: string } | null;
  if (!acesso || acesso.tipo !== "colaborador") throw new Error("Esta ação é do aplicativo do colaborador.");
  return acesso;
}

type PessoaDoToken = { contaid: number; funcionarioid: number; cpf: string | null };

/** Cadastro de quem está chamando, pelo token (nunca pelo que o navegador diz). */
async function pessoaDoToken(userId: string): Promise<PessoaDoToken> {
  const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
  const { data, error } = await supabaseAdmin
    .from("contasusuarios")
    .select("contaid, funcionarioid, funcionarios(cpf)")
    .eq("userid", userId)
    .single();
  if (error || !data?.funcionarioid) throw new Error("Cadastro não encontrado.");
  return {
    contaid: data.contaid,
    funcionarioid: data.funcionarioid,
    cpf: (data as { funcionarios?: { cpf: string | null } }).funcionarios?.cpf ?? null,
  };
}

export const trocarMinhaSenha = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((d: { senha: string }) => d)
  .handler(async ({ data, context }) => {
    const { supabase, userId } = context as unknown as { supabase: ClienteDoUsuario; userId: string };
    await colaboradorDoToken(supabase);
    const pessoa = await pessoaDoToken(userId);
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");

    const senha = conferirSegredo(data.senha, 8, pessoa.cpf, "senha");
    const { error } = await supabaseAdmin.rpc("definir_senha_app", {
      p_contaid: pessoa.contaid,
      p_funcionarioid: pessoa.funcionarioid,
      p_hash: await resumoDaSenha(senha),
    });
    if (error) throw new Error(`Não foi possível salvar a senha: ${error.message}`);
    return { ok: true };
  });

export const definirMeuPin = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((d: { pin: string }) => d)
  .handler(async ({ data, context }) => {
    const { supabase, userId } = context as unknown as { supabase: ClienteDoUsuario; userId: string };
    await colaboradorDoToken(supabase);
    const pessoa = await pessoaDoToken(userId);
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");

    // Escolher PIN passa pela trava: sem isto, a resposta "escolha outro
    // número" vira um adivinhador do PIN dos colegas.
    const chave = await embaralhar(`pessoa:${pessoa.contaid}:${pessoa.funcionarioid}`);
    const origem = origemDaChamada();
    const { data: travado } = await supabaseAdmin.rpc("acesso_travado", {
      p_contaid: pessoa.contaid, p_tipo: "pin", p_chave: chave, p_origem: origem,
    });
    if (travado === true) throw new Error("Muitas tentativas de PIN. Espere um pouco e tente de novo.");

    const pin = conferirSegredo(data.pin, 6, pessoa.cpf, "PIN");
    const { error } = await supabaseAdmin.rpc("definir_pin", {
      p_contaid: pessoa.contaid,
      p_funcionarioid: pessoa.funcionarioid,
      p_pinhash: await embaralhar(`pin:${pessoa.contaid}:${pin}`),
      p_provisorio: false,
    });
    await supabaseAdmin.rpc("registrar_tentativa", {
      p_contaid: pessoa.contaid, p_tipo: "pin", p_chave: chave, p_origem: origem, p_sucesso: !error,
    });
    if (error) throw new Error(error.message.includes("Escolha outro") ? "Escolha outro número." : error.message);
    return { ok: true };
  });

/** Ciência da política no primeiro acesso: usa a mesma função das telas do gestor. */
export const aceitarPolitica = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((d: { assinaturaid: number }) => d)
  .handler(async ({ data, context }) => {
    const { supabase, userId } = context as unknown as { supabase: ClienteDoUsuario; userId: string };
    await colaboradorDoToken(supabase);
    const pessoa = await pessoaDoToken(userId);
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");

    const { error } = await supabaseAdmin.rpc("politica_dar_ciencia", {
      p_contaid: pessoa.contaid,
      p_funcionarioid: pessoa.funcionarioid,
      p_assinaturaid: data.assinaturaid,
    });
    if (error) throw new Error(error.message);
    return { ok: true };
  });

// ---------------------------------------------------------------------------
// O gestor: criar acesso, gerar código, redefinir, trocar CPF, desativar
// ---------------------------------------------------------------------------

/** Gera o código de primeiro acesso e devolve o texto UMA vez. */
async function gerarCodigo(contaid: number, funcionarioid: number, quem: string) {
  const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
  const codigo = codigoSorteado();
  const { error } = await supabaseAdmin.rpc("criar_codigo_acesso", {
    p_contaid: contaid,
    p_funcionarioid: funcionarioid,
    p_codigohash: await embaralhar(`codigo:${contaid}:${codigo}`),
    p_dias: DIAS_DO_CODIGO,
    p_quem: quem,
  });
  if (error) throw new Error(error.message);
  return codigo;
}

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

    // Senha aleatória descartável: logo abaixo ela vira a senha interna, que
    // ninguém conhece. Nunca existe uma "senha padrão".
    const { data: criado, error } = await supabaseAdmin.auth.admin.createUser({
      email: emailDoColaborador(pessoa.cpf, contaid),
      password: senhaSorteada() + senhaSorteada(),
      email_confirm: true,
    });
    if (error || !criado?.user) throw new Error(`Não foi possível criar o acesso: ${error?.message ?? ""}`);

    try {
      await supabaseAdmin.auth.admin.updateUserById(criado.user.id, { password: await senhaInterna(criado.user.id) });
      const { error: erroVinculo } = await supabaseAdmin.rpc("criar_acesso_colaborador", {
        p_contaid: contaid,
        p_funcionarioid: pessoa.funcionarioid,
        p_userid: criado.user.id,
        p_pinhash: null as unknown as string,
        p_quem: userId,
      });
      if (erroVinculo) throw new Error(erroVinculo.message);
      const codigo = await gerarCodigo(contaid, pessoa.funcionarioid, userId);
      return { nome: pessoa.nomecompleto, codigo, dias: DIAS_DO_CODIGO };
    } catch (e) {
      await supabaseAdmin.auth.admin.deleteUser(criado.user.id).catch(() => undefined);
      throw new Error(`Não foi possível criar o acesso: ${(e as Error).message}`);
    }
  });

/** Gera um código novo (o anterior é cancelado). */
export const gerarCodigoDeAcesso = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((d: { funcionarioid: number }) => d)
  .handler(async ({ data, context }) => {
    const { supabase, userId } = context as unknown as { supabase: ClienteDoUsuario; userId: string };
    await exigirMaster(supabase);
    const contaid = await contaDoMaster(supabase);
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");

    const { data: pessoa } = await supabaseAdmin
      .from("funcionarios")
      .select("funcionarioid, nomecompleto")
      .eq("contaid", contaid)
      .eq("funcionarioid", data.funcionarioid)
      .single();
    if (!pessoa) throw new Error("Pessoa não encontrada.");

    const codigo = await gerarCodigo(contaid, pessoa.funcionarioid, userId);
    return { nome: pessoa.nomecompleto, codigo, dias: DIAS_DO_CODIGO };
  });

/** "Redefinir acesso": apaga senha e PIN, derruba as sessões e gera código novo. */
export const redefinirAcessoColaborador = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((d: { funcionarioid: number }) => d)
  .handler(async ({ data, context }) => {
    const { supabase, userId } = context as unknown as { supabase: ClienteDoUsuario; userId: string };
    await exigirMaster(supabase);
    const contaid = await contaDoMaster(supabase);
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");

    const { data: acesso } = await supabaseAdmin
      .from("contasusuarios")
      .select("userid, funcionarios(nomecompleto)")
      .eq("contaid", contaid)
      .eq("funcionarioid", data.funcionarioid)
      .single();
    if (!acesso) throw new Error("Esta pessoa ainda não tem acesso.");

    // Primeiro o banco (que confere se a pessoa está ativa), depois o Supabase.
    const { error: erroBanco } = await supabaseAdmin.rpc("redefinir_acesso", {
      p_contaid: contaid,
      p_funcionarioid: data.funcionarioid,
      p_pinhash: null as unknown as string,
      p_quem: userId,
    });
    if (erroBanco) throw new Error(erroBanco.message);

    await supabaseAdmin.auth.admin.signOut(acesso.userid, "global").catch(() => undefined);
    const codigo = await gerarCodigo(contaid, data.funcionarioid, userId);
    const nome = (acesso as { funcionarios?: { nomecompleto: string } }).funcionarios?.nomecompleto ?? "";
    return { nome, codigo, dias: DIAS_DO_CODIGO };
  });

/** Trocar o CPF de quem já entra pelo app: muda o cadastro e o login junto. */
export const trocarCpfDoColaborador = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((d: { funcionarioid: number; cpf: string }) => d)
  .handler(async ({ data, context }) => {
    const { supabase } = context as unknown as { supabase: ClienteDoUsuario };
    await exigirMaster(supabase);
    const contaid = await contaDoMaster(supabase);
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");

    const cpf = soNumeros(data.cpf);
    const { data: acesso } = await supabaseAdmin
      .from("contasusuarios")
      .select("userid")
      .eq("contaid", contaid)
      .eq("funcionarioid", data.funcionarioid)
      .single();

    const { error } = await supabaseAdmin.rpc("trocar_cpf", {
      p_contaid: contaid, p_funcionarioid: data.funcionarioid, p_cpf: cpf,
    });
    if (error) throw new Error(error.message);

    if (acesso) {
      const { error: erroEmail } = await supabaseAdmin.auth.admin.updateUserById(acesso.userid, {
        email: emailDoColaborador(cpf, contaid),
        email_confirm: true,
      });
      if (erroEmail) throw new Error(`CPF trocado, mas o login não acompanhou: ${erroEmail.message}`);
    }
    return { ok: true };
  });

/** Desativar ou reativar: o banco apaga senha e PIN; aqui o login é derrubado. */
export const desativarColaborador = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((d: { funcionarioid: number; ativo: boolean }) => d)
  .handler(async ({ data, context }) => {
    const { supabase } = context as unknown as { supabase: ClienteDoUsuario };
    await exigirMaster(supabase);
    const contaid = await contaDoMaster(supabase);
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");

    const { error } = await supabaseAdmin
      .from("funcionarios")
      .update({ ativo: data.ativo })
      .eq("contaid", contaid)
      .eq("funcionarioid", data.funcionarioid);
    if (error) throw new Error(error.message);

    if (!data.ativo) {
      const { data: acesso } = await supabaseAdmin
        .from("contasusuarios")
        .select("userid")
        .eq("contaid", contaid)
        .eq("funcionarioid", data.funcionarioid)
        .single();
      if (acesso) await supabaseAdmin.auth.admin.signOut(acesso.userid, "global").catch(() => undefined);
    }
    return { ok: true };
  });

// ---------------------------------------------------------------------------
// Acesso do tablet da loja
// ---------------------------------------------------------------------------

export const criarAcessoLoja = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((d: { lojaid: number }) => d)
  .handler(async ({ data, context }) => {
    const { supabase, userId } = context as unknown as { supabase: ClienteDoUsuario; userId: string };
    await exigirMaster(supabase);
    const contaid = await contaDoMaster(supabase);
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");

    // Confere a loja ANTES de criar login nenhum.
    const { data: loja } = await supabaseAdmin
      .from("lojas")
      .select("lojaid, ativa")
      .eq("contaid", contaid)
      .eq("lojaid", data.lojaid)
      .single();
    if (!loja?.ativa) throw new Error("Loja não encontrada ou desativada.");

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
      await supabaseAdmin.auth.admin.deleteUser(criado.user.id).catch(() => undefined);
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
