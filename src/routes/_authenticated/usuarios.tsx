// Usuários e cargos (parte 5, 30/09/2026): SÓ do master, nunca delegável.
//
// O CARGO diz o QUÊ (as permissões); as LOJAS de cada pessoa dizem ONDE. Sem
// ajuste de caixinha por pessoa: para dar algo diferente a alguém, faça outro
// cargo (Duplicar ajuda). Quem decide tudo é o banco: esta tela só pergunta e
// mostra; o gerente nem chega aqui (o banco recusa as funções desta página).
import { createFileRoute } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useMemo, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Pagina } from "@/ui/Pagina";
import { useLojaAtiva } from "@/lojas/loja-ativa";
import { quandoFoi, useHojeDaConta } from "@/ui/hoje";
import { ativarGerente, convidarGerente, reenviarConviteGerente } from "@/servidor/usuarios";

export const Route = createFileRoute("/_authenticated/usuarios")({
  component: UsuariosECargos,
});

const campo = "rounded-lg border border-border bg-background px-3 py-2 text-sm";
const botao = "rounded-lg border border-border px-3 py-1.5 text-sm";
const principal = "rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground disabled:opacity-60";

type Cargo = { cargoid: number; nome: string; codigos: string[]; usuarios: number };
type Permissao = { codigo: string; tela: string; nome: string };
type Usuario = {
  userid: string;
  nome: string | null;
  email: string | null;
  cargoid: number;
  cargo: string;
  lojas: number[];
  funcionarioid: number | null;
  pessoa: string | null;
  ativo: boolean;
  convitependente: boolean;
  ultimoacesso: string | null;
};

function useCargos() {
  return useQuery({
    queryKey: ["cargos"],
    queryFn: async () => {
      const { data, error } = await supabase.rpc("cargos_da_conta");
      if (error) throw error;
      return (data ?? []) as Cargo[];
    },
  });
}

function useCatalogo() {
  return useQuery({
    queryKey: ["catalogo-permissoes"],
    queryFn: async () => {
      const { data, error } = await supabase.rpc("catalogo_de_permissoes");
      if (error) throw error;
      return (data ?? []) as Permissao[];
    },
  });
}

function UsuariosECargos() {
  const [aba, setAba] = useState<"usuarios" | "cargos" | "historico">("usuarios");
  const semCargo = useQuery({
    queryKey: ["permissoes-sem-cargo"],
    queryFn: async () => {
      const { data, error } = await supabase.rpc("permissoes_sem_cargo");
      if (error) throw error;
      return (data ?? []) as Permissao[];
    },
  });
  const n = semCargo.data?.length ?? 0;

  return (
    <Pagina titulo="Usuários e cargos">
      <p className="text-sm text-muted-foreground">
        Quem ajuda você a gerir as lojas. O <strong>cargo</strong> diz o que a pessoa pode fazer; as <strong>lojas</strong>{" "}
        dela dizem onde. Só você vê e mexe nesta página.
      </p>
      {n > 0 && (
        <div className="rounded-xl border border-amber-500/50 bg-amber-500/10 p-4 text-sm">
          <p className="font-semibold">
            {n === 1 ? "1 permissão nova aguardando" : `${n} permissões novas aguardando`}
          </p>
          <p className="mt-1 text-muted-foreground">
            Nenhum cargo tem {n === 1 ? "esta permissão" : "estas permissões"}, então ninguém além de você pode usá-
            {n === 1 ? "la" : "las"}. Se algum gerente precisar, marque no cargo dele.
          </p>
          <ul className="mt-2 list-inside list-disc">
            {semCargo.data?.map((p) => (
              <li key={p.codigo}>
                {p.tela}: {p.nome}
              </li>
            ))}
          </ul>
        </div>
      )}
      <div className="flex flex-wrap gap-x-2 border-b border-border">
        {(
          [
            ["usuarios", "Usuários"],
            ["cargos", "Cargos"],
            ["historico", "Histórico"],
          ] as const
        ).map(([id, rotulo]) => (
          <button
            key={id}
            onClick={() => setAba(id)}
            className={`rounded-t-lg px-4 py-2 text-sm font-medium ${aba === id ? "bg-card text-foreground" : "text-muted-foreground"}`}
          >
            {rotulo}
          </button>
        ))}
      </div>
      {aba === "usuarios" && <Usuarios />}
      {aba === "cargos" && <Cargos />}
      {aba === "historico" && <Historico />}
    </Pagina>
  );
}

