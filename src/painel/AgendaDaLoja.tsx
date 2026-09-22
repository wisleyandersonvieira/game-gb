// Próximos agendamentos no painel da loja e na TV.
// Os dados vêm do banco (agenda_para_painel): na TV só hora e tipo; no
// painel logado também o primeiro nome do cliente. CPF, telefone,
// observações e valor nunca chegam aqui.

export type ItemAgenda = { quando: string; tipo: string; cliente?: string };

const FUSO = "America/Sao_Paulo";

function diaDe(iso: string) {
  return new Intl.DateTimeFormat("en-CA", { timeZone: FUSO }).format(new Date(iso));
}

/** "Hoje", "Amanhã" ou "sáb., 27/09". */
function rotuloDoDia(iso: string) {
  const hoje = new Intl.DateTimeFormat("en-CA", { timeZone: FUSO }).format(new Date());
  const amanha = new Date(`${hoje}T12:00:00Z`);
  amanha.setUTCDate(amanha.getUTCDate() + 1);
  const d = diaDe(iso);
  if (d === hoje) return "Hoje";
  if (d === amanha.toISOString().slice(0, 10)) return "Amanhã";
  return new Date(iso).toLocaleDateString("pt-BR", { timeZone: FUSO, weekday: "short", day: "2-digit", month: "2-digit" });
}

/** "15h" ou "15h30". */
function horaCurta(iso: string) {
  const [h, m] = new Date(iso)
    .toLocaleTimeString("pt-BR", { timeZone: FUSO, hour: "2-digit", minute: "2-digit" })
    .split(":");
  return m === "00" ? `${Number(h)}h` : `${Number(h)}h${m}`;
}

export function AgendaCartao({ agenda, tv = false }: { agenda: ItemAgenda[]; tv?: boolean }) {
  return (
    <section className={`space-y-2 rounded-xl border border-border bg-card ${tv ? "p-5" : "p-3"}`}>
      <h2 className={`${tv ? "text-xl" : "text-sm"} font-semibold`}>Próximos agendamentos</h2>
      {agenda.length === 0 ? (
        <p className={`${tv ? "text-base" : "text-xs"} text-muted-foreground`}>Nenhum agendamento confirmado.</p>
      ) : (
        <ul className="space-y-1.5">
          {agenda.map((a, i) => (
            <li key={`${a.quando}-${i}`} className={`flex items-baseline justify-between gap-2 ${tv ? "text-lg" : "text-sm"}`}>
              <span>
                <strong>{horaCurta(a.quando)}</strong> — {a.tipo}
                {a.cliente && <span className="text-muted-foreground"> · {a.cliente}</span>}
              </span>
              <span className={`${tv ? "text-base" : "text-xs"} whitespace-nowrap text-muted-foreground`}>{rotuloDoDia(a.quando)}</span>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

/** Tela cheia da agenda, usada no rodízio da TV (só hora e tipo). */
export function TelaDaAgenda({ agenda }: { agenda: ItemAgenda[] }) {
  const porDia = agenda.reduce<{ dia: string; itens: ItemAgenda[] }[]>((acc, a) => {
    const r = rotuloDoDia(a.quando);
    const ultimo = acc[acc.length - 1];
    if (ultimo && ultimo.dia === r) ultimo.itens.push(a);
    else acc.push({ dia: r, itens: [a] });
    return acc;
  }, []);

  return (
    <div className="space-y-8 py-6">
      <p className="text-center text-2xl font-semibold text-muted-foreground sm:text-4xl">Próximos agendamentos</p>
      {porDia.map((g) => (
        <section key={g.dia} className="space-y-3">
          <p className="text-xl font-semibold capitalize sm:text-3xl">{g.dia}</p>
          <ul className="space-y-2">
            {g.itens.map((a, i) => (
              <li key={`${a.quando}-${i}`} className="rounded-xl border border-border bg-card px-5 py-4 text-2xl sm:text-4xl">
                <strong className="text-accent">{horaCurta(a.quando)}</strong> — {a.tipo}
              </li>
            ))}
          </ul>
        </section>
      ))}
    </div>
  );
}
