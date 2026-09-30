// Tela de saúde do sistema: diz o que está faltando para o app funcionar,
// sem mostrar o valor de segredo nenhum (só "configurado" ou "faltando").
//
// Existe porque uma publicação sem as atualizações do banco deixou todo mundo
// de fora — inclusive o administrador — com uma mensagem que não dizia o motivo.
import { createFileRoute } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { diagnostico, type SaudeDasRotinas, type SituacaoDosBuckets } from "@/servidor/acesso";
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

          <Buckets b={d.data.buckets} />

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

          {d.data.temChave && d.data.temPepper && d.data.temSite && d.data.contaDeSenha && d.data.banco === "ok" &&
            !d.data.buckets.erro && d.data.buckets.lista.every((b) => !b.publico && (b.existe || !b.esperado)) && (
            <p className="rounded-lg border border-sucesso bg-card p-3 text-sm">
              Tudo certo: o sistema está pronto para uso.
            </p>
          )}
        </>
      )}
    </main>
  );
}

/** "2026-09-27" → "27/09/2026" (o dia já vem do banco; nada de fuso aqui). */
const diaBr = (dia: string) => dia.split("-").reverse().join("/");

/**
 * Os buckets do Storage (01/10/2026): cada um tem de existir e ser PRIVADO.
 * Público = qualquer link que vazou uma vez abre para sempre, sem login.
 */
function Buckets({ b }: { b: SituacaoDosBuckets }) {
  return (
    <div className="space-y-2">
      <p className="text-sm font-medium">Arquivos guardados (buckets do Storage)</p>
      <ul className="space-y-2">
        {b.erro && <Linha ok={false} titulo="Não deu para conferir os buckets" ajuda={b.erro} />}
        {b.lista.map((x) => (
          <Linha
            key={x.id}
            ok={!x.publico && (x.existe || !x.esperado)}
            titulo={`${x.para} ("${x.id}"): ${!x.existe ? "FALTA" : x.publico ? "PÚBLICO" : "privado"}`}
            ajuda={
              x.publico
                ? `Qualquer pessoa com o link de um arquivo deste bucket abre sem login, para sempre. Corrija JÁ: Supabase → Storage → "${x.id}" → Edit bucket → desligue "Public bucket" → Save.`
                : `O bucket "${x.id}" não existe: o envio desses arquivos falha. Chame o Claude.`
            }
          />
        ))}
      </ul>
    </div>
  );
}

/** "há 3 horas", "há 2 dias" (a partir do instante que veio do banco). */
function ha(instante: string | null | undefined): string {
  if (!instante) return "nunca";
  const min = Math.max(0, Math.round((Date.now() - Date.parse(instante)) / 60000));
  if (min < 60) return `há ${min} min`;
  const h = Math.round(min / 60);
  if (h < 48) return `há ${h} h`;
  return `há ${Math.round(h / 24)} dias`;
}

const NOME_DO_AGENDAMENTO: Record<string, string> = {
  "gamegb-rotinas": "Rotinas do sistema (lista do dia, fechamento, fotos), a cada 5 minutos",
  "stgame-codigos-vencidos": "Limpeza dos códigos de acesso vencidos, a cada 5 minutos",
  "stgame-telegram-fila": "Fila de mensagens do Telegram, a cada 15 segundos (só importa com o bot ligado)",
};
const NOME_DA_ROTINA: Record<string, string> = {
  lista_do_dia: "Lista de tarefas do dia",
  foto_da_fila: "Foto da fila do dia (o que o Quadro mostra dos dias passados)",
  conferencia_livro: "Conferência do saldo de pontos",
  limpeza: "Limpeza dos registros antigos",
  expurgo_fotos: "Fotos vencidas: pôr na fila de apagamento",
};

/** O que a resposta da função que apaga as fotos quer dizer. */
function respostaDoApagamento(c: NonNullable<NonNullable<SaudeDasRotinas["apagamento"]>["ultimachamada"]>): string {
  if (!c.chamou) return c.erro ?? "não chamou";
  if (!c.respondidaem) return "chamada feita, esperando a resposta";
  if (c.status === 200) return `respondeu OK: apagou ${c.apagados ?? 0} arquivo(s)`;
  if (c.status === 401) return "respondeu 401: a senha do cofre (stgame_expurgo_segredo) e a da função (STGAME_EXPURGO_SEGREDO) não são iguais";
  if (c.status === 404) return "respondeu 404: a função expurgo-fotos não está publicada no Supabase";
  if (c.status) return `respondeu ${c.status}: ${c.erro ?? "erro"}`;
  return c.erro ?? "sem resposta";
}

