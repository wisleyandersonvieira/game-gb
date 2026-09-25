// "Versão nova disponível": a faixa que aparece quando o site já foi
// publicado de novo mas esta aba ainda está rodando a versão antiga.
//
// Por que existe: em 25/09/2026 uma versão nova foi para o ar e ninguém tinha
// como saber, nem de dentro do app nem pelo /saude, que só falava do banco.
//
// Como funciona: o pacote sabe de que versão ELE é (gravado no build). O
// arquivo /versao.json fica solto ao lado do app e é sempre o da versão
// publicada agora. Quando os dois discordam, apareceu versão nova.
//
// NUNCA recarrega sozinho: alguém pode estar no meio de uma entrega. A faixa
// só oferece o botão.
import { useEffect, useState } from "react";
import { VERSAO, type Versao } from "./versao";

/** De quanto em quanto tempo perguntar. Também pergunta ao voltar para a aba. */
const INTERVALO = 10 * 60_000;

async function versaoPublicada(): Promise<Versao | null> {
  try {
    // no-store E um número no endereço: sem isso, o navegador (ou a rede da
    // loja) devolveria a resposta guardada, que é exatamente a versão antiga
    // que estamos tentando detectar.
    const r = await fetch(`/versao.json?t=${Date.now()}`, { cache: "no-store" });
    if (!r.ok) return null;
    return (await r.json()) as Versao;
  } catch {
    // Sem internet, ou publicação em andamento: não é assunto de quem está
    // usando. Tenta de novo na próxima.
    return null;
  }
}

/**
 * Apareceu versão nova? Separado para poder ser testado.
 *
 * Compara a HORA do build, não o commit: o commit pode vir vazio quando a
 * hospedagem não informa, e aí todo mundo seria "desconhecido" e iguais.
 * Só avisa quando a publicada é MAIS NOVA — publicar uma versão antiga de
 * volta (um retorno de emergência) não deve mandar ninguém "atualizar" para
 * trás sem necessidade; o navegador já vai pegar a certa sozinho.
 */
export function temVersaoNova(minha: Versao, publicada: Versao): boolean {
  if (!minha.em || !publicada.em) return false;
  if (minha.em === publicada.em) return false;
  return new Date(publicada.em).getTime() > new Date(minha.em).getTime();
}

export function VersaoNova() {
  const [nova, setNova] = useState<Versao | null>(null);

  useEffect(() => {
    // Em desenvolvimento não há build, então não há o que comparar.
    if (!VERSAO.em) return;

    let vivo = true;
    async function conferir() {
      const v = await versaoPublicada();
      if (!vivo || !v) return;
      if (temVersaoNova(VERSAO, v)) setNova(v);
    }

    conferir();
    const t = setInterval(conferir, INTERVALO);
    const aoVoltar = () => {
      if (document.visibilityState === "visible") conferir();
    };
    document.addEventListener("visibilitychange", aoVoltar);
    return () => {
      vivo = false;
      clearInterval(t);
      document.removeEventListener("visibilitychange", aoVoltar);
    };
  }, []);

  if (!nova) return null;

  return (
    // sticky, não fixed: assim ela EMPURRA a tela para baixo em vez de tapar o
    // título — no balcão, um aviso cobrindo a fila seria pior que o problema.
    <div className="sticky top-0 z-50 flex flex-wrap items-center justify-center gap-x-3 gap-y-1 bg-primary px-4 py-2 text-center text-sm text-primary-foreground">
      <span>Versão nova disponível.</span>
      <button
        onClick={() => window.location.reload()}
        className="rounded-md bg-primary-foreground/15 px-3 py-1 font-medium underline-offset-2 hover:underline"
      >
        Atualizar agora
      </button>
      <button
        onClick={() => setNova(null)}
        aria-label="Fechar o aviso"
        className="px-2 text-primary-foreground/70"
      >
        ✕
      </button>
    </div>
  );
}
