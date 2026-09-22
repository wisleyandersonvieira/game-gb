// Lógica do @STGameAppBot. Cada ação chama UMA função bot_* do banco, que
// confere o vínculo, a conta e a permissão e usa as mesmas funções de negócio
// das telas. Aqui só se monta a conversa (textos e botões).
//
// Regra de privacidade: nada de console.log com texto de mensagem nem com
// chat_id. Os erros registrados levam só o nome da operação.
import { escaparHtml as h, type Telegram, teclado, type Teclado } from "../_shared/telegram.ts";

// deno-lint-ignore no-explicit-any
type Json = any;
export type Banco = {
  rpc: (fn: string, args?: Record<string, unknown>) => Promise<{ data: Json; error: { message: string } | null }>;
  storage: {
    from: (bucket: string) => {
      upload: (caminho: string, dados: Uint8Array, opcoes: Record<string, unknown>) => Promise<{ error: { message: string } | null }>;
      remove: (caminhos: string[]) => Promise<unknown>;
      createSignedUrl: (caminho: string, segundos: number) => Promise<{ data: { signedUrl: string } | null; error: unknown }>;
    };
  };
};

export type Contexto = { banco: Banco; tg: Telegram; usuarioBot: string };

const PECA_CONVITE = "Peça o convite ao seu gestor.";
const GRUPO_NAO_VINCULADO = "Grupo não vinculado.";

const MENU = {
  reply_markup: {
    keyboard: [
      ["📋 Minhas tarefas", "⭐ Feedback do dia"],
      ["💰 Meu saldo", "📜 Meu histórico"],
      ["🏆 Ranking", "🎯 Meta", "🏅 Conquistas"],
      ["🎁 Prêmios", "🍔 Comanda"],
      ["📢 Comunicados", "📄 Documentos"],
      ["❓ Ajuda"],
    ],
    resize_keyboard: true,
    is_persistent: true,
  },
};

const MENU_TEXTO: Record<string, string> = {
  "📋 Minhas tarefas": "/tarefas",
  "⭐ Feedback do dia": "/feedback",
  "💰 Meu saldo": "/saldo",
  "📜 Meu histórico": "/historico",
  "🏆 Ranking": "/ranking",
  "🎯 Meta": "/meta",
  "🏅 Conquistas": "/conquistas",
  "🎁 Prêmios": "/premios",
  "🍔 Comanda": "/comanda",
  "📢 Comunicados": "/comunicados",
  "📄 Documentos": "/documentos",
  "❓ Ajuda": "/ajuda",
};

const AJUDA = [
  "<b>Como usar o STGame</b>",
  "📋 <b>Minhas tarefas</b>: veja o que é seu hoje e mande a foto de cada tarefa feita.",
  "⭐ <b>Feedback do dia</b>: dê uma nota de 0 a 10 para o seu dia.",
  "💰 <b>Meu saldo</b> e 📜 <b>Meu histórico</b>: seus pontos e suas últimas entregas.",
  "🏆 <b>Ranking</b>, 🎯 <b>Meta</b> e 🏅 <b>Conquistas</b>.",
  "🎁 <b>Prêmios</b> e 🍔 <b>Comanda</b>: troque seus pontos (antes, avalie o dia de ontem).",
  "📢 <b>Comunicados</b> e 📄 <b>Documentos</b>: leia e confirme que está ciente.",
  "Digite /cancelar para desistir de uma ação.",
].join("\n");

const reais = (v: number) => new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(v);
const num = (v: number) => Number(v).toLocaleString("pt-BR", { maximumFractionDigits: 1 });

class Conversa {
  enviadas = 0;
  constructor(private c: Contexto, public chatId: number) {}
  async enviar(texto: string, extra: Record<string, unknown> = {}) {
    const r = await this.c.tg.enviar(this.chatId, texto, extra);
    if (r.ok) this.enviadas++;
    return r;
  }
}

async function rpc(c: Contexto, fn: string, args: Record<string, unknown>): Promise<Json> {
  const { data, error } = await c.banco.rpc(fn, args);
  if (error) {
    console.error(`[bot] falha em ${fn}`);
    return { ok: false, erro: "falha", mensagem: "Não consegui fazer isso agora. Tente de novo em instantes." };
  }
  return data;
}

/** Mensagem de erro amigável para o que a função do banco devolveu. */
function textoDeErro(r: Json): string {
  if (r?.erro === "sem_vinculo") return PECA_CONVITE;
  if (r?.erro === "falta_feedback") return "Antes de trocar pontos, avalie o seu dia de ontem em ⭐ Feedback do dia.";
  return h(r?.mensagem ?? "Não deu certo. Tente de novo.");
}

