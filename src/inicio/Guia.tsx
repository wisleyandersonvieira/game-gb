// Guia de primeiros passos: aparece enquanto falta algo básico na conta.
import { Link } from "@tanstack/react-router";
import { CircleCheck, Circle, X } from "lucide-react";
import type { PainelInicio } from "./tipos";

const PASSOS: { chave: keyof PainelInicio["guia"]; texto: string; ajuda: string; para: string }[] = [
  { chave: "loja", texto: "Cadastrar a loja", ajuda: "Nome e cidade de cada loja.", para: "/gestao" },
  { chave: "equipe", texto: "Cadastrar a equipe", ajuda: "Quem trabalha e em qual loja.", para: "/funcionarios" },
  { chave: "tarefas", texto: "Criar e atribuir tarefas", ajuda: "O que cada pessoa faz e quantos pontos vale.", para: "/tarefas" },
  { chave: "meta", texto: "Definir a meta de vendas", ajuda: "Meta por dia da semana e do mês.", para: "/metas" },
  { chave: "tv", texto: "Criar o link da TV", ajuda: "O painel da loja na TV, sem login.", para: "/gestao" },
];

export function Guia({ guia, aoFechar }: { guia: PainelInicio["guia"]; aoFechar?: () => void }) {
  const feitos = PASSOS.filter((p) => guia[p.chave]).length;
  return (
    <section className="rounded-xl border border-primary/40 bg-primary/5 p-4 sm:p-5">
      <div className="flex items-start justify-between gap-3">
        <div>
          <h2 className="font-semibold">Primeiros passos</h2>
          <p className="text-sm text-muted-foreground">
            {feitos} de {PASSOS.length} feitos. Com isso pronto, esta tela se enche de números.
          </p>
        </div>
        {aoFechar && (
          <button
            onClick={aoFechar}
            className="inline-flex h-10 w-10 shrink-0 items-center justify-center rounded-lg text-muted-foreground hover:bg-muted"
            aria-label="Fechar o guia"
            title="Fechar o guia"
          >
            <X className="h-5 w-5" />
          </button>
        )}
      </div>
      <ol className="mt-3 grid gap-2 sm:grid-cols-2 lg:grid-cols-5">
        {PASSOS.map((p, i) => {
          const ok = guia[p.chave];
          return (
            <li key={p.chave}>
              <Link
                to={p.para}
                className={`flex h-full items-start gap-2 rounded-lg border bg-card p-3 text-sm transition hover:border-primary ${
                  ok ? "border-sucesso/50" : "border-border"
                }`}
              >
                {ok ? (
                  <CircleCheck className="mt-0.5 h-5 w-5 shrink-0 text-sucesso" aria-label="feito" />
                ) : (
                  <Circle className="mt-0.5 h-5 w-5 shrink-0 text-muted-foreground" aria-label="a fazer" />
                )}
                <span>
                  <span className={`block font-medium ${ok ? "text-muted-foreground line-through" : ""}`}>
                    {i + 1}. {p.texto}
                  </span>
                  <span className="block text-xs text-muted-foreground">{p.ajuda}</span>
                </span>
              </Link>
            </li>
          );
        })}
      </ol>
    </section>
  );
}

export const guiaCompleto = (g: PainelInicio["guia"]) => PASSOS.every((p) => g[p.chave]);
