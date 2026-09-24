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
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import { SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY } from "@/integrations/supabase/config-publica";
import {
  ERRO_TRAVADO, abrirTentativa, deHex, embaralhar, fecharTentativa,
  hex, origemDaChamada, resumoDoPin,
} from "@/servidor/segredos";

// Domínio interno dos logins que o sistema monta sozinho. É um subdomínio de
// um domínio REAL de propósito: validador de e-mail recusa TLD inventado (o
// antigo .local). Ninguém recebe e-mail aqui — estas caixas não existem.
const DOMINIO_COLABORADOR = "colaborador.stgame.com.br";
const DOMINIO_LOJA = "loja.stgame.com.br";
const DIAS_DO_CODIGO = 7;
// A hospedagem (Cloudflare) recusa PBKDF2 acima de 100.000 voltas — e recusa
// no ar, não aqui. Este número é o teto de lá; a verificação do GitHub barra
// qualquer valor maior.
const ITERACOES_SENHA = 100_000;

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

/**
 * Confere a senha. Quando não existe senha guardada, confere contra um resumo
 * de mentira: sem isso, a resposta voltava na hora e o tempo dizia se aquele
 * CPF existe (dava para descobrir quem trabalha na empresa).
 */
const RESUMO_DE_MENTIRA = `pbkdf2$${ITERACOES_SENHA}$${"00".repeat(16)}$${"00".repeat(32)}`;

async function senhaConfere(senha: string, guardado: string | null) {
  const usar = guardado && guardado.startsWith("pbkdf2$") ? guardado : RESUMO_DE_MENTIRA;
  const [tipo, iteracoes, sal, esperado] = usar.split("$");
  if (tipo !== "pbkdf2" || !sal || !esperado) return false;
  const material = await crypto.subtle.importKey("raw", new TextEncoder().encode(senha), "PBKDF2", false, ["deriveBits"]);
  const bits = await crypto.subtle.deriveBits(
    { name: "PBKDF2", salt: deHex(sal), iterations: Number(iteracoes), hash: "SHA-256" },
    material,
    256,
  );
  const calculado = hex(bits);
  let diferenca = calculado.length === esperado.length ? 0 : 1;
  for (let i = 0; i < Math.min(calculado.length, esperado.length); i++) {
    diferenca |= calculado.charCodeAt(i) ^ esperado.charCodeAt(i);
  }
  // Sem senha guardada nunca vale, mesmo que o resumo de mentira batesse.
  return diferenca === 0 && !!guardado;
}

const soNumeros = (v: string) => (v ?? "").replace(/\D/g, "");

/** E-mail interno, montado pelo sistema. Nao recebe e-mail nenhum. */
const emailDoColaborador = (cpf: string, contaid: number) => `${soNumeros(cpf)}.${contaid}@${DOMINIO_COLABORADOR}`;
const emailDaLoja = (lojaid: number, contaid: number) => `loja${lojaid}.${contaid}@${DOMINIO_LOJA}`;

/** Codigo de primeiro acesso: 8 caracteres, sem letras que se confundem. */
function codigoSorteado() {
  const letras = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const bytes = crypto.getRandomValues(new Uint8Array(8));
  const c = [...bytes].map((b) => letras[b % letras.length]).join("");
  return `${c.slice(0, 4)}-${c.slice(4)}`;
}