/* ------------------------------------------------------------------ */
/* Usuários                                                            */
/* ------------------------------------------------------------------ */

function Usuarios() {
  const qc = useQueryClient();
  const cargos = useCargos();
  const { lojas } = useLojaAtiva();
  const [editando, setEditando] = useState<Usuario | "novo" | null>(null);
  const [recado, setRecado] = useState<string | null>(null);
  const usuarios = useQuery({
    queryKey: ["usuarios-gerenciais"],
    queryFn: async () => {
      const { data, error } = await supabase.rpc("usuarios_gerenciais");
      if (error) throw error;
      return (data ?? []) as Usuario[];
    },
  });
  const nomeLoja = (id: number) => lojas.find((l) => l.lojaid === id)?.nome ?? `Loja ${id}`;
  const atualizar = () => {
    qc.invalidateQueries({ queryKey: ["usuarios-gerenciais"] });
    qc.invalidateQueries({ queryKey: ["cargos"] });
  };
  const ativar = useMutation({
    mutationFn: (u: Usuario) => ativarGerente({ data: { userid: u.userid, ativo: !u.ativo } }),
    onSuccess: atualizar,
  });
  const reenviar = useMutation({
    mutationFn: (u: Usuario) => reenviarConviteGerente({ data: { userid: u.userid } }),
    onSuccess: (r) => setRecado(`Convite reenviado para ${r.email}.`),
  });

  if (editando !== null) {
    return (
      <FormularioUsuario
        usuario={editando === "novo" ? null : editando}
        cargos={cargos.data ?? []}
        aoTerminar={(texto) => {
          setEditando(null);
          setRecado(texto);
          atualizar();
        }}
      />
    );
  }

  return (
    <div className="space-y-3">
      {(cargos.data ?? []).length === 0 ? (
        <p className="text-sm text-muted-foreground">Crie um cargo primeiro (aba Cargos). Depois volte aqui.</p>
      ) : (
        <button data-botao="criar-gerente" className={principal} onClick={() => setEditando("novo")}>
          Criar usuário gerencial
        </button>
      )}
      {recado && <p className="text-sm text-sucesso">{recado}</p>}
      {ativar.isError && <p className="text-sm text-destructive">{(ativar.error as Error).message}</p>}
      {reenviar.isError && <p className="text-sm text-destructive">{(reenviar.error as Error).message}</p>}
      {(usuarios.data ?? []).length === 0 && !usuarios.isLoading && (
        <p className="text-sm text-muted-foreground">Nenhum usuário gerencial ainda.</p>
      )}
      {(usuarios.data ?? []).map((u) => (
        <div key={u.userid} className="space-y-1 rounded-xl border border-border bg-card p-4">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <p className="font-medium">
              {u.nome ?? u.email}
              <span className="ml-2 text-sm text-muted-foreground">{u.email}</span>
            </p>
            <span className="text-xs text-muted-foreground">
              {!u.ativo ? "Desativado" : u.convitependente ? "Convite enviado, ainda não entrou" : "Ativo"}
            </span>
          </div>
          <p className="text-sm">
            Cargo: <strong>{u.cargo}</strong> · Lojas: {u.lojas.map(nomeLoja).join(", ")}
            {u.pessoa && <> · Na equipe: {u.pessoa}</>}
          </p>
          <div className="flex flex-wrap gap-2 pt-1">
            <button className={botao} onClick={() => setEditando(u)}>
              Editar
            </button>
            <button
              className={botao}
              onClick={() =>
                (u.ativo
                  ? window.confirm(`Desativar ${u.nome ?? u.email}? A pessoa sai do sistema na hora.`)
                  : true) && ativar.mutate(u)
              }
            >
              {u.ativo ? "Desativar" : "Reativar"}
            </button>
            {u.ativo && u.convitependente && (
              <button className={botao} onClick={() => reenviar.mutate(u)}>
                Reenviar convite
              </button>
            )}
          </div>
        </div>
      ))}
    </div>
  );
}

