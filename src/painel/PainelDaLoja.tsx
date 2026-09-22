// O painel da loja em si: barra do dia, pódio e Kanban.
// O mesmo componente serve o painel logado e a TV; na TV tudo fica maior.
// Os dados vêm prontos do banco (montar_painel), sem nenhum id, foto,
// observação, telefone ou CPF.
import { MetaCartao, type MetaPainel } from "./MetaDaLoja";
import { AgendaCartao, type ItemAgenda } from "./AgendaDaLoja";

export type DadosPainel = {
  loja: string;
  hoje: string;
  atualizadoem: string;
  progresso: { total: number; aprovadas: number; emvalidacao: number };
  parafazer: { titulo: string; pessoa: string; pontos: number; atrasada: boolean }[];
  emvalidacao: { titulo: string; pessoa: string; pontos: number; enviadaem: string; dehoje: boolean }[];
  pendentes: number;
  podio: { pessoa: string; pontos: number }[];
  atividade: { titulo: string; pessoa: string; pontos: number; aprovadaem: string }[];
  meta: MetaPainel;
  agenda: ItemAgenda[];
};

const MEDALHAS = ["🥇", "🥈", "🥉"];

export function hora(iso: string) {
  return new Date(iso).toLocaleTimeString("pt-BR", {
    timeZone: "America/Sao_Paulo",
    hour: "2-digit",
    minute: "2-digit",
  });
}

function diaEHora(iso: string) {
  return new Date(iso).toLocaleString("pt-BR", {
    timeZone: "America/Sao_Paulo",
    day: "2-digit",
    month: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  });
}

export function percentual(p: DadosPainel["progresso"]) {
  return p.total > 0 ? Math.round((p.aprovadas / p.total) * 100) : 0;
}

export function PainelDaLoja({ dados, tv = false }: { dados: DadosPainel; tv?: boolean }) {
  const t = {
    titulo: tv ? "text-2xl" : "text-sm",
    item: tv ? "text-2xl" : "text-sm",
    sub: tv ? "text-lg" : "text-xs",
    card: tv ? "p-5" : "p-3",
  };

  return (
    <div className={tv ? "space-y-8" : "space-y-6"}>
      <BarraDoDia progresso={dados.progresso} tv={tv} />

      <div className={`grid gap-4 ${tv ? "lg:grid-cols-4" : "md:grid-cols-4"}`}>
        {/* Pódio */}
        <section className={`space-y-3 rounded-xl border border-border bg-card ${t.card}`}>
          <h2 className={`${t.titulo} font-semibold`}>Pódio de hoje</h2>
          {dados.podio.length === 0 ? (
            <p className={`${t.sub} text-muted-foreground`}>Ninguém pontuou hoje ainda.</p>
          ) : (
            <ol className="space-y-2">
              {dados.podio.map((p, i) => (
                <li key={`${p.pessoa}-${i}`} className={`flex items-center justify-between ${t.item}`}>
                  <span>
                    <span className="mr-2">{MEDALHAS[i]}</span>
                    {p.pessoa}
                  </span>
                  <strong className="text-azul">{p.pontos}</strong>
                </li>
              ))}
            </ol>
          )}
        </section>

        {/* Para fazer hoje */}
        <Coluna titulo="Para fazer hoje" quantidade={dados.parafazer.length} tv={tv}>
          {dados.parafazer.map((i, n) => (
            <Item key={n} tv={tv} titulo={i.titulo} linha={`${i.pessoa} · ${i.pontos} pts`} destaque={i.atrasada ? "atrasada" : undefined} />
          ))}
          {dados.parafazer.length === 0 && <Vazio tv={tv} texto="Tudo feito por hoje." />}
        </Coluna>

        {/* Em validação: todas as pendentes, mesmo antigas */}
        <Coluna titulo="Em validação" quantidade={dados.pendentes} tv={tv}>
          {dados.emvalidacao.map((i, n) => (
            <Item
              key={n}
              tv={tv}
              titulo={i.titulo}
              linha={`${i.pessoa} · enviada ${i.dehoje ? `às ${hora(i.enviadaem)}` : `em ${diaEHora(i.enviadaem)}`}`}
              destaque={i.dehoje ? undefined : "de outro dia"}
            />
          ))}
          {dados.emvalidacao.length === 0 && <Vazio tv={tv} texto="Nada esperando validação." />}
        </Coluna>

        {/* Atividade recente */}
        <Coluna titulo="Atividade recente" quantidade={dados.atividade.length} tv={tv}>
          {dados.atividade.map((i, n) => (
            <Item key={n} tv={tv} titulo={`✅ ${i.titulo}`} linha={`${i.pessoa} · +${i.pontos} · ${hora(i.aprovadaem)}`} />
          ))}
          {dados.atividade.length === 0 && <Vazio tv={tv} texto="Nenhuma aprovação hoje ainda." />}
        </Coluna>
      </div>

      {/* Espaços que as próximas fases preenchem */}
      <div className={`grid gap-4 ${tv ? "lg:grid-cols-3" : "md:grid-cols-3"}`}>
        <MetaCartao meta={dados.meta} tv={tv} />
        <Reservado tv={tv} titulo="Resgates recentes" fase="Fase 7" />
        <AgendaCartao agenda={dados.agenda ?? []} tv={tv} />
      </div>
    </div>
  );
}