// ---------------------------------------------------------------------------
// Entrada
// ---------------------------------------------------------------------------
export function processar(c: Contexto, u: Json): Promise<void> {
  if (u.callback_query) return botao(c, u.callback_query);
  if (u.my_chat_member) return membroDoGrupo(c, u.my_chat_member);
  const m = u.message;
  if (m?.chat?.type === "private") return privada(c, m);
  if (m?.chat?.type === "group" || m?.chat?.type === "supergroup") return grupo(c, m);
  return Promise.resolve();
}

// ---------------------------------------------------------------------------
// Conversa privada
// ---------------------------------------------------------------------------
function comando(texto: string, usuarioBot: string): { cmd: string; resto: string } | null {
  const t = (MENU_TEXTO[texto.trim()] ?? texto).trim();
  const achou = t.match(/^\/([a-z_]+)(?:@([A-Za-z0-9_]+))?(?:\s+([\s\S]*))?$/);
  if (!achou) return null;
  if (achou[2] && achou[2].toLowerCase() !== usuarioBot.toLowerCase()) return null;
  return { cmd: achou[1], resto: (achou[3] ?? "").trim() };
}

async function privada(c: Contexto, m: Json) {
  const conversa = new Conversa(c, m.chat.id);
  try {
    await privadaInterna(c, m, conversa);
  } finally {
    if (conversa.enviadas > 0) await rpc(c, "bot_registrar_uso", { p_chatid: m.chat.id, p_tipo: "resposta", p_qtd: conversa.enviadas });
  }
}

async function privadaInterna(c: Contexto, m: Json, cv: Conversa) {
  const chat = m.chat.id as number;
  const texto: string = typeof m.text === "string" ? m.text : "";
  const cmd = texto ? comando(texto, c.usuarioBot) : null;

  // /start com código: vínculo.
  if (cmd?.cmd === "start" && cmd.resto) {
    const nome = [m.from?.first_name, m.from?.last_name].filter(Boolean).join(" ");
    const r = await rpc(c, "bot_usar_convite", { p_chatid: chat, p_tipochat: "private", p_codigo: cmd.resto, p_nome: nome });
    if (!r?.ok) return void (await cv.enviar(PECA_CONVITE, { reply_markup: { remove_keyboard: true } }));
    if (r.tipo === "master") {
      return void (await cv.enviar(`✅ Seu Telegram foi ligado ao STGame (<b>${h(r.empresa)}</b>).\nAqui você recebe os avisos da sua empresa.`));
    }
    return void (await cv.enviar(`✅ Olá, <b>${h(r.nome)}</b>! Você está ligado(a) à <b>${h(r.empresa)}</b>.\n\n${AJUDA}`, MENU));
  }

  const quem = await rpc(c, "bot_quem", { p_chatid: chat });
  if (quem?.status === "sem_vinculo" || !quem?.status) {
    return void (await cv.enviar(PECA_CONVITE, { reply_markup: { remove_keyboard: true } }));
  }
  if (quem.status === "escolher" || cmd?.cmd === "empresa") {
    const opcoes = quem.opcoes ?? [];
    if (quem.status === "ok" && !quem.varias) return void (await cv.enviar(`Você está ligado(a) só à <b>${h(quem.empresa)}</b>.`));
    return void (await cv.enviar("Você trabalha em mais de uma empresa. Com qual quer falar agora?",
      teclado((opcoes.length ? opcoes : []).map((o: Json) => [{ text: o.empresa, callback_data: `emp:${o.contaid}` }]))));
  }
  if (quem.tipo === "master") {
    return void (await cv.enviar(`Você está ligado(a) como responsável da <b>${h(quem.empresa)}</b>. Aqui chegam os avisos. As aprovações são feitas no grupo de gestão da loja.`));
  }

  if (cmd?.cmd === "cancelar") {
    await rpc(c, "bot_limpar_estado", { p_chatid: chat, p_usuarioid: chat });
    return void (await cv.enviar("Tudo bem, cancelado.", MENU));
  }

  // Foto ou arquivo.
  if (m.photo) return foto(c, m, cv);
  if (m.document || m.video || m.animation) {
    return void (await cv.enviar("📷 Envie a evidência como <b>foto</b> (pela câmera ou galeria), não como arquivo."));
  }

  if (cmd) return comandoPrivado(c, cv, quem, cmd.cmd);

  // Texto livre: pode ser a resposta de um passo em andamento.
  const e = await rpc(c, "bot_estado", { p_chatid: chat, p_usuarioid: chat });
  if (e?.estado === "nao_aplicavel" && texto.trim()) {
    const r = await rpc(c, "bot_nao_aplicavel", { p_chatid: chat, p_motivo: texto.trim().slice(0, 500) });
    return void (await cv.enviar(r?.ok ? "🤷 Registrado como \"não se aplica\". O gestor vai decidir." : textoDeErro(r), MENU));
  }
  if (e?.estado === "comanda") {
    const valor = Number(texto.replace(/[^\d,.-]/g, "").replace(/\.(?=\d{3}(\D|$))/g, "").replace(",", "."));
    if (!(valor > 0)) return void (await cv.enviar("Digite só o valor em reais, por exemplo: <b>15,50</b>. Ou /cancelar."));
    const r = await rpc(c, "bot_comanda", { p_chatid: chat, p_valor: valor });
    if (!r?.ok) return void (await cv.enviar(textoDeErro(r), MENU));
    return void (await cv.enviar(`🍔 Pedido de abate de <b>${reais(r.valor)}</b> registrado (${r.pontos} pontos). A gestão confirma no caixa.\nSaldo agora: <b>${r.saldo}</b> pontos.`, MENU));
  }
  if (e?.estado === "foto") return void (await cv.enviar("📷 Estou esperando a <b>foto</b> da tarefa. Ou /cancelar."));
  await cv.enviar(`Não entendi. Use os botões do menu.\n\n${AJUDA}`, MENU);
}

