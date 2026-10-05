// Os ✗ da PLATAFORMA, em português, numa lista só (01/10/2026). É o que a faixa
// vermelha do /admin mostra. A /saude explica cada um em detalhe.
//
// CURATIVO: a faixa só aparece para quem abre o /admin. Alarme que depende de
// alguém abrir a tela ainda depende de alguém abrir a tela. O alarme de verdade
// não existe: o Telegram saiu em 04/10/2026, e a faixa e a /saude só falam a
// quem abre a tela.
import type { SaudeDasRotinas, SituacaoDosBuckets } from "@/servidor/acesso";

export type DiagnosticoDaPlataforma = {
  temChave: boolean;
  temPepper: boolean;
  temSite: boolean;
  contaDeSenha: boolean;
  banco: "ok" | "desatualizado" | "sem resposta";
  rotinas: SaudeDasRotinas | null;
  buckets: SituacaoDosBuckets;
};

const DIA_MS = 24 * 60 * 60 * 1000;

export function problemasDaPlataforma(d: DiagnosticoDaPlataforma, agora = Date.now()): string[] {
  const p: string[] = [];
  // Os buckets primeiro: bucket público deixa as fotos abertas a quem tiver o link.
  for (const b of d.buckets.lista) {
    if (b.publico) p.push(`O bucket "${b.id}" (${b.para}) está PÚBLICO: qualquer link dele abre sem login.`);
    else if (b.esperado && !b.existe) p.push(`O bucket "${b.id}" (${b.para}) não existe.`);
  }
  if (d.buckets.erro) p.push(`Não deu para conferir os buckets: ${d.buckets.erro}`);
  if (!d.temChave) p.push("Falta a chave de servidor (STGAME_SERVICE_ROLE_KEY).");
  if (!d.temPepper) p.push("Falta a chave de segredos do app (STGAME_PIN_PEPPER).");
  if (!d.temSite) p.push("Falta o endereço do site (SITE_URL).");
  if (!d.contaDeSenha) p.push("A conta de senha não funciona nesta hospedagem: ninguém entra.");
  if (d.banco !== "ok") p.push(d.banco === "desatualizado" ? "O banco não recebeu as atualizações desta versão." : "O servidor não fala com o banco.");
  const r = d.rotinas;
  if (!r) return p;
  if (!r.cofre || !r.pgnet) p.push("O cofre (Vault) ou o pg_net não está ligado.");
  for (const nome of ["stgame_funcoes_url", "stgame_expurgo_segredo"])
    if (r.segredos[nome] !== true) p.push(`Falta o segredo ${nome} no cofre.`);
  if (!r.agendador) p.push("O agendador (pg_cron) não está ligado: nenhuma rotina roda sozinha.");
  for (const j of r.jobs) {
    if (!j.existe) p.push(`O agendamento "${j.nome}" não existe.`);
    else if (!j.ativo) p.push(`O agendamento "${j.nome}" está desligado.`);
    else if (j.comandocerto === false) p.push(`O agendamento "${j.nome}" roda um comando diferente do esperado.`);
    else if (j.atrasado || j.ultimostatus === "failed") p.push(`O agendamento "${j.nome}" está atrasado ou falhando.`);
  }
  for (const d2 of r.diarias ?? []) {
    if (d2.atrasadas > 0) p.push(`A rotina "${d2.rotina}" está atrasada em ${d2.atrasadas} conta(s).`);
    if (d2.comerro > 0) p.push(`A rotina "${d2.rotina}" deu erro em ${d2.comerro} conta(s).`);
  }
  const ap = r.apagamento;
  if (ap) {
    const parada =
      ap.nafila + ap.presas > 0 && ap.apagadas24h === 0 && !!ap.maisantiga && agora - Date.parse(ap.maisantiga) > DIA_MS;
    if (parada) p.push("A fila de apagamento das fotos está PARADA (nada saiu em 24 horas).");
    if (ap.presas > 0) p.push(`${ap.presas} foto(s) com a remoção falhando 5 vezes.`);
    if (ap.ultimachamada && ap.ultimachamada.status !== 200 && ap.ultimachamada.respondidaem)
      p.push(`A última chamada à função que apaga as fotos não deu certo (${ap.ultimachamada.status ?? ap.ultimachamada.erro ?? "sem resposta"}).`);
  }
  const st = r.storage;
  if (st && st.apagadosquecontinuam > 0)
    p.push(`${st.apagadosquecontinuam} foto(s) dadas como apagadas continuam no Storage.`);
  return p;
}