function FormularioUsuario({
  usuario,
  cargos,
  aoTerminar,
}: {
  usuario: Usuario | null;
  cargos: Cargo[];
  aoTerminar: (recado: string) => void;
}) {
  const { lojas } = useLojaAtiva();
  const [nome, setNome] = useState(usuario?.nome ?? "");
  const [email, setEmail] = useState(usuario?.email ?? "");
  const [cargoid, setCargoid] = useState<number | "">(usuario?.cargoid ?? "");
  const [escolhidas, setEscolhidas] = useState<number[]>(usuario?.lojas ?? []);
  const [funcionarioid, setFuncionarioid] = useState<number | "">(usuario?.funcionarioid ?? "");
  const pessoas = useQuery({
    queryKey: ["pessoas-para-vinculo"],
    queryFn: async () => {
      const { data, error } = await supabase.rpc("pessoas_para", { p_codigo: "equipe.ver" });
      if (error) throw error;
      return (data ?? []).filter((p) => p.ativo);
    },
  });
  const cargo = cargos.find((c) => c.cargoid === cargoid);

  const salvar = useMutation({
    mutationFn: async () => {
      if (cargoid === "") throw new Error("Escolha um cargo.");
      if (escolhidas.length === 0) throw new Error("Escolha pelo menos uma loja.");
      const vinculo = funcionarioid === "" ? null : funcionarioid;
      if (usuario) {
        const { error } = await supabase.rpc("editar_usuario_gerencial", {
          p_userid: usuario.userid,
          p_nome: nome,
          p_cargoid: cargoid,
          p_lojas: escolhidas,
          p_funcionarioid: vinculo,
        });
        if (error) throw error;
        return "Alterações salvas. Valem na próxima ação da pessoa.";
      }
      const r = await convidarGerente({ data: { nome, email, cargoid, lojas: escolhidas, funcionarioid: vinculo } });
      return `Convite enviado para ${r.email}. A pessoa cria a própria senha pelo link do e-mail.`;
    },
    onSuccess: aoTerminar,
  });

  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        salvar.mutate();
      }}
      className="space-y-3 rounded-xl border border-border bg-card p-4"
    >
      <p className="font-semibold">{usuario ? "Editar usuário" : "Criar usuário gerencial"}</p>
      <div className="grid gap-3 sm:grid-cols-2">
        <input className={campo} placeholder="Nome" value={nome} onChange={(e) => setNome(e.target.value)} required />
        <input
          className={campo}
          placeholder="E-mail"
          type="email"
          value={email}
          disabled={usuario !== null}
          onChange={(e) => setEmail(e.target.value)}
          required
        />
        <select className={campo} value={cargoid} onChange={(e) => setCargoid(e.target.value ? Number(e.target.value) : "")}>
          <option value="">Cargo...</option>
          {cargos.map((c) => (
            <option key={c.cargoid} value={c.cargoid}>
              {c.nome}
            </option>
          ))}
        </select>
        <select
          className={campo}
          value={funcionarioid}
          onChange={(e) => setFuncionarioid(e.target.value ? Number(e.target.value) : "")}
          aria-label="Também é da equipe?"
        >
          <option value="">Não é da equipe</option>
          {(pessoas.data ?? []).map((p) => (
            <option key={p.funcionarioid} value={p.funcionarioid}>
              É {p.nomecompleto} na equipe
            </option>
          ))}
        </select>
      </div>
      <p className="text-xs text-muted-foreground">
        Se a pessoa também é da equipe, ligue-a aqui: é isso que impede que ela aprove a própria entrega ou dê pontos a si
        mesma.
      </p>
      <fieldset className="space-y-1">
        <legend className="text-sm font-medium">Lojas onde ela pode agir</legend>
        <div className="flex flex-wrap gap-3">
          {lojas.map((l) => (
            <label key={l.lojaid} className="flex items-center gap-2 text-sm">
              <input
                type="checkbox"
                checked={escolhidas.includes(l.lojaid)}
                onChange={(e) =>
                  setEscolhidas(e.target.checked ? [...escolhidas, l.lojaid] : escolhidas.filter((x) => x !== l.lojaid))
                }
              />
              {l.nome}
            </label>
          ))}
          <button type="button" className="text-xs text-azul underline" onClick={() => setEscolhidas(lojas.map((l) => l.lojaid))}>
            todas as lojas
          </button>
        </div>
      </fieldset>
      {cargo && (
        <p className="text-xs text-muted-foreground">
          O cargo {cargo.nome} tem {cargo.codigos.length} permissões. Para ver ou mudar quais, use a aba Cargos.
        </p>
      )}
      <div className="flex flex-wrap gap-2">
        <button type="submit" className={principal} disabled={salvar.isPending}>
          {usuario ? "Salvar" : "Mandar convite"}
        </button>
        <button type="button" className={botao} onClick={() => aoTerminar("")}>
          Cancelar
        </button>
      </div>
      {salvar.isError && <p className="text-sm text-destructive">{(salvar.error as Error).message}</p>}
    </form>
  );
}