async function comandoPrivado(c: Contexto, cv: Conversa, quem: Json, cmd: string) {
  const chat = cv.chatId;
  switch (cmd) {
    case "start":
    case "menu":
      return void (await cv.enviar(`Olá, <b>${h(quem.nome)}</b>! (${h(quem.empresa)})\n\n${AJUDA}`, MENU));
    case "ajuda":
      return void (await cv.enviar(AJUDA, MENU));
    case "tarefas": {
      const r = await rpc(c, "bot_tarefas", { p_chatid: chat });
      if (!r?.ok) return void (await cv.enviar(textoDeErro(r)));
      if (!r.tarefas.length) return void (await cv.enviar("✨ Nada pendente para hoje. Bom trabalho!"));
      await cv.enviar("📋 <b>Suas tarefas de hoje</b>");
      for (const t of r.tarefas.slice(0, 15)) {
        await cv.enviar(`${t.atrasada ? "⚠️ <b>Atrasada</b> · " : ""}<b>${h(t.titulo)}</b> · ${t.pontos} pts\n🏪 ${h(t.loja)}`,
          teclado([[{ text: "📸 Enviar foto", callback_data: `ent:${t.atribuicaoid}` }, { text: "🤷 Não se aplica", callback_data: `na:${t.atribuicaoid}` }]]));
      }
      return;
    }
    case "saldo": {
      const r = await rpc(c, "bot_consulta", { p_chatid: chat, p_item: "saldo" });
      if (!r?.ok) return void (await cv.enviar(textoDeErro(r)));
      return void (await cv.enviar(`💰 Você tem <b>${r.saldo}</b> pontos${r.reais != null ? ` (≈ ${reais(r.reais)})` : ""}.`));
    }
    case "historico": {
      const r = await rpc(c, "bot_consulta", { p_chatid: chat, p_item: "historico" });
      if (!r?.ok) return void (await cv.enviar(textoDeErro(r)));
      if (!r.itens?.length) return void (await cv.enviar("Você ainda não tem entregas."));
      const icone: Record<string, string> = { Aprovada: "✅", Recusada: "❌", Pendente: "⏳", Estornada: "↩️" };
      const linhas = r.itens.map((i: Json) =>
        `${icone[i.status] ?? "•"} ${h(i.titulo)}${i.status === "Aprovada" ? ` · +${i.pontos}` : ""}${i.motivo ? `\n   <i>${h(i.motivo)}</i>` : ""}`);
      return void (await cv.enviar(`📜 <b>Suas últimas entregas</b>\n${linhas.join("\n")}`));
    }
    case "conquistas": {
      const r = await rpc(c, "bot_consulta", { p_chatid: chat, p_item: "conquistas" });
      if (!r?.ok) return void (await cv.enviar(textoDeErro(r)));
      if (!r.itens?.length) return void (await cv.enviar("Nenhuma conquista ainda. Continue! 💪"));
      return void (await cv.enviar(`🏅 <b>Suas conquistas</b>\n${r.itens.map((i: Json) => `${h(i.icone ?? "")} <b>${h(i.nome)}</b>`).join("\n")}`));
    }
    case "ranking": {
      const r = await rpc(c, "bot_consulta", { p_chatid: chat, p_item: "ranking" });
      if (!r?.ok) return void (await cv.enviar(textoDeErro(r)));
      if (!r.itens?.length) return void (await cv.enviar("O ranking do mês começa a aparecer amanhã."));
      const medalha = ["🥇", "🥈", "🥉"];
      const linhas = r.itens.map((i: Json) =>
        `${medalha[i.posicao - 1] ?? `${i.posicao}º`} ${i.eu ? "<b>" : ""}${h(i.nome)} · ${num(i.nota)}${i.eu ? " (você)</b>" : ""}`);
      return void (await cv.enviar(`🏆 <b>Nota do mês</b> (até ontem)\n${linhas.join("\n")}`));
    }
    case "meta": {
      const r = await rpc(c, "bot_consulta", { p_chatid: chat, p_item: "meta" });
      if (!r?.ok) return void (await cv.enviar(textoDeErro(r)));
      const linhas = (r.lojas ?? []).map((l: Json) => {
        const m = l.meta;
        if (!m) return `🏪 ${h(l.loja)}: sem meta definida`;
        const dia = m.dia ? `hoje ${num(m.dia.percentual)}%${m.dia.bateu ? " 🎉" : ""}` : "hoje sem meta";
        const mes = m.mes ? ` · mês ${num(m.mes.percentual)}%${m.mes.bateu ? " 🏆" : ""}` : "";
        return `🏪 ${h(l.loja)}: ${dia}${mes}`;
      });
      return void (await cv.enviar(`🎯 <b>Meta</b>\n${linhas.join("\n") || "Sem meta definida."}`));
    }
    case "feedback": {
      const r = await rpc(c, "bot_consulta", { p_chatid: chat, p_item: "feedback" });
      if (!r?.ok) return void (await cv.enviar(textoDeErro(r)));
      const botoes: Teclado = [];
      if (r.faltaontem) botoes.push([{ text: "⭐ Avaliar ontem", callback_data: "fbm:ontem" }]);
      if (!r.hoje) botoes.push([{ text: "⭐ Avaliar hoje", callback_data: "fbm:hoje" }]);
      if (!botoes.length) return void (await cv.enviar("✅ Seu feedback de hoje já foi enviado. Obrigado!"));
      return void (await cv.enviar("Como foi o seu dia?", teclado(botoes)));
    }
    case "premios": {
      const r = await rpc(c, "bot_consulta", { p_chatid: chat, p_item: "premios" });
      if (!r?.ok) return void (await cv.enviar(textoDeErro(r)));
      if (r.travado) {
        return void (await cv.enviar(`🎁 Você tem <b>${r.saldo}</b> pontos. Para trocar, avalie primeiro o seu dia de ontem.`,
          teclado([[{ text: "⭐ Avaliar ontem", callback_data: "fbm:ontem" }]])));
      }
      const linhas: Teclado = (r.itens ?? []).slice(0, 20).map((p: Json) => [{
        text: `🎁 ${p.nome} · ${p.custo} pts${p.estoque != null ? ` (${p.estoque})` : ""}`, callback_data: `pr:${p.produtoid}`,
      }]);
      if (r.comanda) linhas.push([{ text: "🍔 Abater na comanda", callback_data: "com" }]);
      if (!linhas.length) return void (await cv.enviar(`Você tem <b>${r.saldo}</b> pontos. Ainda não há prêmios cadastrados.`));
      return void (await cv.enviar(`🎁 <b>Prêmios</b> · você tem <b>${r.saldo}</b> pontos`, teclado(linhas)));
    }
    case "comanda":
      return comandaIniciar(c, cv);
    case "comunicados": {
      const r = await rpc(c, "bot_consulta", { p_chatid: chat, p_item: "comunicados" });
      if (!r?.ok) return void (await cv.enviar(textoDeErro(r)));
      if (!r.itens?.length) return void (await cv.enviar("📢 Nenhum comunicado esperando a sua ciência."));
      for (const i of r.itens.slice(0, 5)) {
        await cv.enviar(`📢 <b>${h(i.titulo)}</b>\n\n${h(i.conteudo)}${i.pontos > 0 ? `\n\n🎁 +${i.pontos} pontos ao confirmar.` : ""}`,
          teclado([[{ text: "✅ Estou ciente", callback_data: `ci:${i.assinaturaid}` }]]));
      }
      return;
    }
    case "documentos": {
      const r = await rpc(c, "bot_consulta", { p_chatid: chat, p_item: "documentos" });
      if (!r?.ok) return void (await cv.enviar(textoDeErro(r)));
      if (!r.itens?.length) return void (await cv.enviar("📄 Nenhum documento disponível."));
      return void (await cv.enviar("📄 <b>Seus documentos</b>\nO link abre por 5 minutos.",
        teclado(r.itens.map((d: Json) => [{ text: `${d.pendente ? "⚠️ " : ""}📄 ${d.tipo}${d.mes ? ` ${d.mes}` : ""}`, callback_data: `doc:${d.documentoid}` }]))));
    }
    default:
      return void (await cv.enviar(`Não conheço esse comando.\n\n${AJUDA}`, MENU));
  }
}