/** Senha do tablet: sorteada, mostrada uma vez. 32 letras: sem viés no sorteio. */
function senhaSorteada() {
  const letras = "abcdefghijkmnpqrstuvwxyz23456789";
  const bytes = crypto.getRandomValues(new Uint8Array(14));
  return [...bytes].map((b) => letras[b % 32]).join("");
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
  if (/^(.)\1+$/.test(v)) throw new Error("Não repita o mesmo caractere.");
  if (oQue === "senha") {
    const comuns = ["12345678", "senha123", "password", "123456789", "qwertyui", "abcd1234", "stgame123"];
    if (comuns.includes(v.toLowerCase())) throw new Error("Essa senha é fácil demais. Escolha outra.");
    if (/^\d+$/.test(v)) throw new Error("A senha precisa ter pelo menos uma letra.");
  }
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

/**
 * Abre a sessao depois de NOS conferirmos quem e.
 *
 * O e-mail vem do proprio login (pelo identificador), nao remontado a partir do
 * CPF: assim, trocar o dominio interno ou o CPF nunca deixa ninguem de fora.
 */
async function abrirSessao(userid: string) {
  const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
  const { data: dono } = await supabaseAdmin.auth.admin.getUserById(userid);
  const email = dono?.user?.email;
  if (!email) throw new Error("Não foi possível abrir a sessão. Peça ao gestor para redefinir o seu acesso.");

  const login = await clienteDeLogin();
  const { data, error } = await login.auth.signInWithPassword({ email, password: await senhaInterna(userid) });
  if (error || !data?.session) {
    throw new Error("Não foi possível abrir a sessão. Peça ao gestor para redefinir o seu acesso.");
  }
  return { access_token: data.session.access_token, refresh_token: data.session.refresh_token };
}

/**
 * Abre uma tentativa: o banco tranca a chave, confere os limites e já registra.
 * Conferir e registrar em duas idas separadas deixava uma rajada simultânea
 * passar inteira por cima do teto — era assim que o adivinhador voltava.
 */
/** Mensagens únicas: nunca dizem se o CPF existe. */
const ERRO_LOGIN = "CPF ou senha inválidos.";
const ERRO_CODIGO = "CPF ou código inválidos.";
const ERRO_LOGIN_EMAIL = "E-mail ou senha inválidos.";

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
    const tentativa = await abrirTentativa(contaid, "senha", chave, origem);

    const { data: pessoa } = await supabaseAdmin.rpc("senha_app_de", { p_contaid: contaid, p_cpf: cpf });
    const dados = pessoa as { funcionarioid: number; userid: string; senhahash: string | null } | null;
    const ok = await senhaConfere(data.senha ?? "", dados?.senhahash ?? null);

    await fecharTentativa(tentativa, ok);
    if (!ok || !dados) throw new Error(ERRO_LOGIN);

    return abrirSessao(dados.userid);
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
    const tentativa = await abrirTentativa(contaid, "senha", chave, origem);

    const codigoLimpo = (data.codigoacesso ?? "").trim().toUpperCase().replace(/\s/g, "");
    const { data: usado } = await supabaseAdmin.rpc("usar_codigo_acesso", {
      p_contaid: contaid,
      p_cpf: cpf,
      p_codigohash: await embaralhar(`codigo:${contaid}:${codigoLimpo}`),
    });
    await fecharTentativa(tentativa, !!usado);
    if (!usado) throw new Error(ERRO_CODIGO);

    const { data: pessoa } = await supabaseAdmin.rpc("senha_app_de", { p_contaid: contaid, p_cpf: cpf });
    const dados = pessoa as { userid: string } | null;
    if (!dados) throw new Error(ERRO_CODIGO);
    return abrirSessao(dados.userid);
  });

/**
 * Entrada por e-mail: serve para o gestor (master), para o administrador geral
 * e para o tablet da loja.
 *
 * A senha também é conferida por NÓS, como a do colaborador. Quem ainda não tem
 * resumo guardado (todo mundo, no dia em que isto entra no ar) entra uma última
 * vez pela senha antiga do Supabase — e nesse momento a senha é convertida: o
 * resumo passa a ser nosso e a senha do Supabase vira o valor interno. Depois
 * disso, falar direto com o Supabase não serve mais.
 */
