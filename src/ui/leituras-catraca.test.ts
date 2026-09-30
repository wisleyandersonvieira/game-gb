// Trava da parte 4 e da chave da parte 5 (30/09/2026).
//
// 1. "Faltam 0 tabelas": nenhuma tela de gestão lê tabela direto (o gerente
//    não lê tabela nenhuma; a tela vinha vazia). Só os arquivos das telas do
//    MASTER (lista fechada abaixo) podem.
// 2. "Faltam 0 leituras": toda função que uma tela de gestão chama está na
//    lista testada para o gerente (seção 108 do teste de isolamento: três
//    lojas, três gestores, as duas metades) OU na lista fechada abaixo de quem
//    NÃO é leitura do gerente (escritas, que a seção 91 confere; leituras só
//    do master; ajudantes). Função nova numa tela, fora das duas: reprova.
// 3. O botão "Criar usuário gerencial" só existe com TODAS as pendências
//    vazias: as de gravação (seção 91), as de tela do gerente (teste de tempo)
//    e as deste arquivo. É a última chave.
import { describe, expect, it } from "bun:test";
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";

const RAIZ = join(import.meta.dir, "..", "..");
const ler = (f: string) => readFileSync(join(RAIZ, f), "utf8");

function arquivos(pasta: string): string[] {
  const saida: string[] = [];
  for (const nome of readdirSync(join(RAIZ, pasta))) {
    const caminho = `${pasta}/${nome}`;
    if (statSync(join(RAIZ, caminho)).isDirectory()) saida.push(...arquivos(caminho));
    else if (/\.tsx?$/.test(nome) && !nome.endsWith(".test.ts")) saida.push(caminho);
  }
  return saida;
}

// Fora da gestão: o app do colaborador, o tablet, a TV, o admin geral, o servidor.
const FORA = ["src/routes/eu", "src/routes/tablet", "src/routes/admin", "src/routes/tv", "src/colaborador", "src/servidor",
  "src/routes/saude", "src/routes/primeiro-acesso", "src/routes/definir-senha", "src/routes/e.$codigo", "src/routes/auth",
  "src/admin", "src/integrations"];
// Telas SÓ do master (o gerente nem entra; o banco também recusa).
const SO_MASTER = ["src/routes/_authenticated/canal-confidencial.tsx", "src/routes/_authenticated/documentos-pessoais.tsx",
  "src/routes/_authenticated/configuracoes.tsx", "src/routes/_authenticated/estornos.tsx", "src/routes/medir.tsx",
  "src/configuracoes/", "src/telegram/"];
// Onde ainda há leitura de tabela, e por quê (só o master).
const TABELA_PERMITIDA: Record<string, string[]> = {
  // O documento pessoal ligado a uma etapa: o seletor só aparece para o master.
  "src/routes/_authenticated/onboarding.tsx": ["documentospessoais"],
};
// Chamadas que NÃO são leitura do gerente.
const NAO_LEITURA = new Set([
  // Escritas: a seção 91 confere que cada uma chama pode() ou é só do master.
  "abrir_solicitacao", "alterar_hora_da_atribuicao", "alterar_pagamento_agendamento", "anular_feedback", "apagar_jornada",
  "apagar_meta_especial", "aprovar_entrega", "arquivar_comunicado", "ativar_conquista", "ativar_loja", "ativar_premio",
  "ativar_tarefa", "ativar_tipo_evento", "atribuir_tarefa", "cancelar_agendamento", "cancelar_troca", "concluir_troca",
  "criar_agendamento", "criar_conquista", "criar_convite_telegram", "criar_link_tv", "criar_loja", "criar_meta_especial",
  "decidir_justificativa", "desfazer_ciencia", "editar_agendamento", "editar_comunicado", "editar_conquista", "editar_loja",
  "encerrar_atribuicoes", "estornar_entrega", "estornar_troca", "incluir_destinatarios", "iniciar_onboarding",
  "lancar_venda_do_dia", "liberar_pin", "marcar_agendamento_realizado", "marcar_etapa_onboarding", "mudar_situacao_solicitacao",
  "parear_tv", "passar_tarefa_de_folga", "publicar_comunicado", "reabrir_agendamento", "recriar_tarefa_do_agendamento",
  "recusar_entrega", "refazer_fechamento", "registrar_anexo_agendamento", "registrar_ciencia", "registrar_entrega",
  "registrar_feedback", "registrar_justificativa", "registrar_troca", "registrar_troca_por_valor", "remarcar_agendamento",
  "remover_anexo_agendamento", "revogar_aceite", "revogar_link_tv", "salvar_etapa_onboarding", "salvar_intervalo_do_mapa",
  "salvar_jornada", "salvar_meta_do_mes", "salvar_metas_da_semana", "salvar_pessoa", "salvar_premio", "salvar_som_da_loja",
  "salvar_tarefa", "salvar_tipo_evento", "salvar_tv_da_loja", "trocar_responsavel_agendamento", "vincular_jornada",
  // Leitura só do master (decisão 5: a conferência das vendas é dele).
  "historico_das_vendas",
  // Ajudantes: quem sou, que dia é hoje, a prévia da TV (a mesma do visitante).
  "meu_hoje", "minha_conta", "sou_master", "painel_da_tv",
]);