async function comandaIniciar(c: Contexto, cv: Conversa) {
  const r = await rpc(c, "bot_comanda_iniciar", { p_chatid: cv.chatId });
  if (!r?.ok) {
    return void (await cv.enviar(textoDeErro(r), r?.erro === "falta_feedback" ? teclado([[{ text: "⭐ Avaliar ontem", callback_data: "fbm:ontem" }]]) : {}));
  }
  await cv.enviar(`🍔 <b>Abater na comanda</b>\nVocê tem <b>${r.saldo}</b> pontos (≈ ${reais(r.reais)}).\nDigite o valor em reais que quer abater, por exemplo <b>15,50</b>. Ou /cancelar.`);
}

/** Foto da entrega: sem encaminhada, dentro de 10 minutos, foto nova. */
async function foto(c: Contexto, m: Json, cv: Conversa) {
  const chat = cv.chatId;
  if (m.forward_origin || m.forward_from || m.forward_from_chat || m.forward_date) {
    return void (await cv.enviar("❌ Foto encaminhada não vale. Tire a foto agora e envie."));
  }
  const maior = m.photo[m.photo.length - 1];
  const conf = await rpc(c, "bot_conferir_foto", { p_chatid: chat, p_fotoidunico: maior.file_unique_id });
  if (!conf?.ok) {
    const msg: Record<string, string> = {
      sem_tarefa: "Primeiro escolha a tarefa em 📋 Minhas tarefas e toque em 📸 Enviar foto.",
      expirou: "⏰ Passaram os 10 minutos. Toque em 📸 Enviar foto de novo e mande a foto em seguida.",
      repetida: "❌ Esta foto já foi usada. Tire uma foto nova.",
    };
    return void (await cv.enviar(msg[conf?.erro] ?? textoDeErro(conf)));
  }
  let caminho = "";
  try {
    const dados = await c.tg.baixar(maior.file_id);
    caminho = `${conf.contaid}/${conf.lojaid}/tg-${Date.now()}-${crypto.randomUUID().slice(0, 8)}.jpg`;
    const { error } = await c.banco.storage.from("entregas").upload(caminho, dados, { contentType: "image/jpeg", upsert: false });
    if (error) throw new Error("upload");
  } catch {
    console.error("[bot] falha ao guardar foto");
    return void (await cv.enviar("Não consegui receber a foto agora. Tente de novo em instantes."));
  }
  const r = await rpc(c, "bot_registrar_entrega", {
    p_chatid: chat, p_atribuicaoid: conf.atribuicaoid, p_caminho: caminho, p_fileid: maior.file_id, p_fotoidunico: maior.file_unique_id,
  });
  if (!r?.ok) {
    await c.banco.storage.from("entregas").remove([caminho]);
    return void (await cv.enviar(r?.erro === "repetida" ? "❌ Esta foto já foi usada. Tire uma foto nova." : textoDeErro(r)));
  }
  await cv.enviar(`✅ Foto recebida! <b>${h(r.titulo)}</b> foi para validação.`, MENU);
}

