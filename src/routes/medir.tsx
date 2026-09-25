// Tela de medição (24/09/2026). Não muda nada no sistema: só mostra o que foi
// cronometrado enquanto você navegava.
//
// Como usar: entre normalmente, abra as telas que quiser medir (Início, Quadro,
// Equipe, Tarefas, Metas, Agenda, Ranking, Extrato, Relatórios) e só então
// abra /medir. A tabela mostra o que cada tela esperou.
import { createFileRoute, redirect } from "@tanstack/react-router";
import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { meuAcesso } from "@/integrations/supabase/destino";
import {
  chamadas, ligarMedicao, limparMedicao, medicaoLigada, resumir, type ResumoDaTela,
} from "@/medicao/registro";

export const Route = createFileRoute("/medir")({
  ssr: false,
  head: () => ({ meta: [{ name: "robots", content: "noindex, nofollow" }] }),
  // Só o dono da conta. Os nomes das nossas consultas não são assunto de quem
  // não entrou (pedido do Wisley, 25/09/2026).
  beforeLoad: async () => {
    const acesso = await meuAcesso();
    if (acesso.tipo !== "master" && acesso.tipo !== "gerente" && acesso.tipo !== "admin") {
      throw redirect({ to: acesso.tipo === "semlogin" ? "/auth" : "/sem-acesso" });
    }
  },
  component: Medir,
});

const NOMES: Record<string, string> = {
  "/inicio": "Início",
  "/painel": "Quadro",
  "/funcionarios": "Equipe",
  "/tarefas": "Tarefas",
  "/metas": "Metas",
  "/agenda": "Agenda",
  "/ranking": "Ranking",
  "/extrato": "Extrato",
  "/relatorios": "Relatórios",
  "/operacional": "Painel da loja",
  "/gestao": "Lojas e links da TV",
  "/medir": "(esta tela)",
};

/** Peso do código de cada tela, medido no build. Não depende da conexão. */
const PESO: Record<string, string> = {
  "/inicio": "396 KB (leva a biblioteca de gráficos)",
  "/painel": "28 KB",
  "/funcionarios": "24 KB",
  "/tarefas": "28 KB",
  "/metas": "20 KB",
  "/agenda": "28 KB",
  "/ranking": "20 KB",
  "/extrato": "12 KB",
  "/relatorios": "20 KB",
};

