// O caminho ANTIGO do aceite e da entrega pelo tablet — temporário, só para
// medir (26/09/2026).
//
// É o código que estava no ar até o commit 08aeefc, sem mudar uma linha da
// lógica, com um cronômetro em cada ida ao banco. Existe para o Wisley comparar
// ANTES e DEPOIS no mesmo tablet, na mesma rede, no mesmo minuto: a tela do
// tablet com `?medir=antigo` usa estas funções; sem isso, usa as novas.
//
// Apagar depois da comparação (está anotado no plano).
import { createServerFn } from "@tanstack/react-start";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import { abrirTentativa, fecharTentativa, origemDaChamada, embaralhar, resumoDoPin } from "@/servidor/segredos";
import { conferirBilhete, conferirHoraDaFoto, provaDaFoto } from "@/servidor/fotodaentrega";
import { cronometro, type ItemDaFila } from "@/servidor/tablet";

type ClienteDoUsuario = {
  rpc: (nome: string, args?: Record<string, unknown>) => Promise<{ data: unknown; error: unknown }>;
};
type Contexto = { supabase: ClienteDoUsuario; userId: string; recebidoem?: number };
type Tablet = { contaid: number; lojaid: number; loja: string };
type Cronometro = ReturnType<typeof cronometro>;

async function tabletDoToken(supabase: ClienteDoUsuario, userId: string, c: Cronometro): Promise<Tablet> {
  const { data, error } = await supabase.rpc("meu_acesso");
  c.marcar("tablet_meuacesso");
  if (error) throw new Error("Não foi possível confirmar o acesso deste tablet.");
  const acesso = data as { tipo?: string; loja?: string } | null;
  if (!acesso || acesso.tipo !== "loja") throw new Error("Esta tela é do tablet da loja.");

  const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
  const { data: vinculo, error: erro } = await supabaseAdmin
    .from("contasusuarios")
    .select("contaid, lojaid")
    .eq("userid", userId)
    .single();
  c.marcar("tablet_vinculo");
  if (erro || !vinculo?.lojaid) throw new Error("Este tablet não está ligado a nenhuma loja.");
  return { contaid: vinculo.contaid, lojaid: vinculo.lojaid, loja: acesso.loja ?? "" };
}

async function pessoaDoPin(t: Tablet, pin: string, c: Cronometro) {
  const limpo = (pin ?? "").trim();
  if (!/^\d{6}$/.test(limpo)) throw new Error("PIN não reconhecido.");

  const chave = await embaralhar(`pintablet:${t.contaid}:${t.lojaid}`);
  const tentativa = await abrirTentativa(t.contaid, "pintablet", chave, origemDaChamada());
  c.marcar("trava_abrir");

  const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
  const { data, error } = await supabaseAdmin.rpc("visao_pessoa_do_pin", {
    p_contaid: t.contaid,
    p_lojaid: t.lojaid,
    p_pinhash: await resumoDoPin(t.contaid, limpo),
  });
  c.marcar("pin");
  const pessoa = data as { funcionarioid: number; nome: string } | null;
  await fecharTentativa(tentativa, !error && !!pessoa);
  c.marcar("trava_fechar");
  if (error) throw new Error("Não foi possível conferir o PIN agora.");
  if (!pessoa) throw new Error("PIN não reconhecido. Confira o número — e lembre que só quem trabalha hoje nesta loja aparece na fila.");
  return pessoa;
}

export const filaDoTabletAntiga = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    const { supabase, userId, recebidoem } = context as unknown as Contexto;
    const c = cronometro(recebidoem);
    const t = await tabletDoToken(supabase, userId, c);
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { data, error } = await supabaseAdmin.rpc("visao_fila", { p_contaid: t.contaid, p_lojaid: t.lojaid });
    c.marcar("fila");
    if (error) throw new Error("Não foi possível carregar a fila agora.");
    const { data: cfg } = await supabaseAdmin
      .from("configuracoes")
      .select("valor")
      .eq("contaid", t.contaid)
      .eq("chave", "MINUTOS_TAREFA_PARADA")
      .maybeSingle();
    c.marcar("configuracao");
    await supabaseAdmin
      .from("lojas")
      .select("somtarefanova, somvolume, somrepetirminutos")
      .eq("contaid", t.contaid)
      .eq("lojaid", t.lojaid)
      .maybeSingle();
    c.marcar("som");
    return { itens: (data ?? []) as unknown as ItemDaFila[], minutosParada: Number(cfg?.valor ?? 30) || 30, tempos: c.fechar() };
  });

export const pegarNoTabletAntigo = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((d: { pin: string; atribuicaoid: number }) => d)
  .handler(async ({ data, context }) => {
    const { supabase, userId, recebidoem } = context as unknown as Contexto;
    const c = cronometro(recebidoem);
    const t = await tabletDoToken(supabase, userId, c);
    const pessoa = await pessoaDoPin(t, data.pin, c);

    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { error } = await supabaseAdmin.rpc("visao_pegar", {
      p_contaid: t.contaid,
      p_lojaid: t.lojaid,
      p_funcionarioid: pessoa.funcionarioid,
      p_atribuicaoid: data.atribuicaoid,
    });
    c.marcar("aceite");
    if (error) throw new Error(error.message);
    return { nome: pessoa.nome, tempos: c.fechar() };
  });

export const entregarNoTabletAntigo = createServerFn({ method: "POST" })
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
    const { supabase, userId, recebidoem } = context as unknown as Contexto;
    const c = cronometro(recebidoem);
    const t = await tabletDoToken(supabase, userId, c);
    const pessoa = await pessoaDoPin(t, data.pin, c);

    let fotoidunico: string | null = null;
    let semhorafoto = false;
    if (data.caminho) {
      if (!data.bilhete) throw new Error("Envio de foto inválido.");
      await conferirBilhete(data.bilhete, data.caminho, data.atribuicaoid, -t.lojaid);
      const prova = await provaDaFoto(data.caminho);
      c.marcar("foto_baixar_e_conferir");
      fotoidunico = prova.fotoidunico;
      ({ semhorafoto } = await conferirHoraDaFoto(t.contaid, prova.horafoto));
      c.marcar("foto_hora");
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
    c.marcar("entrega");
    if (error) throw new Error(error.message);
    return { nome: pessoa.nome, tempos: c.fechar() };
  });