// ---------------------------------------------------------------------------
// Botões
// ---------------------------------------------------------------------------
async function botao(c: Contexto, q: Json) {
  const dado: string = q.data ?? "";
  const msg = q.message;
  if (!msg?.chat) return void (await c.tg.responderBotao(q.id));
  if (msg.chat.type !== "private") return botaoDoGrupo(c, q);

  const cv = new Conversa(c, msg.chat.id);
  try {
    await botaoPrivado(c, q, cv, dado);
  } finally {
    if (cv.enviadas > 0) await rpc(c, "bot_registrar_uso", { p_chatid: cv.chatId, p_tipo: "resposta", p_qtd: cv.enviadas });
  }
}

async function botaoPrivado(c: Contexto, q: Json, cv: Conversa, dado: string) {
  const chat = cv.chatId;
  const [acao, a, b] = dado.split(":");
  const id = Number(a);
  const responder = (t?: string, alerta = false) => c.tg.responderBotao(q.id, t, alerta);

  if (acao === "emp") {
    const r = await rpc(c, "bot_escolher_conta", { p_chatid: chat, p_contaid: id });
    await responder();
    return void (await cv.enviar(r?.ok ? `Agora você está falando com a <b>${h(r.empresa)}</b>.` : PECA_CONVITE, r?.ok ? MENU : {}));
  }
  if (acao === "ent") {
    const r = await rpc(c, "bot_iniciar_entrega", { p_chatid: chat, p_atribuicaoid: id });
    await responder();
    return void (await cv.enviar(r?.ok ? `📸 Envie agora a <b>foto</b> de <b>${h(r.titulo)}</b>. Você tem 10 minutos.` : textoDeErro(r)));
  }
  if (acao === "na") {
    const r = await rpc(c, "bot_nao_aplicavel_iniciar", { p_chatid: chat, p_atribuicaoid: id });
    await responder();
    return void (await cv.enviar(r?.ok ? `🤷 Por que <b>${h(r.titulo)}</b> não se aplica hoje? Escreva o motivo numa mensagem.` : textoDeErro(r)));
  }
  if (acao === "fbm") {
    await responder();
    const quando = a === "ontem" ? "ontem" : "hoje";
    const linhas: Teclado = [[0, 1, 2, 3, 4, 5], [6, 7, 8, 9, 10]].map((l) => l.map((n) => ({ text: String(n), callback_data: `fb:${quando}:${n}` })));
    return void (await cv.enviar(`De 0 a 10, como foi o seu dia ${quando === "ontem" ? "de ontem" : "de hoje"}?`, teclado(linhas)));
  }
  if (acao === "fb") {
    const r = await rpc(c, "bot_feedback", { p_chatid: chat, p_quando: a === "ontem" ? "ontem" : "hoje", p_nota: Number(b) });
    await responder(r?.ok ? "Obrigado!" : undefined);
    return void (await cv.enviar(r?.ok ? `⭐ Obrigado pelo feedback!${r.bonus > 0 ? ` +${r.bonus} pontos.` : ""}` : textoDeErro(r)));
  }
  if (acao === "pr") {
    await responder();
    return void (await cv.enviar("Confirma a troca?", teclado([[{ text: "✅ Confirmar", callback_data: `prc:${id}` }, { text: "Voltar", callback_data: "x" }]])));
  }
  if (acao === "prc") {
    const r = await rpc(c, "bot_resgatar", { p_chatid: chat, p_produtoid: id });
    await responder();
    return void (await cv.enviar(r?.ok ? `🎁 Pedido de <b>${h(r.premio)}</b> registrado! A gestão vai entregar.\nSaldo agora: <b>${r.saldo}</b> pontos.` : textoDeErro(r)));
  }
  if (acao === "com") {
    await responder();
    return comandaIniciar(c, cv);
  }
  if (acao === "ci") {
    const r = await rpc(c, "bot_ciencia", { p_chatid: chat, p_assinaturaid: id });
    await responder(r?.ok ? "Ciência registrada" : undefined);
    if (!r?.ok) return void (await cv.enviar(textoDeErro(r)));
    const quando = new Date(r.quando).toLocaleString("pt-BR", { timeZone: "America/Sao_Paulo" });
    return void (await cv.enviar(`📜 <b>Recibo de ciência</b>\n${h(r.titulo)}\nRegistrado em ${quando}.${r.pontos > 0 ? `\n🎁 +${r.pontos} pontos.` : ""}`));
  }
  if (acao === "doc") {
    const r = await rpc(c, "bot_documento", { p_chatid: chat, p_tipochat: "private", p_documentoid: id });
    if (!r?.ok) {
      await responder();
      return void (await cv.enviar(textoDeErro(r)));
    }
    const { data } = await c.banco.storage.from("documentos-rh").createSignedUrl(r.caminho, 300);
    await responder();
    if (!data?.signedUrl) return void (await cv.enviar("Não consegui abrir o documento agora. Tente de novo."));
    const botoes: Teclado = [[{ text: "📄 Abrir (vale 5 minutos)", url: data.signedUrl }]];
    if (r.pendente) botoes.push([{ text: "✅ Recebi e estou ciente", callback_data: `docc:${id}` }]);
    return void (await cv.enviar(`📄 <b>${h(r.tipo)}${r.mes ? ` ${h(r.mes)}` : ""}</b>`, teclado(botoes)));
  }
  if (acao === "docc") {
    const r = await rpc(c, "bot_ciencia_documento", { p_chatid: chat, p_documentoid: id });
    await responder(r?.ok ? "Ciência registrada" : undefined);
    return void (await cv.enviar(r?.ok ? "✅ Ciência do documento registrada." : textoDeErro(r)));
  }
  await responder();
}