/* ------------------------------------------------------------------ */
/* Cargos                                                              */
/* ------------------------------------------------------------------ */

function Cargos() {
  const qc = useQueryClient();
  const cargos = useCargos();
  const [editando, setEditando] = useState<Cargo | "novo" | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const atualizar = () => {
    qc.invalidateQueries({ queryKey: ["cargos"] });
    qc.invalidateQueries({ queryKey: ["permissoes-sem-cargo"] });
  };
  const acao = useMutation({
    mutationFn: async (f: () => Promise<{ error: unknown }>) => {
      const { error } = await f();
      if (error) throw error;
    },
    onSuccess: () => {
      setErro(null);
      atualizar();
    },
    onError: (e) => setErro((e as Error).message),
  });

  if (editando !== null) {
    return (
      <FormularioCargo
        cargo={editando === "novo" ? null : editando}
        aoTerminar={() => {
          setEditando(null);
          atualizar();
        }}
      />
    );
  }

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap gap-2">
        <button className={principal} onClick={() => setEditando("novo")}>
          Novo cargo
        </button>
        <button
          className={botao}
          onClick={() => acao.mutate(() => supabase.rpc("criar_cargo_acesso_total", {}) as unknown as Promise<{ error: unknown }>)}
        >
          Criar cargo "Acesso total"
        </button>
      </div>
      <p className="text-xs text-muted-foreground">
        "Acesso total" nasce com todas as permissões que existem hoje. Permissão que entrar no sistema depois não entra
        sozinha em cargo nenhum: ela aparece no aviso lá em cima, para você decidir.
      </p>
      {erro && <p className="text-sm text-destructive">{erro}</p>}
      {(cargos.data ?? []).length === 0 && !cargos.isLoading && (
        <p className="text-sm text-muted-foreground">Nenhum cargo ainda.</p>
      )}
      {(cargos.data ?? []).map((c) => (
        <div key={c.cargoid} className="flex flex-wrap items-center justify-between gap-2 rounded-xl border border-border bg-card p-4">
          <p>
            <strong>{c.nome}</strong>
            <span className="ml-2 text-sm text-muted-foreground">
              {c.codigos.length} permissões · {c.usuarios === 1 ? "1 usuário" : `${c.usuarios} usuários`}
            </span>
          </p>
          <div className="flex flex-wrap gap-2">
            <button className={botao} onClick={() => setEditando(c)}>
              Editar
            </button>
            <button
              className={botao}
              onClick={() => {
                const nome = window.prompt("Nome do novo cargo", `${c.nome} (cópia)`);
                if (nome) acao.mutate(() => supabase.rpc("duplicar_cargo", { p_cargoid: c.cargoid, p_nome: nome }) as unknown as Promise<{ error: unknown }>);
              }}
            >
              Duplicar
            </button>
            <button
              className={botao}
              onClick={() =>
                window.confirm(`Apagar o cargo ${c.nome}?`) &&
                acao.mutate(() => supabase.rpc("apagar_cargo", { p_cargoid: c.cargoid }) as unknown as Promise<{ error: unknown }>)
              }
            >
              Apagar
            </button>
          </div>
        </div>
      ))}
    </div>
  );
}

