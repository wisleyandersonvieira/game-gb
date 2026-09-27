import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { destinoDoUsuario } from "@/integrations/supabase/destino";
import { concluirPrimeiroAcesso, conferirPrimeiroAcesso, entrarColaborador, entrarMaster } from "@/servidor/acesso";
import { faltaParaConcluir } from "@/ui/senhaEPin";
import { Logo } from "@/ui/Logo";

/** O codigo da empresa fica guardado no aparelho: quem le o QR uma vez nao digita mais. */
const CHAVE_EMPRESA = "stgame.empresa";

export const Route = createFileRoute("/auth")({
  head: () => ({
    meta: [
      { title: "Entrar — STGame" },
      {
        name: "description",
        content: "Área restrita. O acesso é por convite do administrador.",
      },
      { property: "og:title", content: "Entrar — STGame" },
      { property: "og:description", content: "Área restrita." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
  component: AuthPage,
});

function AuthPage() {
  const navigate = useNavigate();
  const [aba, setAba] = useState<"colaborador" | "primeiro" | "gestor">("colaborador");
  const [codigoAcesso, setCodigoAcesso] = useState("");
  const [empresa, setEmpresa] = useState("");
  const [cpf, setCpf] = useState("");
  const [email, setEmail] = useState("");
  const [senha, setSenha] = useState("");
  const [erro, setErro] = useState<string | null>(null);
  const [aviso, setAviso] = useState<string | null>(null);
  const [carregando, setCarregando] = useState(false);
  // Primeiro acesso em dois passos NA MESMA TELA: 1) o código é CONFERIDO
  // (não gasto); 2) senha e PIN, e só no "Concluir" o código é gasto — junto
  // com a senha e o PIN, tudo ou nada.
  const [etapa, setEtapa] = useState<"codigo" | "senhaepin">("codigo");
  const [nova, setNova] = useState({ senha: "", senha2: "", pin: "", pin2: "" });

  useEffect(() => {
    try {
      const guardada = localStorage.getItem(CHAVE_EMPRESA);
      if (guardada) setEmpresa(guardada);
    } catch {
      // Navegador sem armazenamento: e so digitar o codigo.
    }
  }, []);

  /** Quem entra pelo servidor recebe a sessao e a guarda aqui. */
  async function usarSessao(sessao: { access_token: string; refresh_token: string }) {
    const { error } = await supabase.auth.setSession(sessao);
    if (error) throw new Error("Não foi possível abrir a sessão. Tente de novo.");
    const destino = await destinoDoUsuario();
    navigate({ to: destino });
  }

  async function entrar(e: React.FormEvent) {
    e.preventDefault();
    setErro(null);
    setAviso(null);
    setCarregando(true);
    try {
      if (aba === "gestor") {
        await usarSessao(await entrarMaster({ data: { email, senha } }));
      } else {
        const codigo = empresa.trim().toLowerCase();
        const guardarEmpresa = () => {
          try {
            localStorage.setItem(CHAVE_EMPRESA, codigo);
          } catch {
            // Sem armazenamento: o codigo e digitado da proxima vez.
          }
        };
        if (aba === "primeiro" && etapa === "codigo") {
          await conferirPrimeiroAcesso({ data: { codigo, cpf, codigoacesso: codigoAcesso } });
          guardarEmpresa();
          setEtapa("senhaepin");
          return;
        }
        const sessao =
          aba === "primeiro"
            ? await concluirPrimeiroAcesso({ data: { codigo, cpf, codigoacesso: codigoAcesso, senha: nova.senha, pin: nova.pin } })
            : await entrarColaborador({ data: { codigo, cpf, senha } });
        guardarEmpresa();
        await usarSessao(sessao);
      }
    } catch (erroEntrada) {
      setErro((erroEntrada as Error).message);
    } finally {
      setCarregando(false);
    }
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
    <main className="flex min-h-screen flex-col items-center justify-center gap-2 p-6">
      <Logo altura={40} />
      <form
        onSubmit={entrar}
        className="w-full max-w-sm space-y-4 rounded-xl border border-border bg-card p-6"
      >
        <div>
          <h1 className="font-display text-2xl font-semibold">Entrar</h1>
          <p className="mt-1 text-sm text-muted-foreground">
            {aba === "colaborador"
              ? "Use o seu CPF e a sua senha."
              : aba === "primeiro"
                ? "Primeira vez? Use o CPF e o código que o seu gestor entregou. Ele vale uma vez só."
                : "Acesso do dono da conta, por e-mail."}
          </p>
        </div>

        <div className="grid grid-cols-3 gap-1 rounded-lg bg-muted p-1 text-sm">
          {(["colaborador", "primeiro", "gestor"] as const).map((v) => (
            <button
              key={v}
              type="button"
              onClick={() => {
                setAba(v);
                setErro(null);
                setEtapa("codigo");
              }}
              className={`rounded-md px-3 py-1.5 font-medium ${aba === v ? "bg-card shadow-sm" : "text-muted-foreground"}`}
            >
              {v === "colaborador" ? "Equipe" : v === "primeiro" ? "1º acesso" : "Gestor"}
            </button>
          ))}
        </div>

        {aba === "primeiro" && etapa === "senhaepin" ? (
          <CriarSenhaEPin valor={nova} mudar={setNova} voltar={() => { setEtapa("codigo"); setErro(null); }} />
        ) : aba !== "gestor" ? (
          <>
            <input
              required
              value={empresa}
              onChange={(e) => setEmpresa(e.target.value)}
              placeholder="Código da empresa"
              autoCapitalize="none"
              className="w-full rounded-lg border border-border bg-background px-3 py-2"
            />
            <input
              required
              inputMode="numeric"
              autoComplete="username"
              value={cpf}
              onChange={(e) => setCpf(e.target.value)}
              placeholder="CPF (só números)"
              className="w-full rounded-lg border border-border bg-background px-3 py-2"
            />
          </>
        ) : (
          <input
            type="email"
            required
            autoComplete="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            placeholder="E-mail"
            className="w-full rounded-lg border border-border bg-background px-3 py-2"
          />
        )}
        {aba === "primeiro" && etapa === "senhaepin" ? null : aba === "primeiro" ? (
          <input
            required
            value={codigoAcesso}
            onChange={(e) => setCodigoAcesso(e.target.value.toUpperCase())}
            placeholder="Código de primeiro acesso (ex.: ABCD-2345)"
            autoCapitalize="characters"
            className="w-full rounded-lg border border-border bg-background px-3 py-2 font-mono"
          />
        ) : (
          <input
            type="password"
            required
            autoComplete="current-password"
            value={senha}
            onChange={(e) => setSenha(e.target.value)}
            placeholder="Senha"
            className="w-full rounded-lg border border-border bg-background px-3 py-2"
          />
        )}

        {erro && <p className="text-sm text-destructive">{erro}</p>}
        {aviso && <p className="text-sm text-muted-foreground">{aviso}</p>}

        <button
          type="submit"
          disabled={carregando || (aba === "primeiro" && etapa === "senhaepin" && faltaParaConcluir(nova) !== null)}
          className="w-full rounded-lg bg-primary px-4 py-2 font-semibold text-primary-foreground disabled:opacity-60"
        >
          {aba === "primeiro" && etapa === "senhaepin"
            ? carregando
              ? "Salvando…"
              : "Concluir"
            : carregando
              ? "Aguarde..."
              : aba === "primeiro"
                ? "Continuar"
                : "Entrar"}
        </button>

        {aba === "gestor" ? (
          <button
            type="button"
            onClick={esqueciSenha}
            className="w-full text-sm text-muted-foreground underline"
          >
            Esqueci minha senha
          </button>
        ) : (
          <p className="text-center text-sm text-muted-foreground">
            Esqueceu a senha ou o PIN? Peça ao seu gestor um código novo.
          </p>
        )}
      </form>
    </main>
  );
}

/**
 * Passo 2 do primeiro acesso: senha e PIN. O que foi digitado continua aqui se
 * der erro (a pessoa corrige e tenta de novo). O botão Concluir, lá embaixo,
 * só acende quando o básico está certo.
 */
function CriarSenhaEPin({
  valor,
  mudar,
  voltar,
}: {
  valor: { senha: string; senha2: string; pin: string; pin2: string };
  mudar: (v: { senha: string; senha2: string; pin: string; pin2: string }) => void;
  voltar: () => void;
}) {
  const campo = "w-full rounded-lg border border-border bg-background px-3 py-2";
  const falta = faltaParaConcluir(valor);
  const comecou = valor.senha || valor.senha2 || valor.pin || valor.pin2;
  return (
    <div className="space-y-3">
      <p className="text-sm">
        Código conferido. Agora crie a sua <strong>senha</strong> e o seu <strong>PIN</strong> — os dois são só seus.
        Nada é gravado até você tocar em <strong>Concluir</strong>.
      </p>
      <input type="password" autoComplete="new-password" className={campo} placeholder="Senha (8 ou mais caracteres)"
        value={valor.senha} onChange={(e) => mudar({ ...valor, senha: e.target.value })} />
      <input type="password" autoComplete="new-password" className={campo} placeholder="Repita a senha"
        value={valor.senha2} onChange={(e) => mudar({ ...valor, senha2: e.target.value })} />
      <p className="text-xs text-muted-foreground">
        O PIN tem 6 números: é o que você digita no tablet da loja para aceitar e entregar tarefas. Não pode ser pedaço do
        seu CPF, sequência ou número repetido.
      </p>
      <input inputMode="numeric" maxLength={6} className={campo} placeholder="PIN de 6 números"
        value={valor.pin} onChange={(e) => mudar({ ...valor, pin: e.target.value.replace(/\D/g, "") })} />
      <input inputMode="numeric" maxLength={6} className={campo} placeholder="Repita o PIN"
        value={valor.pin2} onChange={(e) => mudar({ ...valor, pin2: e.target.value.replace(/\D/g, "") })} />
      {comecou && falta && <p className="text-xs text-muted-foreground">{falta}</p>}
      <button type="button" onClick={voltar} className="text-xs text-muted-foreground underline">
        Voltar e corrigir o código
      </button>
    </div>
  );
}