// ---------------------------------------------------------------------------
// Grupos (Group Privacy ligado: chegam comandos com @bot, respostas às
// mensagens do bot, botões e o aviso de "bot adicionado").
// ---------------------------------------------------------------------------
async function membroDoGrupo(c: Contexto, mcm: Json) {
  const chat = mcm.chat;
  if (!chat || chat.type === "private") return;
  const entrou = ["member", "administrator"].includes(mcm.new_chat_member?.status) && !["member", "administrator"].includes(mcm.old_chat_member?.status);
  if (!entrou) return;
  const g = await rpc(c, "bot_grupo", { p_chatid: chat.id });
  if (!g?.vinculado) await c.tg.enviar(chat.id, GRUPO_NAO_VINCULADO);
}

async function grupo(c: Contexto, m: Json) {
  const chat = m.chat.id as number;
  const texto: string = typeof m.text === "string" ? m.text : "";
  const cmd = texto ? comando(texto, c.usuarioBot) : null;
  const g = await rpc(c, "bot_grupo", { p_chatid: chat });
  let enviadas = 0;
  const enviar = async (t: string, extra: Record<string, unknown> = {}) => {
    const r = await c.tg.enviar(chat, t, { reply_to_message_id: m.message_id, allow_sending_without_reply: true, ...extra });
    if (r.ok) enviadas++;
    return r;
  };

  try {
    if (!g?.vinculado) {
      if (cmd?.cmd === "vincular" && cmd.resto) {
        const r = await rpc(c, "bot_usar_convite", { p_chatid: chat, p_tipochat: m.chat.type, p_codigo: cmd.resto, p_nome: m.chat.title ?? "" });
        if (r?.ok && r.tipo === "grupo") {
          await c.tg.enviar(chat, `✅ Grupo ligado: ${r.papel === "gestao" ? "gestão" : "equipe"} da <b>${h(r.loja)}</b>.`);
          return;
        }
      }
      if (cmd) await c.tg.enviar(chat, GRUPO_NAO_VINCULADO);
      return;
    }

    // Resposta à pergunta do motivo da recusa.
    const resposta = m.reply_to_message;
    if (resposta?.from?.is_bot && texto && !cmd) {
      const r = await rpc(c, "bot_recusa_motivo", { p_chatgrupo: chat, p_usuario: m.from.id, p_respostaa: resposta.message_id, p_motivo: texto.trim().slice(0, 500) });
      if (r?.ok) {
        await atualizarMensagemDaEntrega(c, chat, r.entregaid);
        await enviar(`❌ Entrega recusada por ${h(r.validador)}. A pessoa vai receber o motivo.`);
      } else if (r?.erro === "sem_permissao") {
        await enviar("Sem permissão.");
      } else if (r?.erro === "ja_validada") {
        await enviar("Esta entrega já foi validada.");
      } else if (r?.erro && r.erro !== "sem_pedido") {
        await enviar(textoDeErro(r));
      }
      return;
    }
    if (!cmd) return;

    if (cmd.cmd === "vincular") return void (await enviar("Este grupo já está ligado."));
    if (["pendencias", "lancar", "status_meta"].includes(cmd.cmd) && g.papel !== "gestao") {
      return void (await enviar("Este comando é do grupo de gestão."));
    }
    if (cmd.cmd === "pendencias") {
      const r = await rpc(c, "bot_pendencias", { p_chatgrupo: chat, p_usuario: m.from.id });
      if (!r?.ok) return void (await enviar(r?.erro === "sem_permissao" ? "Sem permissão." : textoDeErro(r)));
      const pessoas = (r.pessoas ?? []).map((p: Json) => `👤 <b>${h(p.nome)}</b>: ${p.tarefas.map((t: string) => h(t)).join(", ")}`);
      return void (await enviar(`📋 <b>Pendências de hoje · ${h(r.loja)}</b>\n⏳ ${r.avalidar} entrega(s) para validar\n${pessoas.join("\n") || "Nenhuma tarefa em aberto. 👏"}`));
    }
    if (cmd.cmd === "lancar") {
      const partes = cmd.resto.match(/^([\d.,]+)\s*([\s\S]*)$/);
      const valor = partes ? Number(partes[1].replace(/\.(?=\d{3}(\D|$))/g, "").replace(",", ".")) : NaN;
      if (!(valor >= 0)) return void (await enviar("Use assim: /lancar 1250,50 (e um motivo, se for correção)."));
      const r = await rpc(c, "bot_lancar", { p_chatgrupo: chat, p_usuario: m.from.id, p_valor: valor, p_motivo: partes?.[2]?.trim() || null });
      if (!r?.ok) return void (await enviar(r?.erro === "sem_permissao" ? "Sem permissão." : textoDeErro(r)));
      return void (await enviar(`✅ Venda de hoje: <b>${reais(valor)}</b> (${h(r.validador)}).\n${textoMeta(r.meta)}`));
    }
    if (cmd.cmd === "status_meta") {
      const r = await rpc(c, "bot_status_meta", { p_chatgrupo: chat, p_usuario: m.from.id });
      if (!r?.ok) return void (await enviar(r?.erro === "sem_permissao" ? "Sem permissão." : textoDeErro(r)));
      return void (await enviar(`🎯 <b>${h(r.loja)}</b>\n${textoMeta(r.meta)}`));
    }
    if (cmd.cmd === "ajuda" || cmd.cmd === "start") {
      return void (await enviar(g.papel === "gestao"
        ? "Grupo de gestão. Aprove ou recuse as entregas pelos botões. Comandos: /pendencias, /lancar 1250,50, /status_meta."
        : "Grupo da equipe. Aqui aparecem os avisos da loja."));
    }
  } finally {
    if (enviadas > 0) await rpc(c, "bot_registrar_uso", { p_chatid: chat, p_tipo: "resposta", p_qtd: enviadas });
  }
}

