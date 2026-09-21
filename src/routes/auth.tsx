import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { destinoDoUsuario } from "@/integrations/supabase/destino";

export const Route = createFileRoute("/auth")({
  head: () => ({
    meta: [
      { title: "Entrar — Game GB" },
      {
        name: "description",
        content: "Área restrita. O acesso é por convite do administrador.",
      },
      { property: "og:title", content: "Entrar — Game GB" },
      { property: "og:description", content: "Área restrita." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
  component: AuthPage,
});

function AuthPage() {
  const navigate = useNavigate();
  const [email, setEmail] = useState("");
  const [senha, setSenha] = useState("");
  const [erro, setErro] = useState<string | null>(null);
  const [aviso, setAviso] = useState<string | null>(null);
  const [carregando, setCarregando] = useState(false);

  async function entrar(e: React.FormEvent) {
    e.preventDefault();
    setErro(null);
    setAviso(null);
    setCarregando(true);

    const { error } = await supabase.auth.signInWithPassword({ email, password: senha });
    if (error) {
      setCarregando(false);
      setErro(
        error.message === "Invalid login credentials"
          ? "E-mail ou senha incorretos."
          : error.message,
      );
      return;
    }

    const destino = await destinoDoUsuario();
    setCarregando(false);
    navigate({ to: destino });
  }

  async function esqueciSenha() {
    setErro(null);
    setAviso(null);
    if (!email) {
      setErro("Digite seu e-mail acima primeiro.");
      return;
    }
    const { error } = await supabase.auth.resetPasswordForEmail(email, {
      redirectTo: `${window.location.origin}/definir-senha`,
    });
    if (error) setErro(error.message);
    else setAviso("Se esse e-mail tiver acesso, enviamos um link para definir uma senha nova.");
  }

  return (
    <main className="flex min-h-screen items-center justify-center p-6">
      <form
        onSubmit={entrar}
        className="w-full max-w-sm space-y-4 rounded-xl border border-border bg-card p-6"
      >
        <div>
          <h1 className="text-2xl font-bold">Entrar</h1>
          <p className="mt-1 text-sm text-muted-foreground">
            O acesso é só por convite. Fale com o administrador se ainda não recebeu o seu.
          </p>
        </div>

        <input
          type="email"
          required
          autoComplete="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          placeholder="E-mail"
          className="w-full rounded-lg border border-border bg-background px-3 py-2"
        />
        <input
          type="password"
          required
          autoComplete="current-password"
          value={senha}
          onChange={(e) => setSenha(e.target.value)}
          placeholder="Senha"
          className="w-full rounded-lg border border-border bg-background px-3 py-2"
        />

        {erro && <p className="text-sm text-destructive">{erro}</p>}
        {aviso && <p className="text-sm text-muted-foreground">{aviso}</p>}

        <button
          type="submit"
          disabled={carregando}
          className="w-full rounded-lg bg-primary px-4 py-2 font-semibold text-primary-foreground disabled:opacity-60"
        >
          {carregando ? "Aguarde..." : "Entrar"}
        </button>

        <button
          type="button"
          onClick={esqueciSenha}
          className="w-full text-sm text-muted-foreground underline"
        >
          Esqueci minha senha
        </button>
      </form>
    </main>
  );
}
