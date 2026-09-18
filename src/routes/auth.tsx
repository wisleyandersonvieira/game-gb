import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";

export const Route = createFileRoute("/auth")({
  head: () => ({
    meta: [
      { title: "Acesso ao Painel — Gestão da Loja" },
      {
        name: "description",
        content: "Entre com seu e-mail para acessar o painel de tarefas e ranking.",
      },
      { property: "og:title", content: "Acesso ao Painel" },
      { property: "og:description", content: "Área restrita da equipe." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
  component: AuthPage,
});

function AuthPage() {
  const navigate = useNavigate();
  const [modo, setModo] = useState<"entrar" | "criar">("entrar");
  const [email, setEmail] = useState("");
  const [senha, setSenha] = useState("");
  const [erro, setErro] = useState<string | null>(null);
  const [carregando, setCarregando] = useState(false);

  async function enviar(e: React.FormEvent) {
    e.preventDefault();
    setErro(null);
    setCarregando(true);
    const res =
      modo === "entrar"
        ? await supabase.auth.signInWithPassword({ email, password: senha })
        : await supabase.auth.signUp({
            email,
            password: senha,
            options: { emailRedirectTo: `${window.location.origin}/painel` },
          });
    setCarregando(false);
    if (res.error) {
      setErro(res.error.message);
      return;
    }
    if (res.data.session) navigate({ to: "/painel" });
    else setErro("Conta criada. Confirme o e-mail ou entre novamente.");
  }

  return (
    <main className="min-h-screen flex items-center justify-center p-6">
      <form
        onSubmit={enviar}
        className="w-full max-w-sm space-y-4 rounded-xl border border-border bg-card p-6"
      >
        <h1 className="text-2xl font-bold">
          {modo === "entrar" ? "Entrar" : "Criar conta"}
        </h1>
        <input
          type="email"
          required
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          placeholder="E-mail"
          className="w-full rounded-lg border border-border bg-background px-3 py-2"
        />
        <input
          type="password"
          required
          minLength={6}
          value={senha}
          onChange={(e) => setSenha(e.target.value)}
          placeholder="Senha"
          className="w-full rounded-lg border border-border bg-background px-3 py-2"
        />
        {erro && <p className="text-sm text-destructive">{erro}</p>}
        <button
          type="submit"
          disabled={carregando}
          className="w-full rounded-lg bg-primary px-4 py-2 font-semibold text-primary-foreground disabled:opacity-60"
        >
          {carregando ? "Aguarde..." : modo === "entrar" ? "Entrar" : "Criar conta"}
        </button>
        <button
          type="button"
          onClick={() => setModo(modo === "entrar" ? "criar" : "entrar")}
          className="w-full text-sm text-muted-foreground underline"
        >
          {modo === "entrar" ? "Criar uma conta" : "Já tenho conta"}
        </button>
      </form>
    </main>
  );
}