export const entrarMaster = createServerFn({ method: "POST" })
  .validator((d: { email: string; senha: string }) => d)
  .handler(async ({ data }) => {
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const email = (data.email ?? "").trim().toLowerCase();
    const senha = data.senha ?? "";
    const origem = origemDaChamada();
    const chave = await embaralhar(`email:${email}`);

    const { data: achado } = await supabaseAdmin.rpc("acesso_por_email", { p_email: email });
    const acesso = achado as
      | { userid: string; senhahash: string | null; contaid: number | null; papel: string | null }
      | null;

    // O tablet tem trava própria: só por origem. A senha dele é sorteada pelo
    // servidor (impossível de adivinhar), e travar por e-mail deixaria a loja
    // sem sistema no balcão por 15 minutos — o prejuízo iria para a vítima,
    // não para quem ataca.
    const tipo = acesso?.papel === "loja" ? "tablet" : "senha";
    const tentativa = await abrirTentativa(null, tipo, chave, origem);

    // Caminho normal: o resumo é nosso.
    if (acesso?.senhahash) {
      const ok = await senhaConfere(senha, acesso.senhahash);
      await fecharTentativa(tentativa, ok);
      if (!ok) throw new Error(ERRO_LOGIN_EMAIL);
      return abrirSessao(acesso.userid);
    }

    // Conversão (uma vez por login antigo): confere no Supabase e passa a
    // guardar o resumo aqui, trocando a senha de lá pela interna.
    const login = await clienteDeLogin();
    const { data: sessao, error } = await login.auth.signInWithPassword({ email, password: senha });
    await fecharTentativa(tentativa, !error);
    if (error || !sessao?.session || !acesso) throw new Error(ERRO_LOGIN_EMAIL);

    // A ordem importa: primeiro fecha a porta antiga (senha do Supabase vira a
    // interna) e só então guarda o resumo. Se o Supabase falhar, nada muda e a
    // conversão é tentada de novo no próximo login.
    const { error: erroTroca } = await supabaseAdmin.auth.admin.updateUserById(acesso.userid, {
      password: await senhaInterna(acesso.userid),
    });
    if (!erroTroca) {
      const { error: erroResumo } = await supabaseAdmin.rpc("definir_senha_gestor", {
        p_userid: acesso.userid,
        p_contaid: acesso.contaid as unknown as number,
        p_hash: await resumoDaSenha(senha),
      });
      // Se o resumo não gravar, a senha antiga já morreu: avisa para a pessoa
      // usar "Esqueci minha senha" em vez de tentar de novo para sempre.
      if (erroResumo) {
        throw new Error(
          "Sua senha foi atualizada pela metade. Use 'Esqueci minha senha' para definir uma nova.",
        );
      }
    } else {
      console.error("conversão da senha do gestor falhou; será tentada no próximo login", erroTroca.message);
    }
    return { access_token: sessao.session.access_token, refresh_token: sessao.session.refresh_token };
  });

/**
 * Define a senha do gestor depois do convite ou da recuperação por e-mail.
 * O link do Supabase já abriu a sessão; aqui a senha vira nossa e a do Supabase
 * volta a ser o valor interno.
 */