function textoMeta(m: Json): string {
  if (!m) return "Sem meta definida para hoje.";
  const partes: string[] = [];
  if (m.dia) partes.push(`Hoje: <b>${num(m.dia.percentual)}%</b>${m.dia.meta != null ? ` de ${reais(m.dia.meta)}` : ""}${m.dia.bateu ? " 🎉" : ""}`);
  if (m.mes) partes.push(`Mês: <b>${num(m.mes.percentual)}%</b>${m.mes.meta != null ? ` de ${reais(m.mes.meta)}` : ""}${m.mes.projecao ? ` · projeção ${reais(m.mes.projecao)}` : ""}`);
  return partes.join("\n") || "Sem meta definida para hoje.";
}

async function atualizarMensagemDaEntrega(c: Contexto, chat: number, entregaid: number, messageId?: number, temFoto?: boolean) {
  const l = await rpc(c, "bot_legenda_entrega", { p_entregaid: entregaid });
  if (!l?.texto) return;
  // Sem o id (recusa pela resposta), usa a mensagem guardada no envio da fila.
  const alvo = messageId ?? l.avisomsgid;
  const foto = temFoto ?? l.temfoto;
  if (!alvo) return;
  await c.tg.chamar(foto ? "editMessageCaption" : "editMessageText", {
    chat_id: chat, message_id: alvo, [foto ? "caption" : "text"]: l.texto, parse_mode: "HTML", reply_markup: { inline_keyboard: [] },
  });
}

