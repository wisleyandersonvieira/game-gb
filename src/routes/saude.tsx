// Tela de saúde do sistema: diz o que está faltando para o app funcionar,
// sem mostrar o valor de segredo nenhum (só "configurado" ou "faltando").
//
// Existe porque uma publicação sem as atualizações do banco deixou todo mundo
// de fora — inclusive o administrador — com uma mensagem que não dizia o motivo.
import { createFileRoute } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { diagnostico, type SaudeDasRotinas } from "@/servidor/acesso";
import { Logo } from "@/ui/Logo";
import { VERSAO, versaoEmTexto } from "@/ui/versao";
import { dataHoraBr } from "@/rh/datas";

export const Route = createFileRoute("/saude")({
  ssr: false,
  head: () => ({ meta: [{ title: "Saúde do sistema — STGame" }, { name: "robots", content: "noindex, nofollow" }] }),
  component: Saude,
});

function Linha({ ok, titulo, ajuda }: { ok: boolean; titulo: string; ajuda: string }) {
  return (
    <li className="flex gap-3 rounded-lg border border-border bg-card p-3">
      <span className={ok ? "text-sucesso" : "text-destructive"}>{ok ? "✓" : "✗"}</span>
      <div>
        <p className="font-medium">{titulo}</p>
        {!ok && <p className="text-xs text-muted-foreground">{ajuda}</p>}
      </div>
    </li>
  );
}

function Saude() {
  // O token vai junto para o servidor conferir NO BANCO se quem pediu é o dono
  // da conta. A chave do endereço (?chave=...) é a saída para o dia em que
  // ninguém consegue entrar — foi para isso que esta tela nasceu.
  const d = useQuery({
    queryKey: ["diagnostico"],
    queryFn: async () => {
      const { data: sessao } = await supabase.auth.getSession();
      const chave = new URLSearchParams(window.location.search).get("chave") ?? undefined;
      return diagnostico({ data: { token: sessao.session?.access_token, chave } });
    },
  });

  return (
    <main className="mx-auto flex min-h-screen max-w-xl flex-col gap-4 p-6">
      <Logo altura={36} />
      <h1 className="font-display text-2xl font-semibold">Saúde do sistema</h1>
      <p className="text-sm text-muted-foreground">
        Esta tela não mostra nenhum segredo: só diz o que está configurado e o que falta.
      </p>

      {/* A VERSÃO NO AR. Vem gravada dentro do próprio pacote, no build, então
          é impossível ela discordar do que está publicado: se esta página
          carregou, é esta a versão que está servindo. */}
      <div className="rounded-lg border border-border bg-card p-3">
        <p className="text-sm font-medium">Versão no ar</p>
        <p className="mt-1 font-mono text-xs break-words text-muted-foreground">{versaoEmTexto(VERSAO)}</p>
        <p className="mt-1 text-xs text-muted-foreground">
          Se este commit não for o último que você publicou, o que está no ar é uma versão antiga —
          publique de novo. Esta tela é a única que sabe disso: as outras linhas abaixo falam do
          <strong className="font-medium"> banco</strong>, não do aplicativo.
        </p>
      </div>

      {d.isLoading && <p className="text-sm text-muted-foreground">Conferindo…</p>}
      {d.isError && <p className="text-sm text-destructive">{(d.error as Error).message}</p>}

      {/* Sem login e sem a chave: só o estado geral. */}
      {d.data && !d.data.detalhe && (
        <div
          className={`rounded-lg border p-3 text-sm ${
            d.data.banco === "ok" ? "border-sucesso" : "border-destructive"
          } bg-card`}
        >
          <p className="font-medium">
            {d.data.banco === "ok"
              ? "No ar: o sistema está respondendo e o banco está atualizado."
              : d.data.banco === "desatualizado"
                ? "O banco não recebeu as atualizações desta versão."
                : "O servidor não está conseguindo falar com o banco."}
          </p>
          <p className="mt-1 text-xs text-muted-foreground">
            Entre como dono da conta para ver o detalhe. Se ninguém estiver conseguindo entrar,
            acrescente <span className="font-mono">?chave=…</span> ao endereço, com a chave
            cadastrada em STGAME_SAUDE_CHAVE.
          </p>
        </div>
      )}

      <SaudeDaConta />

      {d.data?.detalhe && (
        <>
          <ul className="space-y-2">
            <Linha
              ok={d.data.temChave}
              titulo="Chave de servidor do Supabase"
              ajuda="Cadastre STGAME_SERVICE_ROLE_KEY nos Secrets do Lovable."
            />
            <Linha
              ok={d.data.temPepper}
              titulo="Chave de segredos do app"
              ajuda="Cadastre STGAME_PIN_PEPPER nos Secrets do Lovable (pelo menos 16 caracteres)."
            />
            <Linha
              ok={d.data.temSite}
              titulo="Endereço do site"
              ajuda="Cadastre SITE_URL nos Secrets do Lovable, com o endereço do site (ex.: https://stgame.com.br), sem barra no fim."
            />
            <Linha
              ok={d.data.contaDeSenha}
              titulo="Conta de senha funciona nesta hospedagem"
              ajuda={
                d.data.erroDaConta
                  ? `A hospedagem recusou a conta de senha: ${d.data.erroDaConta}`
                  : "A conta de senha não funcionou. Sem ela, ninguém entra."
              }
            />
            <Linha
              ok={d.data.banco === "ok"}
              titulo="Banco de dados atualizado (nome e parâmetros de cada função)"
              ajuda={
                d.data.banco === "desatualizado"
                  ? "O banco não recebeu as atualizações desta versão. Aplique as migrações (supabase db push)."
                  : "O servidor não conseguiu falar com o banco. Confira a chave de servidor."
              }
            />
          </ul>

          {d.data.rotinas && <Rotinas r={d.data.rotinas} />}

          {d.data.assinaturas.length > 0 && (
            <div className="rounded-lg border border-destructive bg-card p-3">
              <p className="text-sm font-medium">Funções com parâmetros diferentes do que o app espera:</p>
              <p className="mt-1 text-xs text-muted-foreground">
                O nome existe, mas os parâmetros mudaram. Aplique as migrações desta versão.
              </p>
              <ul className="mt-2 space-y-1">
                {d.data.assinaturas.map((a) => (
                  <li key={a} className="break-words font-mono text-xs text-muted-foreground">
                    {a}
                  </li>
                ))}
              </ul>
            </div>
          )}

          {d.data.faltando.length > 0 && (
            <div className="rounded-lg border border-destructive bg-card p-3">
              <p className="text-sm font-medium">Faltando no banco:</p>
              <p className="mt-1 break-words font-mono text-xs text-muted-foreground">
                {d.data.faltando.join(", ")}
              </p>
            </div>
          )}

          {d.data.temChave && d.data.temPepper && d.data.temSite && d.data.contaDeSenha && d.data.banco === "ok" && (
            <p className="rounded-lg border border-sucesso bg-card p-3 text-sm">
              Tudo certo: o sistema está pronto para uso.
            </p>
          )}
        </>
      )}
    </main>
  );
}

