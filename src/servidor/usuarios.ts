// Usuários gerenciais (parte 5, 30/09/2026): convite, reenvio e desativação.
//
// Tudo começa pelo BANCO, com o token de quem pediu: só o master da conta
// passa (preparar_convite_gerente, email_do_gerente, ativar_usuario_gerencial).
// A chave de serviço só entra depois, para o que o banco não faz sozinho:
// mandar o e-mail do convite e derrubar a sessão. A senha a pessoa cria no
// link do e-mail (/definir-senha); o master nunca a vê.
import { createServerFn } from "@tanstack/react-start";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";

type ClienteDoUsuario = {
  rpc: (nome: string, args?: Record<string, unknown>) => Promise<{ data: unknown; error: { message: string } | null }>;
};

function urlDeDestino() {
  const base = process.env["SITE_URL"] ?? "http://localhost:8080";
  return `${base.replace(/\/$/, "")}/definir-senha`;
}

/** Convida um gerente: confere no banco, manda o e-mail e registra. */
export const convidarGerente = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((d: { nome: string; email: string; cargoid: number; lojas: number[]; funcionarioid: number | null }) => ({
    nome: String(d?.nome ?? "").trim(),
    email: String(d?.email ?? "").trim().toLowerCase(),
    cargoid: Number(d?.cargoid),
    lojas: Array.isArray(d?.lojas) ? d.lojas.filter((n) => Number.isInteger(n)) : [],
    funcionarioid: Number.isInteger(d?.funcionarioid) ? (d.funcionarioid as number) : null,
  }))
  .handler(async ({ data, context }) => {
    const { supabase, userId } = context as unknown as { supabase: ClienteDoUsuario; userId: string };
    // 1. O banco confere tudo pelo token de quem pediu (só o master passa).
    const { data: conta, error } = await supabase.rpc("preparar_convite_gerente", {
      p_nome: data.nome,
      p_email: data.email,
      p_cargoid: data.cargoid,
      p_lojas: data.lojas,
      p_funcionarioid: data.funcionarioid,
    });
    if (error) throw new Error(error.message);
    if (typeof conta !== "number") throw new Error("Não foi possível conferir o convite.");

    // 2. O e-mail do convite (o link leva a /definir-senha).
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { data: convidado, error: erroConvite } = await supabaseAdmin.auth.admin.inviteUserByEmail(data.email, {
      redirectTo: urlDeDestino(),
    });
    if (erroConvite || !convidado?.user?.id) {
      throw new Error(`Não foi possível mandar o convite: ${erroConvite?.message ?? "sem resposta"}`);
    }

    // 3. O registro (só pela chave de serviço; o banco confere que quem
    //    convidou é o master da conta, e o histórico guarda o nome dele).
    const { error: erroRegistro } = await supabaseAdmin.rpc("registrar_gerente_convidado", {
      p_contaid: conta,
      p_userid: convidado.user.id,
      p_nome: data.nome,
      p_cargoid: data.cargoid,
      p_lojas: data.lojas,
      p_funcionarioid: data.funcionarioid as unknown as number,
      p_quem: userId,
    });
    if (erroRegistro) {
      await supabaseAdmin.auth.admin.deleteUser(convidado.user.id).catch(() => undefined);
      throw new Error(`O convite não foi registrado: ${erroRegistro.message}`);
    }
    return { email: data.email };
  });

/** Reenvia o link de criar a senha (o anterior vence). */
export const reenviarConviteGerente = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((d: { userid: string }) => ({ userid: String(d?.userid ?? "") }))
  .handler(async ({ data, context }) => {
    const { supabase } = context as unknown as { supabase: ClienteDoUsuario };
    const { data: email, error } = await supabase.rpc("email_do_gerente", { p_userid: data.userid });
    if (error) throw new Error(error.message);
    if (typeof email !== "string" || !email) throw new Error("Usuário não encontrado.");
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { error: erroEnvio } = await supabaseAdmin.auth.resetPasswordForEmail(email, { redirectTo: urlDeDestino() });
    if (erroEnvio) throw new Error(`Não foi possível reenviar: ${erroEnvio.message}`);
    return { email };
  });

/** Desativa (o banco nega tudo na hora; aqui a sessão cai) ou reativa. */
export const ativarGerente = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((d: { userid: string; ativo: boolean }) => ({ userid: String(d?.userid ?? ""), ativo: d?.ativo === true }))
  .handler(async ({ data, context }) => {
    const { supabase } = context as unknown as { supabase: ClienteDoUsuario };
    const { error } = await supabase.rpc("ativar_usuario_gerencial", { p_userid: data.userid, p_ativo: data.ativo });
    if (error) throw new Error(error.message);
    if (!data.ativo) {
      const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
      await supabaseAdmin.auth.admin.signOut(data.userid, "global").catch(() => undefined);
    }
    return { ok: true };
  });