async function botaoDoGrupo(c: Contexto, q: Json) {
  const msg = q.message;
  const chat = msg.chat.id as number;
  const [acao, a] = String(q.data ?? "").split(":");
  const id = Number(a);
  const temFoto = Array.isArray(msg.photo) && msg.photo.length > 0;

  if (acao === "ap") {
    const r = await rpc(c, "bot_validar", { p_chatgrupo: chat, p_usuario: q.from.id, p_entregaid: id, p_aprovar: true, p_motivo: null });
    if (r?.erro === "sem_permissao" || r?.erro === "grupo") return void (await c.tg.responderBotao(q.id, "Sem permissão.", true));
    if (r?.erro === "ja_validada") {
      await c.tg.responderBotao(q.id, "Esta entrega já foi validada.", true);
      return atualizarMensagemDaEntrega(c, chat, id, msg.message_id, temFoto);
    }
    if (!r?.ok) return void (await c.tg.responderBotao(q.id, String(r?.mensagem ?? "Não deu certo.").slice(0, 190), true));
    await c.tg.responderBotao(q.id, `Aprovada ✅ +${r.pontos} pts`);
    return atualizarMensagemDaEntrega(c, chat, id, msg.message_id, temFoto);
  }
  if (acao === "rc") {
    const r = await rpc(c, "bot_recusa_pedir", { p_chatgrupo: chat, p_usuario: q.from.id, p_entregaid: id });
    if (r?.erro === "sem_permissao" || r?.erro === "grupo") return void (await c.tg.responderBotao(q.id, "Sem permissão.", true));
    if (r?.erro === "ja_validada") {
      await c.tg.responderBotao(q.id, "Esta entrega já foi validada.", true);
      return atualizarMensagemDaEntrega(c, chat, id, msg.message_id, temFoto);
    }
    if (!r?.ok) return void (await c.tg.responderBotao(q.id, String(r?.mensagem ?? "Não deu certo.").slice(0, 190), true));
    const pergunta = await c.tg.enviar(chat, `✍️ ${h(r.nome)}, responda <b>esta mensagem</b> com o motivo da recusa.`, {
      reply_to_message_id: msg.message_id, allow_sending_without_reply: true, reply_markup: { force_reply: true, input_field_placeholder: "Motivo da recusa" },
    });
    if (pergunta.ok && pergunta.result?.message_id) {
      await rpc(c, "bot_recusa_guardar", { p_chatgrupo: chat, p_usuario: q.from.id, p_entregaid: id, p_msgid: pergunta.result.message_id });
      await rpc(c, "bot_registrar_uso", { p_chatid: chat, p_tipo: "resposta", p_qtd: 1 });
    }
    return void (await c.tg.responderBotao(q.id, "Escreva o motivo respondendo a mensagem do bot."));
  }
  await c.tg.responderBotao(q.id);
}