export const definirSenhaDeGestor = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((d: { senha: string; senhaatual?: string }) => d)
  .handler(async ({ data, context }) => {
    const { supabase, userId } = context as unknown as { supabase: ClienteDoUsuario; userId: string };
    const { data: acessoAtual, error: erroAcesso } = await supabase.rpc("meu_acesso");
    if (erroAcesso) throw new Error("Não foi possível confirmar quem é você.");
    const tipo = (acessoAtual as { tipo?: string } | null)?.tipo;
    if (tipo !== "master" && tipo !== "gerente" && tipo !== "admin") {
      throw new Error("Esta tela é do gestor.");
    }

    const senha = conferirSegredo(data.senha, 8, null, "senha");
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { data: achado } = await supabaseAdmin
      .from("contasusuarios")
      .select("contaid")
      .eq("userid", userId)
      .maybeSingle();

    // Quem já tem senha guardada precisa digitar a atual: sem isso, uma sessão
    // esquecida aberta trocaria a senha do dono da conta.
    const { data: guardadaAtual } = await supabaseAdmin
      .from("senhasgestor")
      .select("senhahashapp")
      .eq("userid", userId)
      .maybeSingle();
    const guardada = guardadaAtual?.senhahashapp ?? null;
    if (guardada && !(await senhaConfere(data.senhaatual ?? "", guardada))) {
      throw new Error("A senha atual não confere.");
    }

    // Guarda o resumo primeiro; só depois troca a senha do Supabase.
    const { error: erroBanco } = await supabaseAdmin.rpc("definir_senha_gestor", {
      p_userid: userId,
      p_contaid: (achado?.contaid ?? null) as unknown as number,
      p_hash: await resumoDaSenha(senha),
    });
    if (erroBanco) throw new Error(`Não foi possível salvar a senha: ${erroBanco.message}`);
    const { error } = await supabaseAdmin.auth.admin.updateUserById(userId, {
      password: await senhaInterna(userId),
    });
    if (error) throw new Error(`Não foi possível salvar a senha: ${error.message}`);
    if (guardada) await supabaseAdmin.auth.admin.signOut(userId, "others").catch(() => undefined);
    return { ok: true };
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
  .validator((d: { senha: string; senhaatual?: string }) => d)
  .handler(async ({ data, context }) => {
    const { supabase, userId } = context as unknown as { supabase: ClienteDoUsuario; userId: string };
    await colaboradorDoToken(supabase);
    const pessoa = await pessoaDoToken(userId);
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");

    // Quem JÁ tem senha precisa digitar a atual: sem isso, uma sessão
    // emprestada ou esquecida aberta viraria tomada de conta.
    const { data: atual } = await supabaseAdmin.rpc("senha_app_do_funcionario", {
      p_contaid: pessoa.contaid, p_funcionarioid: pessoa.funcionarioid,
    });
    const guardada = (atual as { senhahash: string | null } | null)?.senhahash ?? null;
    if (guardada && !(await senhaConfere(data.senhaatual ?? "", guardada))) {
      throw new Error("A senha atual não confere.");
    }

    const senha = conferirSegredo(data.senha, 8, pessoa.cpf, "senha");
    const { error } = await supabaseAdmin.rpc("definir_senha_app", {
      p_contaid: pessoa.contaid,
      p_funcionarioid: pessoa.funcionarioid,
      p_hash: await resumoDaSenha(senha),
    });
    if (error) throw new Error(`Não foi possível salvar a senha: ${error.message}`);
    // Trocar a senha derruba as outras sessões (a atual continua).
    if (guardada) await supabaseAdmin.auth.admin.signOut(userId, "others").catch(() => undefined);
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
    const tentativa = await abrirTentativa(pessoa.contaid, "pin", chave, origemDaChamada());

    const pin = conferirSegredo(data.pin, 6, pessoa.cpf, "PIN");
    const { error } = await supabaseAdmin.rpc("definir_pin", {
      p_contaid: pessoa.contaid,
      p_funcionarioid: pessoa.funcionarioid,
      p_pinhash: await resumoDoPin(pessoa.contaid, pin),
      p_provisorio: false,
    });
    await fecharTentativa(tentativa, !error);
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

    // O login vai PRIMEIRO: se o e-mail novo já existir (recontratação), nada
    // muda no cadastro. Se depois o banco recusar, o login volta ao que era —
    // nunca fica um com o CPF novo e o outro com o antigo.
    const emailAntigo = acesso ? (await supabaseAdmin.auth.admin.getUserById(acesso.userid)).data.user?.email : null;
    if (acesso) {
      const { error: erroEmail } = await supabaseAdmin.auth.admin.updateUserById(acesso.userid, {
        email: emailDoColaborador(cpf, contaid),
        email_confirm: true,
      });
      if (erroEmail) {
        throw new Error(
          erroEmail.message.toLowerCase().includes("already")
            ? "Já existe um acesso com esse CPF nesta empresa."
            : `Não foi possível trocar o CPF: ${erroEmail.message}`,
        );
      }
    }

    const { error } = await supabaseAdmin.rpc("trocar_cpf", {
      p_contaid: contaid, p_funcionarioid: data.funcionarioid, p_cpf: cpf,
    });
    if (error) {
      if (acesso && emailAntigo) {
        await supabaseAdmin.auth.admin
          .updateUserById(acesso.userid, { email: emailAntigo, email_confirm: true })
          .catch(() => undefined);
      }
      throw new Error(error.message);
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

    const { data: acesso } = await supabaseAdmin
      .from("contasusuarios")
      .select("userid")
      .eq("contaid", contaid)
      .eq("funcionarioid", data.funcionarioid)
      .maybeSingle();

    if (acesso && !data.ativo) {
      // Senha nova e aleatória: mesmo quem tivesse trocado a própria senha no
      // Supabase por fora perde a entrada. Depois, derruba as sessões.
      await supabaseAdmin.auth.admin
        .updateUserById(acesso.userid, { password: senhaSorteada() + senhaSorteada() })
        .catch(() => undefined);
      await supabaseAdmin.rpc("limpar_senha_gestor", { p_userid: acesso.userid });
      await supabaseAdmin.auth.admin.signOut(acesso.userid, "global").catch(() => undefined);
    }

    if (acesso && data.ativo) {
      // Reativar devolve a senha interna. Sem isto, a pessoa ficava sem entrar
      // para sempre: a senha sorteada na desativação ninguém guarda.
      const { error: erroVolta } = await supabaseAdmin.auth.admin.updateUserById(acesso.userid, {
        password: await senhaInterna(acesso.userid),
      });
      if (erroVolta) throw new Error(`Pessoa reativada, mas o acesso não voltou: ${erroVolta.message}`);
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
    // A senha do tablet também é conferida por nós: guardamos o resumo e a
    // senha do Supabase vira a interna. Assim o tablet não é uma porta aberta.
    const { error: erroResumo } = await supabaseAdmin.rpc("definir_senha_gestor", {
      p_userid: criado.user.id, p_contaid: contaid, p_hash: await resumoDaSenha(senha),
    });
    if (erroResumo) {
      await supabaseAdmin.auth.admin.deleteUser(criado.user.id).catch(() => undefined);
      throw new Error(`Não foi possível criar o acesso: ${erroResumo.message}`);
    }
    const { error: erroInterna } = await supabaseAdmin.auth.admin.updateUserById(criado.user.id, {
      password: await senhaInterna(criado.user.id),
    });
    if (erroInterna) {
      await supabaseAdmin.auth.admin.deleteUser(criado.user.id).catch(() => undefined);
      throw new Error(`Não foi possível criar o acesso: ${erroInterna.message}`);
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
    const { error } = await supabaseAdmin.rpc("definir_senha_gestor", {
      p_userid: acesso.userid, p_contaid: contaid, p_hash: await resumoDaSenha(senha),
    });
    if (error) throw new Error(`Não foi possível redefinir: ${error.message}`);
    const { error: erroInterna } = await supabaseAdmin.auth.admin.updateUserById(acesso.userid, {
      password: await senhaInterna(acesso.userid),
    });
    if (erroInterna) throw new Error(`Não foi possível redefinir: ${erroInterna.message}`);
    // Derruba os tablets que estavam abertos com a senha antiga.
    await supabaseAdmin.auth.admin.signOut(acesso.userid, "global").catch(() => undefined);
    return { usuario: emailDaLoja(data.lojaid, contaid), senha };
  });

// ---------------------------------------------------------------------------
// Diagnóstico: o que está faltando para o sistema funcionar
// ---------------------------------------------------------------------------

/**
 * Responde o que está faltando, sem revelar valor de segredo nenhum: só "tem"
 * ou "não tem". Existe porque uma publicação sem as atualizações do banco
 * deixava todo mundo de fora com uma mensagem que não dizia o motivo.
 */
export const diagnostico = createServerFn({ method: "GET" }).handler(async () => {
  const temPepper = !!process.env["STGAME_PIN_PEPPER"] && process.env["STGAME_PIN_PEPPER"]!.length >= 16;

  // Conta de senha DE VERDADE: a hospedagem tem limites próprios (já recusou
  // 210.000 voltas de PBKDF2 no ar, com tudo certo aqui). Melhor descobrir
  // nesta tela do que na hora de entrar.
  let contaDeSenha = false;
  let erroDaConta = "";
  try {
    if (temPepper) {
      const teste = await resumoDaSenha("conferencia-do-diagnostico");
      contaDeSenha = await senhaConfere("conferencia-do-diagnostico", teste);
    }
  } catch (e) {
    erroDaConta = (e as Error).message;
  }
  const temChave = !!(process.env["STGAME_SERVICE_ROLE_KEY"] ?? process.env["SUPABASE_SERVICE_ROLE_KEY"]);
  const temSite = !!process.env["SITE_URL"];

  let banco: "ok" | "desatualizado" | "sem resposta" = "sem resposta";
  let faltando: string[] = [];
  if (temChave) {
    try {
      const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
      const { data, error } = await supabaseAdmin.rpc("diagnostico_do_sistema");
      if (error) {
        // A própria função de diagnóstico não existe: o banco não recebeu as
        // atualizações desta versão.
        banco = error.message.includes("Could not find") || error.code === "PGRST202" ? "desatualizado" : "sem resposta";
      } else {
        const d = data as { funcoesfaltando: string[]; tabelasfaltando: string[] };
        faltando = [...(d?.funcoesfaltando ?? []), ...(d?.tabelasfaltando ?? [])];
        banco = faltando.length === 0 ? "ok" : "desatualizado";
      }
    } catch {
      banco = "sem resposta";
    }
  }

  return { temPepper, temChave, temSite, contaDeSenha, erroDaConta, banco, faltando };
});
