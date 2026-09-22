import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { definirSenhaDeGestor } from "@/servidor/acesso";
import { destinoDoUsuario } from "@/integrations/supabase/destino";
import { Logo } from "@/ui/Logo";

export const Route = createFileRoute("/definir-senha")({
  ssr: false,
  component: DefinirSenha,
});

function DefinirSenha() {
  const navigate = useNavigate();
  const [pronto, setPronto] = useState(false);
  const [temSessao, setTemSessao] = useState(false);
  const [senha, setSenha] = useState("");
  const [repetir, setRepetir] = useState("");
  // Só é pedida a quem já tem senha (troca voluntária); no convite fica vazia.
  const [senhaAtual, setSenhaAtual] = useState("");
  const [erro, setErro] = useState<string | null>(null);
  const [salvando, setSalvando] = useState(false);

  // O link do convite chega de duas formas conforme a configuracao do Supabase:
  // com um ?code= na URL (troca por sessao) ou com os tokens no #hash (o
  // proprio cliente ja captura sozinho).
  useEffect(() => {
    (async () => {
      const code = new URLSearchParams(window.location.search).get("code");
      if (code) {
        const { error } = await supabase.auth.exchangeCodeForSession(code);
        if (error) setErro("Este link expirou ou já foi usado. Peça um novo ao administrador.");
      }
      const { data } = await supabase.auth.getSession();
      setTemSessao(Boolean(data.session));
      setPronto(true);
    })();
  }, []);

  async function salvar(e: React.FormEvent) {
    e.preventDefault();
    setErro(null);
    if (senha.length < 8) {
      setErro("A senha precisa ter pelo menos 8 caracteres.");
      return;
    }
    if (senha !== repetir) {
      setErro("As duas senhas não são iguais.");
      return;
    }
    setSalvando(true);
    // A senha do gestor passa a ser conferida pelo nosso servidor: é ele quem
    // guarda o resumo e troca a senha do Supabase pela interna.
    try {
      await definirSenhaDeGestor({ data: { senha, senhaatual: senhaAtual } });
    } catch (e) {
      setSalvando(false);
      setErro((e as Error).message);
      return;
    }
    const destino = await destinoDoUsuario();
    setSalvando(false);
    navigate({ to: destino });
  }

  if (!pronto) {
    return (
      <main className="flex min-h-screen items-center justify-center p-6">
        <p className="text-muted-foreground">Conferindo o link...</p>
      </main>
    );
  }

  return (
    <main className="flex min-h-screen flex-col items-center justify-center gap-2 p-6">
      <Logo altura={40} />
      <form
        onSubmit={salvar}
        className="w-full max-w-sm space-y-4 rounded-xl border border-border bg-card p-6"
      >
        <div>
          <h1 className="font-display text-2xl font-semibold">Definir senha</h1>
          <p className="mt-1 text-sm text-muted-foreground">
            Escolha a senha que você vai usar para entrar.
          </p>
        </div>

        {!temSessao && (
          <p className="text-sm text-destructive">
            Não reconhecemos este link. Ele pode ter expirado ou já ter sido usado. Peça um
            convite novo ao administrador.
          </p>
        )}

        <input
          type="password"
          autoComplete="current-password"
          value={senhaAtual}
          onChange={(e) => setSenhaAtual(e.target.value)}
          placeholder="Senha atual (só se você já tinha uma)"
          className="w-full rounded-lg border border-border bg-background px-3 py-2"
        />
        <input
          type="password"
          required
          minLength={8}
          autoComplete="new-password"
          value={senha}
          onChange={(e) => setSenha(e.target.value)}
          placeholder="Nova senha (mínimo 8 caracteres)"
          className="w-full rounded-lg border border-border bg-background px-3 py-2"
        />
        <input
          type="password"
          required
          minLength={8}
          autoComplete="new-password"
          value={repetir}
          onChange={(e) => setRepetir(e.target.value)}
          placeholder="Repita a senha"
          className="w-full rounded-lg border border-border bg-background px-3 py-2"
        />

        {erro && <p className="text-sm text-destructive">{erro}</p>}

        <button
          type="submit"
          disabled={salvando || !temSessao}
          className="w-full rounded-lg bg-primary px-4 py-2 font-semibold text-primary-foreground disabled:opacity-60"
        >
          {salvando ? "Salvando..." : "Salvar e entrar"}
        </button>
      </form>
    </main>
  );
}
