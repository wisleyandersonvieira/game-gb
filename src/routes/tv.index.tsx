// A TV entra por aqui: stgame.com.br/tv, sem código no endereço.
//
// Ela mostra um código de 6 caracteres, bem grande, e fica perguntando de
// tempos em tempos se já foi pareada. O gestor digita esse código no celular,
// escolhe a loja e dá um nome; a TV entra sozinha em seguida.
//
// Depois disso o link fica guardado NO PRÓPRIO APARELHO, e a TV abre direto
// toda vez que liga. Quando o gestor revoga, o painel para de responder e ela
// volta sozinha para a tela do código — sem ninguém ir até lá.
import { createFileRoute } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { useCallback, useEffect, useState } from "react";
import { pedirCodigoDaTv, verSeParearam } from "@/servidor/tv";
import { TelaDaTv } from "@/painel/TelaDaTv";
import { EstiloDaTv } from "@/painel/TelaDaTv";

export const Route = createFileRoute("/tv/")({
  ssr: false,
  head: () => ({
    meta: [
      { title: "TV da loja — STGame" },
      { name: "robots", content: "noindex, nofollow" },
    ],
  }),
  component: TvPareada,
});

/** Onde o aparelho guarda o que é dele. */
const GUARDADO = { link: "stgame.tv.link", segredo: "stgame.tv.segredo" };

/** De quanto em quanto tempo perguntar "já me parearam?". */
const PERGUNTAR_A_CADA = 5_000;

function leia(chave: string): string | null {
  try {
    return localStorage.getItem(chave);
  } catch {
    // Navegador de TV com armazenamento bloqueado: dá para parear, mas ela
    // vai pedir código de novo a cada vez que ligar. Melhor do que não abrir.
    return null;
  }
}

function guarde(chave: string, valor: string | null) {
  try {
    if (valor === null) localStorage.removeItem(chave);
    else localStorage.setItem(chave, valor);
  } catch {
    /* sem armazenamento: segue sem guardar */
  }
}

/** O segredo deste aparelho. Nasce uma vez e fica. */
function segredoDoAparelho(): string {
  const guardado = leia(GUARDADO.segredo);
  if (guardado && guardado.length >= 20) return guardado;
  const novo = crypto.randomUUID().replace(/-/g, "") + crypto.randomUUID().replace(/-/g, "");
  guarde(GUARDADO.segredo, novo);
  return novo;
}

function TvPareada() {
  const [link, setLink] = useState<string | null>(null);
  const [pronto, setPronto] = useState(false);

  useEffect(() => {
    setLink(leia(GUARDADO.link));
    setPronto(true);
  }, []);

  // Revogada pelo gestor: esquece o link e volta para o código.
  const perdeuAcesso = useCallback(() => {
    guarde(GUARDADO.link, null);
    // Segredo novo: o antigo já teve o código dele usado.
    guarde(GUARDADO.segredo, null);
    setLink(null);
  }, []);

  if (!pronto) return <main style={{ minHeight: "100vh", backgroundColor: "#0b1220" }} />;
  if (link) return <TelaDaTv codigo={link} aoPerderAcesso={perdeuAcesso} />;

  return <PedirPareamento aoParear={(t) => { guarde(GUARDADO.link, t); setLink(t); }} />;
}

function PedirPareamento({ aoParear }: { aoParear: (token: string) => void }) {
  const [segredo] = useState(segredoDoAparelho);
  const [erro, setErro] = useState(false);

  // O código. Vence em 10 minutos e é trocado sozinho — ninguém mexe na TV.
  const codigo = useQuery({
    queryKey: ["tv-codigo", segredo],
    // Um pouco antes dos 10 minutos, para nunca ficar um código morto na tela.
    refetchInterval: 9 * 60_000,
    refetchIntervalInBackground: true,
    retry: true,
    retryDelay: (t) => Math.min(30_000, 2000 * 2 ** t),
    queryFn: () => pedirCodigoDaTv({ data: { segredo } }),
  });

  // "Já me parearam?" — de 5 em 5 segundos, para a TV entrar logo depois do
  // gestor confirmar.
  const resposta = useQuery({
    queryKey: ["tv-esperando", segredo, codigo.data?.codigo],
    enabled: !!codigo.data,
    refetchInterval: PERGUNTAR_A_CADA,
    refetchIntervalInBackground: true,
    retry: true,
    queryFn: () => verSeParearam({ data: { segredo } }),
  });

  useEffect(() => {
    const r = resposta.data;
    if (!r) return;
    if (r.situacao === "pareada") aoParear(r.token);
    // Código vencido ou já usado: pede outro na hora.
    if (r.situacao === "vencido" || r.situacao === "ja_entregue") codigo.refetch();
  }, [resposta.data, aoParear, codigo]);

  useEffect(() => setErro(codigo.isError || resposta.isError), [codigo.isError, resposta.isError]);

  const texto = codigo.data?.codigo ?? "";

  return (
    <div
      className="tv-tela"
      // Se a folha cair, isto continua valendo: e o minimo legivel.
      style={{ backgroundColor: "#0b1220", color: "#f2f6fc", minHeight: "100vh", padding: "4%" }}
    >
      <EstiloDaTv />
      <div className="tv-centro">
        <p className="tv-legenda">Para ligar esta TV ao painel da loja:</p>

        {/* Bem grande: tem que ser lido do outro lado do salão. */}
        <p className="tv-codigo" style={{ fontSize: "160px", margin: "24px 0" }}>
          {texto || "••••••"}
        </p>

        <ol className="tv-passos">
          <li>1. No celular, entre no STGame como gestor.</li>
          <li>2. Vá em Gestão &rarr; Lojas &rarr; Link de TV &rarr; Parear TV.</li>
          <li>3. Digite o código acima, escolha a loja e dê um nome.</li>
        </ol>

        <p className="tv-aviso">
          {erro
            ? "Sem conexão. Tentando de novo..."
            : "O código vale 10 minutos e é trocado sozinho. Não precisa mexer aqui."}
        </p>
      </div>
    </div>
  );
}
