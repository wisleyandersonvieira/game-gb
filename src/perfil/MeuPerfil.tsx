// "Meu perfil": nome de exibição e tema. Cada pessoa altera só o próprio
// (o Supabase Auth só deixa o usuário mexer nos próprios dados).
import { useEffect, useState } from "react";
import { Botao } from "@/ui/Botao";
import { CabecalhoPagina } from "@/ui/CabecalhoPagina";
import { escolherTema, temaAtual, type Tema } from "@/ui/tema";
import { salvarNome, useUsuario } from "@/ui/usuario";
import { MeuTelegram } from "@/telegram/Telegram";

const campo = "w-full rounded-lg border border-border bg-background px-3 py-2 text-sm placeholder:text-muted-foreground";

/** `telegram`: só no app do master (o administrador geral não tem conta). */
export function MeuPerfil({ telegram = false }: { telegram?: boolean }) {
  const usuario = useUsuario();
  const [nome, setNome] = useState("");
  const [tema, setTema] = useState<Tema>("claro");
  const [aviso, setAviso] = useState<{ texto: string; grave: boolean } | null>(null);
  const [salvando, setSalvando] = useState(false);

  useEffect(() => {
    if (usuario) setNome(usuario.nomeProprio);
  }, [usuario]);
  useEffect(() => setTema(temaAtual()), []);

  async function salvar(e: React.FormEvent) {
    e.preventDefault();
    setSalvando(true);
    setAviso(null);
    try {
      await salvarNome(nome);
      setAviso({ texto: "Nome salvo.", grave: false });
    } catch (erro) {
      setAviso({ texto: (erro as Error).message, grave: true });
    } finally {
      setSalvando(false);
    }
  }

  return (
    <div className="mx-auto max-w-xl space-y-6">
      <CabecalhoPagina titulo="Meu perfil" descricao="Como você aparece no sistema. Vale só para o seu login." />

      <form onSubmit={salvar} className="space-y-3 rounded-xl border border-border bg-card p-4">
        <div className="space-y-1">
          <label htmlFor="nome" className="text-sm font-medium">
            Nome de exibição
          </label>
          <input
            id="nome"
            value={nome}
            maxLength={80}
            placeholder={usuario?.email ?? "Seu nome"}
            onChange={(e) => setNome(e.target.value)}
            className={campo}
          />
          <p className="text-xs text-muted-foreground">
            Aparece no topo da tela e no rodapé dos PDFs ("Gerado em … por …"). Em branco, usamos o seu e-mail.
          </p>
        </div>
        <div className="space-y-1">
          <p className="text-sm font-medium">E-mail de acesso</p>
          <p className="text-sm text-muted-foreground">{usuario?.email ?? "…"}</p>
        </div>
        <Botao type="submit" disabled={salvando || !usuario}>
          {salvando ? "Salvando..." : "Salvar nome"}
        </Botao>
        {aviso && <p className={`text-sm ${aviso.grave ? "text-destructive" : "text-sucesso"}`}>{aviso.texto}</p>}
      </form>

      <section className="space-y-3 rounded-xl border border-border bg-card p-4">
        <h2 className="text-sm font-medium">Tema</h2>
        <div className="grid grid-cols-2 gap-2">
          {(
            [
              ["claro", "Claro"],
              ["escuro", "Escuro"],
            ] as const
          ).map(([id, rotulo]) => (
            <button
              key={id}
              type="button"
              onClick={() => {
                setTema(id);
                escolherTema(id);
              }}
              aria-pressed={tema === id}
              className={`min-h-12 rounded-lg border px-3 text-sm ${
                tema === id ? "border-azul bg-azul-soft font-semibold text-azul" : "border-border"
              }`}
            >
              {rotulo}
            </button>
          ))}
        </div>
        <p className="text-xs text-muted-foreground">A escolha fica guardada no seu login e vale no próximo acesso. A TV continua escura.</p>
      </section>

      {telegram && <MeuTelegram />}
    </div>
  );
}