/** Uma hora sem rodar já é sinal de agendamento parado (ele roda a cada 5 minutos). */
const PARADO_DEPOIS_DE_MS = 60 * 60 * 1000;

/**
 * O que as rotinas automáticas precisam para rodar (29/09/2026). Diz só SE
 * cada segredo existe, nunca o valor. Os números somados de todas as contas
 * (mensagens e fotos) só vêm para o admin geral ou com a chave.
 */
function Rotinas({ r }: { r: SaudeDasRotinas }) {
  const rotinas = r.jobs.find((j) => j.nome === "gamegb-rotinas");
  const fila = r.jobs.find((j) => j.nome === "stgame-telegram-fila");
  const rodouAgora = (j?: SaudeDasRotinas["jobs"][number]) =>
    !!j?.ultimaexecucao && Date.now() - Date.parse(j.ultimaexecucao) < PARADO_DEPOIS_DE_MS && j.ultimostatus !== "failed";
  const segredo = (nome: string) => r.segredos[nome] === true;
  return (
    <div className="space-y-2">
      <p className="text-sm font-medium">Rotinas automáticas</p>
      <ul className="space-y-2">
        <Linha
          ok={r.cofre && r.pgnet}
          titulo="Cofre de segredos e chamadas do banco (Vault e pg_net)"
          ajuda="Sem eles, nenhuma foto vencida é apagada e nenhuma mensagem sai. Ligue as extensões Vault e pg_net no Supabase."
        />
        <Linha
          ok={segredo("stgame_funcoes_url") && segredo("stgame_expurgo_segredo")}
          titulo="Segredos do apagamento de fotos no cofre"
          ajuda="Faltam stgame_funcoes_url e/ou stgame_expurgo_segredo no Vault. Sem eles, as fotos vencidas não são apagadas."
        />
        <Linha
          ok={r.agendador && !!rotinas?.existe && !!rotinas?.ativo && rodouAgora(rotinas)}
          titulo="Agendamento automático das rotinas (lista do dia, fechamento, fotos)"
          ajuda={
            !r.agendador
              ? "A extensão pg_cron não está ligada: nenhuma rotina roda sozinha."
              : !rotinas?.existe
                ? 'O agendamento "gamegb-rotinas" não existe. Aplique as migrações.'
                : !rotinas.ativo
                  ? 'O agendamento "gamegb-rotinas" está desligado.'
                  : `A última execução foi ${rotinas.ultimaexecucao ? dataHoraBr(rotinas.ultimaexecucao) : "nunca"}${rotinas.ultimostatus === "failed" ? ", com erro" : ""}: ele deveria rodar a cada 5 minutos.`
          }
        />
        <Linha
          ok={segredo("stgame_fila_segredo") && !!fila?.existe && !!fila?.ativo}
          titulo="Fila de mensagens do Telegram (só importa com o bot ligado)"
          ajuda="Falta o segredo stgame_fila_segredo no Vault ou o agendamento stgame-telegram-fila. Resolver antes de ligar o Telegram (Etapa 1.13)."
        />
        {r.mensagensfalhadas !== null && (
          <Linha
            ok={r.mensagensfalhadas === 0}
            titulo={`Mensagens que falharam nas últimas 24 horas: ${r.mensagensfalhadas}`}
            ajuda="Mensagens que o Telegram recusou até desistir. Todas as contas somadas."
          />
        )}
        {r.fotos && (
          <Linha
            ok={r.fotos.vencidas === 0 || r.fotos.diasdeatraso <= 2}
            titulo={`Fotos vencidas ainda guardadas: ${r.fotos.vencidas}`}
            ajuda={`A mais antiga passou do prazo há ${r.fotos.diasdeatraso} dia(s)${r.fotos.presas > 0 ? `; ${r.fotos.presas} com a remoção falhando` : ""}. A política de uso promete que elas são apagadas. Todas as contas somadas.`}
          />
        )}
      </ul>
    </div>
  );
}