function Medir() {
  const [resumo, setResumo] = useState<ResumoDaTela[]>([]);
  const [idaEVolta, setIdaEVolta] = useState<number[] | null>(null);
  const [medindo, setMedindo] = useState(false);
  const [ligada, setLigada] = useState(medicaoLigada());

  /** Ida e volta até o Supabase: a mesma chamada, 7 vezes. */
  async function medirIdaEVolta() {
    setMedindo(true);
    const tempos: number[] = [];
    for (let i = 0; i < 7; i++) {
      const t = performance.now();
      await supabase.rpc("minha_conta");
      tempos.push(Math.round(performance.now() - t));
    }
    setIdaEVolta(tempos.sort((a, b) => a - b));
    setMedindo(false);
  }

  const mediana = idaEVolta ? idaEVolta[Math.floor(idaEVolta.length / 2)] : null;
  const ordenado = [...resumo].sort((a, b) => b.parede - a.parede);

  return (
    <main className="mx-auto max-w-4xl space-y-5 p-6">
      <div>
        <h1 className="font-display text-2xl font-semibold">Medição de desempenho</h1>
        <p className="text-sm text-muted-foreground">
          Abra as telas que quiser medir e volte aqui. Os números são desta aba e somem ao
          recarregar. Nada é enviado para lugar nenhum.
        </p>
      </div>

      <section className="space-y-2 rounded-xl border-2 border-primary bg-card p-4">
        <h2 className="font-semibold">A medição está {ligada ? "LIGADA" : "desligada"}</h2>
        <p className="text-xs text-muted-foreground">
          Desligada por padrão, para não pesar no uso normal. Ligue, navegue pelas telas que quer
          medir e volte aqui. Vale só neste aparelho e neste navegador.
        </p>
        <button
          onClick={() => { ligarMedicao(!ligada); setLigada(!ligada); setResumo([]); }}
          className="rounded-lg bg-primary px-4 py-2 text-sm font-medium text-primary-foreground"
        >
          {ligada ? "Desligar medição" : "Ligar medição"}
        </button>
      </section>

      <section className="space-y-2 rounded-xl border border-border bg-card p-4">
        <h2 className="font-semibold">1. Ida e volta até o banco</h2>
        <p className="text-xs text-muted-foreground">
          Quanto custa UMA pergunta ao Supabase, daqui. É o número que multiplica tudo: uma tela que
          faz 6 perguntas em sequência espera 6 vezes isso.
        </p>
        <button
          onClick={medirIdaEVolta}
          disabled={medindo}
          className="rounded-lg bg-primary px-4 py-2 text-sm font-medium text-primary-foreground disabled:opacity-40"
        >
          {medindo ? "Medindo..." : "Medir ida e volta"}
        </button>
        {idaEVolta && (
          <p className="text-sm">
            Mediana: <strong className="font-mono text-lg">{mediana} ms</strong>{" "}
            <span className="text-muted-foreground">
              (7 medidas: {idaEVolta.join(", ")} ms)
            </span>
          </p>
        )}
      </section>

      <section className="space-y-2 rounded-xl border border-border bg-card p-4">
        <h2 className="font-semibold">2. O que cada tela esperou</h2>
        <div className="flex flex-wrap gap-2">
          <button
            onClick={() => setResumo(resumir())}
            className="rounded-lg bg-primary px-4 py-2 text-sm font-medium text-primary-foreground"
          >
            Ver a medição ({chamadas.length} chamadas gravadas)
          </button>
          <button
            onClick={() => { limparMedicao(); setResumo([]); }}
            className="rounded-lg border border-border px-4 py-2 text-sm"
          >
            Zerar e começar de novo
          </button>
        </div>

        {ordenado.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            Nada gravado ainda. Navegue pelas telas e volte aqui.
          </p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-left text-sm">
              <thead className="text-xs text-muted-foreground">
                <tr>
                  <th className="py-1 pr-3">Tela</th>
                  <th className="py-1 pr-3">Esperou</th>
                  <th className="py-1 pr-3">Chamadas</th>
                  <th className="py-1 pr-3">Em sequência</th>
                  <th className="py-1 pr-3">A mais lenta</th>
                  <th className="py-1">Código</th>
                </tr>
              </thead>
              <tbody>
                {ordenado.map((r) => (
                  <tr key={r.tela} className="border-t border-border">
                    <td className="py-1 pr-3 font-medium">{NOMES[r.tela] ?? r.tela}</td>
                    <td className="py-1 pr-3 font-mono">{r.parede} ms</td>
                    <td className="py-1 pr-3">
                      {r.chamadas}
                      <span className="text-xs text-muted-foreground">
                        {" "}({r.porTipo.login > 0 && `${r.porTipo.login} login, `}
                        {r.porTipo.banco} banco
                        {r.porTipo.servidor > 0 && `, ${r.porTipo.servidor} servidor`})
                      </span>
                    </td>
                    <td className={`py-1 pr-3 ${r.emCascata > 1 ? "text-destructive" : ""}`}>
                      {r.emCascata} de {Math.max(r.chamadas - 1, 0)}
                    </td>
                    <td className="py-1 pr-3 font-mono text-xs">
                      {r.maisLenta?.nome} ({r.maisLenta?.ms} ms)
                    </td>
                    <td className="py-1 text-xs text-muted-foreground">{PESO[r.tela] ?? "—"}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        <p className="text-xs text-muted-foreground">
          <strong>Esperou</strong> é da primeira chamada até a última: o tempo real de espera.{" "}
          <strong>Em sequência</strong> é quantas só começaram depois que a anterior acabou — cada
          uma dessas custa uma ida e volta inteira. Quanto mais perto de zero, melhor.
        </p>
      </section>

      <section className="space-y-2 rounded-xl border border-border bg-card p-4">
        <h2 className="font-semibold">3. Chamada por chamada</h2>
        <div className="max-h-96 overflow-y-auto">
          <table className="w-full text-left text-xs">
            <thead className="text-muted-foreground">
              <tr>
                <th className="py-1 pr-2">Tela</th>
                <th className="py-1 pr-2">Tipo</th>
                <th className="py-1 pr-2">Nome</th>
                <th className="py-1 pr-2">Começou</th>
                <th className="py-1">Durou</th>
              </tr>
            </thead>
            <tbody>
              {chamadas.map((c, i) => (
                <tr key={i} className="border-t border-border">
                  <td className="py-1 pr-2">{NOMES[c.tela] ?? c.tela}</td>
                  <td className="py-1 pr-2">{c.tipo}</td>
                  <td className="py-1 pr-2 font-mono">{c.nome.slice(0, 40)}</td>
                  <td className="py-1 pr-2 font-mono">{Math.round(c.inicio)} ms</td>
                  <td className="py-1 font-mono">{Math.round(c.fim - c.inicio)} ms</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>
    </main>
  );
}