/**
 * O que as rotinas automáticas precisam para rodar, e se elas RODARAM e
 * FUNCIONARAM (29 e 30/09/2026). Diz só SE cada segredo existe, nunca o valor.
 * Os números somados de todas as contas (fila, Storage) só vêm para o admin
 * geral ou com a chave.
 */
function Rotinas({ r }: { r: SaudeDasRotinas }) {
  const segredo = (nome: string) => r.segredos[nome] === true;
  const ap = r.apagamento;
  const st = r.storage;
  // Parada = tem o que apagar, a mais antiga espera há mais de 1 dia e nada
  // saiu nas últimas 24 horas.
  const filaParada =
    !!ap && ap.nafila + ap.presas > 0 && ap.apagadas24h === 0 && !!ap.maisantiga &&
    Date.now() - Date.parse(ap.maisantiga) > 24 * 60 * 60 * 1000;
  return (
    <div className="space-y-2">
      <p className="text-sm font-medium">Rotinas automáticas</p>
      <ul className="space-y-2">
        <Linha
          ok={r.cofre && r.pgnet}
          titulo="Cofre de segredos e chamadas do banco (Vault e pg_net)"
          ajuda="Sem eles, nenhuma foto vencida é apagada e nenhuma mensagem sai. Ligue as extensões Vault e pg_net no Supabase."
        />
        {["stgame_funcoes_url", "stgame_expurgo_segredo"].map((nome) => (
          <Linha
            key={nome}
            ok={segredo(nome)}
            titulo={`Segredo ${nome} no cofre: ${segredo(nome) ? "existe" : "FALTA"}`}
            ajuda="Sem ele, as fotos vencidas não são apagadas. O passo a passo está em docs/SEGREDOS.md."
          />
        ))}
        {!r.agendador && (
          <Linha ok={false} titulo="Agendador (pg_cron)" ajuda="A extensão pg_cron não está ligada: nenhuma rotina roda sozinha." />
        )}
        {r.jobs.map((j) => {
          const telegram = j.nome === "stgame-telegram-fila";
          const ok = j.existe && j.ativo && j.comandocerto !== false && !j.atrasado && j.ultimostatus !== "failed";
          return (
            <Linha
              key={j.nome}
              ok={ok || (telegram && !segredo("stgame_fila_segredo"))}
              titulo={`${NOME_DO_AGENDAMENTO[j.nome] ?? j.nome}: ${
                !j.existe ? "NÃO EXISTE" : !j.ativo ? "DESLIGADO" : `rodou ${ha(j.ultimaexecucao)}${j.atrasado ? " — ATRASADO" : ""}`
              }`}
              ajuda={
                !j.existe
                  ? `O agendamento "${j.nome}" não existe. Aplique as migrações.`
                  : !j.ativo
                    ? `O agendamento "${j.nome}" está desligado.`
                    : j.comandocerto === false
                      ? `O agendamento "${j.nome}" roda um comando diferente do que o sistema espera.`
                      : `Última execução: ${j.ultimaexecucao ? dataHoraBr(j.ultimaexecucao) : "nunca"}${j.ultimostatus === "failed" ? ", com erro" : ""}.`
              }
            />
          );
        })}
        {r.mensagensfalhadas !== null && (
          <Linha
            ok={r.mensagensfalhadas === 0}
            titulo={`Mensagens que falharam nas últimas 24 horas: ${r.mensagensfalhadas}`}
            ajuda="Mensagens que o Telegram recusou até desistir. Todas as contas somadas."
          />
        )}
        {r.fila && (
          <Linha
            ok={r.fila.dias === 0}
            titulo={`Dias sem foto da fila (últimos 30): ${r.fila.dias}`}
            ajuda={`A rotina da madrugada não tirou a foto da fila desses dias até as 03:00${r.fila.ultimo ? ` (o mais recente: ${diaBr(r.fila.ultimo)})` : ""}. No Quadro, eles aparecem como "não registrado". ${r.fila.contas} conta(s) afetada(s).`}
          />
        )}
        {(r.diarias ?? []).map((d) => (
          <Linha
            key={d.rotina}
            ok={d.atrasadas === 0 && d.comerro === 0}
            titulo={`${NOME_DA_ROTINA[d.rotina] ?? d.rotina}: rodou ${ha(d.ultima)}${
              d.atrasadas > 0 ? ` — ATRASADA em ${d.atrasadas} de ${d.contas} conta(s)` : ""
            }${d.comerro > 0 ? ` — COM ERRO em ${d.comerro} conta(s)` : ""}`}
            ajuda="Roda uma vez por dia, depois das 03:00, em cada conta. Atrasada = mais de 30 horas sem rodar."
          />
        ))}
      </ul>

      {ap && (
        <>
          <p className="pt-2 text-sm font-medium">Apagamento das fotos vencidas</p>
          <ul className="space-y-2">
            {r.fotos && (
              <Linha
                ok={r.fotos.vencidas === 0 || r.fotos.diasdeatraso <= 2}
                titulo={`Fotos vencidas que o sistema ainda não deu como apagadas: ${r.fotos.vencidas}`}
                ajuda={`A mais antiga passou do prazo há ${r.fotos.diasdeatraso} dia(s)${r.fotos.presas > 0 ? `; ${r.fotos.presas} com a remoção falhando` : ""}. Todas as contas somadas.`}
              />
            )}
            <Linha
              ok={!filaParada && ap.presas === 0}
              titulo={
                ap.nafila + ap.presas === 0
                  ? "Fila de apagamento: vazia"
                  : `Fila de apagamento: ${ap.nafila} esperando${ap.presas > 0 ? `, ${ap.presas} presas` : ""} — a mais antiga ${ha(ap.maisantiga)}${filaParada ? " — PARADA" : ""}`
              }
              ajuda={`Apagadas nas últimas 24 horas: ${ap.apagadas24h}; nos últimos 7 dias: ${ap.apagadas7d}. "Presas" = a remoção falhou 5 vezes e o sistema desistiu delas. Parada = nada saiu em 24 horas.`}
            />
            <Linha
              ok={!!ap.ultimachamada && ap.ultimachamada.status === 200}
              titulo={
                ap.ultimachamada
                  ? `Última chamada à função que apaga: ${dataHoraBr(ap.ultimachamada.pedidaem)} — ${respostaDoApagamento(ap.ultimachamada)}`
                  : "A função que apaga ainda não foi chamada"
              }
              ajuda={`Última vez que funcionou: ${ap.ultimosucesso ? dataHoraBr(ap.ultimosucesso) : "nunca"}.`}
            />
          </ul>
        </>
      )}

      {st && (
        <>
          <p className="pt-2 text-sm font-medium">Contado no próprio Storage (onde as fotos ficam)</p>
          <ul className="space-y-2">
            <Linha
              ok={st.vencidos === 0}
              titulo={`Fotos vencidas ainda guardadas no Storage: ${st.vencidos}`}
              ajuda={`A mais antiga foi enviada em ${st.vencidomaisantigo ? dataHoraBr(st.vencidomaisantigo) : "—"}. Esta conta é feita no Storage, não no que o sistema acha que apagou. A política de uso promete que elas são apagadas.`}
            />
            <Linha
              ok={st.apagadosquecontinuam === 0}
              titulo={`Dadas como apagadas, mas ainda no Storage: ${st.apagadosquecontinuam}`}
              ajuda="O sistema registrou que apagou e o arquivo continua lá. Tem de ser zero: chame o Claude."
            />
            {r.amostra && (
              <Linha
                ok={r.amostra.encontradas === 0 && !r.amostra.erro}
                titulo={`Conferência uma a uma: ${r.amostra.conferidas} das últimas apagadas procuradas no Storage — ${r.amostra.encontradas} encontradas`}
                ajuda={r.amostra.erro ? `O Storage respondeu com erro: ${r.amostra.erro}` : "Tem de ser zero encontradas: o arquivo apagado não pode mais existir."}
              />
            )}
            <Linha
              ok={st.semdono === 0}
              titulo={`Arquivos no Storage que nenhuma entrega usa: ${st.semdono}`}
              ajuda={`Nunca serão apagados pela rotina (o mais antigo é de ${st.semdonomaisantigo ? dataHoraBr(st.semdonomaisantigo) : "—"}). Em geral, foto enviada de uma entrega que não chegou a ser registrada.`}
            />
          </ul>
        </>
      )}
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
          fila: { dias: number; ultimo: string | null };
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
            <Linha
              ok={saude.fila.dias === 0}
              titulo={`Dias sem foto da fila (últimos 30): ${saude.fila.dias}`}
              ajuda={`A rotina da madrugada não tirou a foto da fila desses dias até as 03:00${saude.fila.ultimo ? ` (o mais recente: ${diaBr(saude.fila.ultimo)})` : ""}. No Quadro, "para pegar" desses dias aparece como "não registrado".`}
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