/**
 * A saúde da conta de quem está logado: fotos vencidas ainda guardadas,
 * mensagens que falharam e rotinas que não acharam a tarefa (28/09/2026).
 * Cada conta só vê os dela.
 */
function SaudeDaConta() {
  const dados = useQuery({
    queryKey: ["saude-da-conta"],
    queryFn: async () => {
      const { data: sessao } = await supabase.auth.getSession();
      if (!sessao.session) return null;
      const [saude, avisos] = await Promise.all([
        supabase.rpc("saude_da_minha_conta"),
        supabase
          .from("avisossistema")
          .select("avisoid, texto, criadoem")
          .eq("tipo", "rotina_sem_tarefa")
          .order("criadoem", { ascending: false })
          .limit(20),
      ]);
      if (saude.error) throw saude.error;
      if (avisos.error) throw avisos.error;
      return {
        saude: saude.data as unknown as {
          fotos: { vencidas: number; diasdeatraso: number; presas: number };
          mensagensfalhadas: number;
        } | null,
        avisos: avisos.data ?? [],
      };
    },
  });
  if (!dados.data) return null;
  const { saude, avisos } = dados.data;
  return (
    <div className="space-y-2">
      <p className="text-sm font-medium">Esta conta</p>
      <ul className="space-y-2">
        {saude && (
          <>
            <Linha
              ok={saude.fotos.vencidas === 0 || saude.fotos.diasdeatraso <= 2}
              titulo={`Fotos vencidas ainda guardadas: ${saude.fotos.vencidas}`}
              ajuda={`A mais antiga passou do prazo há ${saude.fotos.diasdeatraso} dia(s)${saude.fotos.presas > 0 ? `; ${saude.fotos.presas} com a remoção falhando` : ""}. A política de uso promete que elas são apagadas: a rotina de apagar não está dando conta.`}
            />
            <Linha
              ok={saude.mensagensfalhadas === 0}
              titulo={`Mensagens do Telegram que falharam nas últimas 24 horas: ${saude.mensagensfalhadas}`}
              ajuda="O Telegram recusou essas mensagens até o sistema desistir."
            />
          </>
        )}
        <Linha
          ok={avisos.length === 0}
          titulo={avisos.length === 0 ? "Toda rotina achou a tarefa de que precisa" : "Rotinas que não acharam a tarefa"}
          ajuda=""
        />
      </ul>
      {avisos.length > 0 && (
        <ul className="space-y-2 rounded-lg border border-destructive bg-card p-3">
          {avisos.map((a) => (
            <li key={a.avisoid} className="text-xs">
              {a.texto} <span className="text-muted-foreground">({dataHoraBr(a.criadoem)})</span>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
