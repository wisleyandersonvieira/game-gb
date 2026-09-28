// O caminho ANTIGO da entrega pelo celular — temporário, só para medir
// (29/09/2026).
//
// É o código que estava no ar até o commit f4e7ef8, sem mudar uma linha da
// lógica (inclusive o descarte da foto de tentativa recusada), com um
// cronômetro em cada ida ao banco. Existe para o Wisley comparar ANTES e
// DEPOIS no mesmo celular, na mesma rede, no mesmo minuto: a entrega em
// `/eu/tarefas?medir=antigo` usa estas funções (e a foto sem redução, a
// autorização só depois do toque e a recarga da lista numa chamada à parte);
// sem isso, usa as novas.
//
// Apagar depois da comparação (está anotado no plano).
import { createServerFn } from "@tanstack/react-start";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import { ondeRodou } from "@/servidor/segredos";
import { conferirBilhete, conferirHoraDaFoto, emitirBilhete, provaDaFoto } from "@/servidor/fotodaentrega";
import { descartarFotoDaTentativa } from "@/servidor/fotoSemEntrega";
import { cronometro } from "@/servidor/tablet";

type ClienteDoUsuario = {
  rpc: (nome: string, args?: Record<string, unknown>) => Promise<{ data: unknown; error: unknown }>;
};
type Contexto = { supabase: ClienteDoUsuario; userId: string; recebidoem?: number };
type Cronometro = ReturnType<typeof cronometro>;

async function pessoaDoToken(supabase: ClienteDoUsuario, userId: string, c: Cronometro) {
  const { data, error } = await supabase.rpc("meu_acesso");
  c.marcar("pessoa_meuacesso");
  if (error) throw new Error("Não foi possível confirmar o seu acesso.");
  const acesso = data as { tipo?: string; semsenha?: boolean; sempin?: boolean; politicapendente?: boolean } | null;
  if (acesso?.tipo === "desligado") throw new Error("Seu acesso foi encerrado. Fale com o seu gestor.");
  if (acesso?.tipo !== "colaborador") throw new Error("Esta tela é do aplicativo do colaborador.");
  if (acesso.semsenha || acesso.sempin || acesso.politicapendente) {
    throw new Error("Termine o primeiro acesso antes de usar o aplicativo.");
  }
  const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
  const { data: vinculo, error: erro } = await supabaseAdmin
    .from("contasusuarios")
    .select("contaid, funcionarioid")
    .eq("userid", userId)
    .single();
  c.marcar("pessoa_vinculo");
  if (erro || !vinculo?.funcionarioid) throw new Error("Cadastro não encontrado.");
  return { contaid: vinculo.contaid as number, funcionarioid: vinculo.funcionarioid as number };
}

export const autorizacaoDeFotoDoCelularAntiga = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((d: { atribuicaoid: number }) => {
    if (!Number.isInteger(d?.atribuicaoid) || d.atribuicaoid <= 0) throw new Error("Tarefa inválida.");
    return { atribuicaoid: d.atribuicaoid };
  })
  .handler(async ({ data, context }) => {
    const { supabase, userId, recebidoem } = context as unknown as Contexto;
    const c = cronometro(recebidoem);
    const p = await pessoaDoToken(supabase, userId, c);
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { data: tarefa } = await supabaseAdmin
      .from("tarefasatribuidas")
      .select("lojaid")
      .eq("contaid", p.contaid)
      .eq("atribuicaoid", data.atribuicaoid)
      .eq("funcionarioid", p.funcionarioid)
      .maybeSingle();
    c.marcar("tarefa");
    if (!tarefa?.lojaid) throw new Error("Esta tarefa não é sua.");
    const caminho = `${p.contaid}/${tarefa.lojaid}/${crypto.randomUUID()}.jpg`;
    const { data: envio, error } = await supabaseAdmin.storage.from("entregas").createSignedUploadUrl(caminho);
    if (error || !envio) throw new Error("Não foi possível preparar o envio da foto.");
    const bilhete = await emitirBilhete(caminho, data.atribuicaoid, p.funcionarioid);
    return { caminho, token: envio.token, bilhete };
  });

export const entregarPeloCelularAntigo = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((d: { atribuicaoid: number; caminho?: string | null; bilhete?: string | null; observacao?: string | null }) => {
    if (!Number.isInteger(d?.atribuicaoid) || d.atribuicaoid <= 0) throw new Error("Tarefa inválida.");
    const texto = (v: unknown, n: number) => (typeof v === "string" && v !== "" ? v.slice(0, n) : null);
    return { atribuicaoid: d.atribuicaoid, caminho: texto(d.caminho, 300), bilhete: texto(d.bilhete, 200), observacao: texto(d.observacao, 1000) };
  })
  .handler(async ({ data, context }) => {
    const { supabase, userId, recebidoem } = context as unknown as Contexto;
    const c = cronometro(recebidoem);
    const onde: { colo: string; frio: boolean; fotokb?: number } = ondeRodou();
    const p = await pessoaDoToken(supabase, userId, c);
    let fotoidunico: string | null = null;
    let semhorafoto = false;
    if (data.caminho) {
      if (!data.bilhete) throw new Error("Envio de foto inválido.");
      await conferirBilhete(data.bilhete, data.caminho, data.atribuicaoid, p.funcionarioid);
    }
    try {
      if (data.caminho) {
        const prova = await provaDaFoto(data.caminho);
        c.marcar("foto_baixar_e_conferir");
        onde.fotokb = Math.round(prova.tamanho / 1024);
        fotoidunico = prova.fotoidunico;
        ({ semhorafoto } = await conferirHoraDaFoto(p.contaid, prova.horafoto));
        c.marcar("foto_hora");
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
      c.marcar("entrega");
      if (error) throw new Error((error as { message?: string }).message ?? "Não foi possível entregar agora.");
      return { entregaid: id as number, tempos: c.fechar(), onde };
    } catch (e) {
      if (data.caminho) await descartarFotoDaTentativa(data.caminho);
      throw e;
    }
  });