const iso = ler("supabase/tests/isolamento.sql");
function listaTestada(): Set<string> {
  const i = iso.indexOf("toda leitura do gerente esta na lista testada");
  const j = iso.lastIndexOf("AND p.proname NOT IN (", i);
  return new Set([...iso.slice(j, iso.indexOf(");", j)).matchAll(/'([a-z_]+)'/g)].map((m) => m[1]));
}

const telas = [...arquivos("src/routes"), ...arquivos("src/ui"), ...arquivos("src/lojas"), ...arquivos("src/ranking"),
  ...arquivos("src/jornada"), ...arquivos("src/painel"), ...arquivos("src/rh"), ...arquivos("src/configuracoes"),
  ...arquivos("src/telegram")].filter((f) => !FORA.some((x) => f.startsWith(x)));
const doMaster = (f: string) => SO_MASTER.some((x) => f.startsWith(x));

function tabelasFora(): string[] {
  const sobra: string[] = [];
  for (const f of telas) {
    if (doMaster(f)) continue;
    for (const m of ler(f).matchAll(/(?<!storage)\.from\("([a-z_]+)"\)/g)) {
      if (/storage\s*$/.test(ler(f).slice(Math.max(0, m.index! - 40), m.index!))) continue;
      if ((TABELA_PERMITIDA[f] ?? []).includes(m[1])) continue;
      sobra.push(`${f}: ${m[1]}`);
    }
  }
  return sobra;
}

function leiturasFora(): string[] {
  const testada = listaTestada();
  const sobra = new Set<string>();
  for (const f of telas) {
    if (doMaster(f)) continue;
    for (const m of ler(f).matchAll(/rpc\("([a-z_]+)"/g)) {
      if (!testada.has(m[1]) && !NAO_LEITURA.has(m[1])) sobra.add(`${f}: ${m[1]}`);
    }
  }
  return [...sobra];
}

function pendenciasDeGravacao(): string[] {
  return [...iso.matchAll(/SELECT unnest\(ARRAY\[([^\]]*)\](?:::text\[\])?\), 'pendente_parte2'/g)]
    .map((m) => m[1].trim()).filter((x) => x !== "");
}
function telasPendentesDoGerente(): string {
  const m = ler("supabase/tests/volume_medir.sql").match(/pendentes constant text\[\] := ARRAY\[([^\]]*)\]/);
  return (m?.[1] ?? "?").trim();
}

describe("parte 4: as telas de gestão leem pelo banco", () => {
  it("faltam 0 tabelas: nenhuma tela de gestão lê tabela direto (fora as do master)", () => {
    expect(tabelasFora()).toEqual([]);
  });
  it("faltam 0 leituras: toda função chamada pelas telas está testada para o gerente ou é declarada", () => {
    expect(leiturasFora()).toEqual([]);
  });
  it("a trava olha o lugar certo (acha as telas, as chamadas e a lista testada)", () => {
    expect(telas.length).toBeGreaterThan(30);
    expect(listaTestada().has("pessoas_para")).toBe(true);
  });
});