function FormularioCargo({ cargo, aoTerminar }: { cargo: Cargo | null; aoTerminar: () => void }) {
  const catalogo = useCatalogo();
  const [nome, setNome] = useState(cargo?.nome ?? "");
  const [marcadas, setMarcadas] = useState<string[]>(cargo?.codigos ?? []);
  const porTela = useMemo(() => {
    const m = new Map<string, Permissao[]>();
    for (const p of catalogo.data ?? []) m.set(p.tela, [...(m.get(p.tela) ?? []), p]);
    return [...m.entries()];
  }, [catalogo.data]);
  const salvar = useMutation({
    mutationFn: async () => {
      const { error } = await supabase.rpc("salvar_cargo", {
        p_cargoid: cargo?.cargoid ?? (null as unknown as number),
        p_nome: nome,
        p_codigos: marcadas,
      });
      if (error) throw error;
    },
    onSuccess: aoTerminar,
  });
  const alternar = (codigo: string, sim: boolean) =>
    setMarcadas(sim ? [...marcadas, codigo] : marcadas.filter((c) => c !== codigo));

  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        salvar.mutate();
      }}
      className="space-y-3 rounded-xl border border-border bg-card p-4"
    >
      <input className={`${campo} w-full sm:w-80`} placeholder="Nome do cargo" value={nome} onChange={(e) => setNome(e.target.value)} required />
      <p className="text-xs text-muted-foreground">
        O que ficar desmarcado, quem tem este cargo não pode. Valores em R$ só aparecem com "Ver valores em R$".
      </p>
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        {porTela.map(([tela, itens]) => (
          <fieldset key={tela} className="space-y-1 rounded-lg border border-border p-3">
            <legend className="px-1 text-sm font-medium">{tela}</legend>
            {itens.map((p) => (
              <label key={p.codigo} className="flex items-center gap-2 text-sm">
                <input type="checkbox" checked={marcadas.includes(p.codigo)} onChange={(e) => alternar(p.codigo, e.target.checked)} />
                {p.nome}
              </label>
            ))}
          </fieldset>
        ))}
      </div>
      <div className="flex flex-wrap gap-2">
        <button type="submit" className={principal} disabled={salvar.isPending}>
          Salvar cargo
        </button>
        <button type="button" className={botao} onClick={aoTerminar}>
          Cancelar
        </button>
      </div>
      {salvar.isError && <p className="text-sm text-destructive">{(salvar.error as Error).message}</p>}
    </form>
  );
}

/* ------------------------------------------------------------------ */
/* Histórico                                                           */
/* ------------------------------------------------------------------ */

const TABELA: Record<string, string> = {
  cargos: "Cargo",
  cargospermissoes: "Permissão do cargo",
  usuariosgerenciais: "Usuário",
  usuarioslojas: "Loja do usuário",
  contasusuarios: "Login",
};
const ACAO: Record<string, string> = { INSERT: "criou", UPDATE: "mudou", DELETE: "apagou" };

function resumo(j: unknown): string {
  if (!j || typeof j !== "object") return "—";
  const o = j as Record<string, unknown>;
  const partes = ["nome", "codigo", "lojaid", "cargoid", "ativo", "papel", "funcionarioid"]
    .filter((k) => o[k] !== undefined && o[k] !== null)
    .map((k) => `${k}: ${String(o[k])}`);
  return partes.join(" · ") || "—";
}

function Historico() {
  const relogio = useHojeDaConta();
  const historico = useQuery({
    queryKey: ["historico-permissoes"],
    queryFn: async () => {
      const { data, error } = await supabase.rpc("historico_de_permissoes", { p_limite: 300 });
      if (error) throw error;
      return data ?? [];
    },
  });
  return (
    <div className="space-y-2">
      <p className="text-xs text-muted-foreground">
        Tudo o que mudou em cargos, usuários e lojas, com quem fez, antes e depois. Nada daqui se apaga, nem quando o cargo
        ou o usuário deixa de existir.
      </p>
      {(historico.data ?? []).map((h) => (
        <div key={h.historicoid} className="rounded-lg border border-border bg-card p-3 text-sm">
          <p>
            <strong>{h.quem}</strong> {ACAO[h.acao] ?? h.acao} {TABELA[h.tabela] ?? h.tabela}
            <span className="ml-2 text-xs text-muted-foreground">{quandoFoi(h.em, relogio.data?.hoje, relogio.data?.fuso)}</span>
          </p>
          <p className="text-xs text-muted-foreground">
            Antes: {resumo(h.antes)} → Depois: {resumo(h.depois)}
          </p>
        </div>
      ))}
    </div>
  );
}