/** Barra em duas cores: verde = aprovado; faixa clara = entregue, esperando validação. */
export function BarraDoDia({
  progresso,
  tv = false,
  compacta = false,
}: {
  progresso: DadosPainel["progresso"];
  tv?: boolean;
  compacta?: boolean;
}) {
  const { total, aprovadas, emvalidacao } = progresso;
  const pAprovado = total > 0 ? (aprovadas / total) * 100 : 0;
  const pValidacao = total > 0 ? (emvalidacao / total) * 100 : 0;

  return (
    <div className="space-y-2">
      <div className={`overflow-hidden rounded-full bg-muted ${tv ? "h-10" : compacta ? "h-3" : "h-6"}`}>
        <div className="flex h-full">
          <div className="h-full bg-sucesso transition-all duration-700" style={{ width: `${pAprovado}%` }} />
          <div className="h-full bg-sucesso/35 transition-all duration-700" style={{ width: `${pValidacao}%` }} />
        </div>
      </div>
      {!compacta && (
        <p className={`${tv ? "text-2xl" : "text-sm"} text-muted-foreground`}>
          {total === 0 ? (
            "Nenhuma tarefa para hoje."
          ) : (
            <>
              <strong className="text-foreground">
                {aprovadas} de {total}
              </strong>{" "}
              tarefas concluídas ({percentual(progresso)}%)
              {emvalidacao > 0 && ` · ${emvalidacao} esperando validação`}
            </>
          )}
        </p>
      )}
    </div>
  );
}

function Coluna({
  titulo,
  quantidade,
  tv,
  children,
}: {
  titulo: string;
  quantidade: number;
  tv: boolean;
  children: React.ReactNode;
}) {
  return (
    <section className={`space-y-2 rounded-xl border border-border bg-card ${tv ? "p-5" : "p-3"}`}>
      <h2 className={`${tv ? "text-2xl" : "text-sm"} font-semibold`}>
        {titulo} <span className="text-muted-foreground">· {quantidade}</span>
      </h2>
      <div className={`space-y-2 overflow-y-auto ${tv ? "max-h-[55vh]" : "max-h-96"}`}>{children}</div>
    </section>
  );
}

function Item({ titulo, linha, destaque, tv }: { titulo: string; linha: string; destaque?: string; tv: boolean }) {
  return (
    <div className={`rounded-lg border border-border bg-background ${tv ? "px-4 py-3" : "px-3 py-2"}`}>
      <p className={`${tv ? "text-2xl" : "text-sm"} font-medium`}>
        {titulo}
        {destaque && (
          <span className={`ml-2 rounded-md border border-azul/40 bg-azul-soft px-1.5 text-azul ${tv ? "text-base" : "text-xs"}`}>
            {destaque}
          </span>
        )}
      </p>
      <p className={`${tv ? "text-lg" : "text-xs"} text-muted-foreground`}>{linha}</p>
    </div>
  );
}

function Vazio({ texto, tv }: { texto: string; tv: boolean }) {
  return <p className={`${tv ? "text-lg" : "text-xs"} py-4 text-center text-muted-foreground`}>{texto}</p>;
}

function Reservado({ titulo, fase, tv }: { titulo: string; fase: string; tv: boolean }) {
  return (
    <div className={`rounded-xl border border-dashed border-border ${tv ? "p-5" : "p-3"} text-center`}>
      <p className={`${tv ? "text-xl" : "text-sm"} font-medium text-muted-foreground`}>{titulo}</p>
      <p className={`${tv ? "text-base" : "text-xs"} text-muted-foreground`}>Em construção ({fase}).</p>
    </div>
  );
}
