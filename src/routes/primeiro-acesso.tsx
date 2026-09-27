// Primeiro acesso do colaborador: trocar a senha, escolher o PIN do tablet e
// dar ciência na política de uso. Enquanto faltar alguma das três, é a única
// tela que abre.
import { createFileRoute, redirect, useNavigate } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { meuAcesso } from "@/integrations/supabase/destino";
import { aceitarPolitica, completarSenhaEPin } from "@/servidor/acesso";
import { faltaParaConcluir } from "@/ui/senhaEPin";
import { Logo } from "@/ui/Logo";

export const Route = createFileRoute("/primeiro-acesso")({
  ssr: false,
  beforeLoad: async () => {
    // getSession() é local: não gasta uma ida ao servidor só para saber se
    // existe token. Quem confere de verdade é meuAcesso(), no banco.
    const { data } = await supabase.auth.getSession();
    if (!data.session) throw redirect({ to: "/auth" });
  },
  component: PrimeiroAcesso,
});

const campo = "w-full rounded-lg border border-border bg-background px-3 py-2";

function PrimeiroAcesso() {
  const navigate = useNavigate();
  const qc = useQueryClient();
  const [senha, setSenha] = useState("");
  const [senha2, setSenha2] = useState("");
  const [pin, setPin] = useState("");
  const [pin2, setPin2] = useState("");

  const acesso = useQuery({ queryKey: ["meu-acesso"], queryFn: meuAcesso });
  const a = acesso.data;

  // Senha e PIN JUNTOS, num "Concluir" só: ou grava os dois, ou nenhum. Se
  // der erro, o que foi digitado fica, e a mensagem aparece aqui mesmo.
  const concluir = useMutation({
    mutationFn: async () => {
      await completarSenhaEPin({ data: { senha: a?.semsenha ? senha : "", pin: a?.sempin ? pin : "" } });
    },
    onSuccess: async () => {
      await qc.invalidateQueries({ queryKey: ["meu-acesso"] });
    },
  });

  if (acesso.isLoading) return <main className="p-6 text-sm text-muted-foreground">Carregando…</main>;
  if (!a || a.tipo !== "colaborador") {
    return (
      <main className="flex min-h-screen flex-col items-center justify-center gap-3 p-6 text-center">
        <Logo altura={40} />
        <p className="text-sm text-muted-foreground">Esta tela é do aplicativo da equipe.</p>
      </main>
    );
  }

  const faltaSenha = a.semsenha === true;
  const faltaPin = a.sempin === true;
  const faltaPolitica = a.politicapendente;
  const falta = faltaParaConcluir({ senha, senha2, pin, pin2 }, { senha: faltaSenha, pin: faltaPin });

  if (!faltaSenha && !faltaPin && !faltaPolitica) {
    return <Entrando irPara={() => navigate({ to: "/eu" })} />;
  }

  return (
    <main className="mx-auto flex min-h-screen max-w-md flex-col gap-4 p-6">
      <Logo altura={36} />
      <h1 className="font-display text-2xl font-semibold">Bem-vindo, {a.nome}</h1>
      <p className="text-sm text-muted-foreground">
Dois passos rápidos e você está dentro. A senha e o PIN são só seus: não empreste a ninguém.
      </p>

      <section className="space-y-3 rounded-xl border border-border bg-card p-4">
        <h2 className="font-semibold">
          1. Crie a sua senha e o seu PIN {faltaSenha || faltaPin ? "" : "✓"}
        </h2>
        {(faltaSenha || faltaPin) && (
          <form
            onSubmit={(e) => {
              e.preventDefault();
              concluir.mutate();
            }}
            className="space-y-3"
          >
            {faltaSenha && (
              <>
                <p className="text-xs text-muted-foreground">
                  Senha: pelo menos 8 caracteres. Não pode ser um pedaço do seu CPF, nem sequência, nem número repetido.
                </p>
                <input type="password" autoComplete="new-password" className={campo} placeholder="Nova senha" value={senha} onChange={(e) => setSenha(e.target.value)} />
                <input type="password" autoComplete="new-password" className={campo} placeholder="Repita a senha" value={senha2} onChange={(e) => setSenha2(e.target.value)} />
              </>
            )}
            {faltaPin && (
              <>
                <p className="text-xs text-muted-foreground">
                  PIN: 6 números. É o que você digita no tablet da loja para aceitar e entregar tarefas.
                </p>
                <input inputMode="numeric" maxLength={6} className={campo} placeholder="PIN de 6 números" value={pin} onChange={(e) => setPin(e.target.value.replace(/\D/g, ""))} />
                <input inputMode="numeric" maxLength={6} className={campo} placeholder="Repita o PIN" value={pin2} onChange={(e) => setPin2(e.target.value.replace(/\D/g, ""))} />
              </>
            )}
            {(senha || senha2 || pin || pin2) && falta && !concluir.isError && (
              <p className="text-xs text-muted-foreground">{falta}</p>
            )}
            {concluir.isError && <p className="text-sm text-destructive">{(concluir.error as Error).message}</p>}
            <button
              type="submit"
              disabled={falta !== null || concluir.isPending}
              className="w-full rounded-lg bg-primary px-4 py-2 font-semibold text-primary-foreground disabled:opacity-50"
            >
              {concluir.isPending ? "Salvando…" : "Concluir"}
            </button>
          </form>
        )}
      </section>

      <section className="space-y-3 rounded-xl border border-border bg-card p-4">
        <h2 className="font-semibold">2. Leia e aceite a política de uso {faltaPolitica ? "" : "✓"}</h2>
        {faltaPolitica && <PoliticaDeUso aoAceitar={() => qc.invalidateQueries({ queryKey: ["meu-acesso"] })} />}
      </section>
    </main>
  );
}

/** O texto e a ciência vêm do comunicado da versão em vigor. */
function PoliticaDeUso({ aoAceitar }: { aoAceitar: () => void }) {
  const politica = useQuery({
    queryKey: ["politica-de-uso"],
    queryFn: async () => {
      const { data, error } = await supabase.rpc("minha_politica_de_uso");
      if (error) throw error;
      return data as { assinaturaid: number; titulo: string; conteudo: string } | null;
    },
  });

  const aceitar = useMutation({
    mutationFn: (assinaturaid: number) => aceitarPolitica({ data: { assinaturaid } }),
    onSuccess: aoAceitar,
  });

  if (politica.isLoading) return <p className="text-sm text-muted-foreground">Carregando…</p>;
  if (!politica.data) return <p className="text-sm text-muted-foreground">A empresa ainda não publicou a política.</p>;

  return (
    <>
      <div className="max-h-72 overflow-y-auto whitespace-pre-wrap rounded-lg border border-border bg-background p-3 text-sm">
        {politica.data.conteudo}
      </div>
      {aceitar.isError && <p className="text-sm text-destructive">{(aceitar.error as Error).message}</p>}
      <button
        onClick={() => aceitar.mutate(politica.data!.assinaturaid)}
        disabled={aceitar.isPending}
        className="rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground disabled:opacity-50"
      >
        Li e estou ciente
      </button>
    </>
  );
}

/** Não falta nada: entra direto no aplicativo (sem "Tudo pronto → Continuar"). */
function Entrando({ irPara }: { irPara: () => void }) {
  useEffect(() => {
    irPara();
  }, [irPara]);
  return <main className="p-6 text-sm text-muted-foreground">Entrando…</main>;
}
