// A faixa vermelha do /admin (01/10/2026, decisão do Wisley): qualquer ✗ da
// plataforma aparece no topo, sem precisar abrir a /saude.
// Só avisa quem abre o /admin. Sem o Telegram (retirado em 04/10/2026), esta
// faixa e a /saude são os únicos alarmes da plataforma: nenhum dos dois manda
// aviso a ninguém, os dois esperam alguém abrir a tela.
import { Link } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { diagnostico } from "@/servidor/acesso";
import { problemasDaPlataforma } from "@/ui/saude-plataforma";

export function FaixaDaPlataforma() {
  const d = useQuery({
    queryKey: ["faixa-da-plataforma"],
    refetchInterval: 5 * 60 * 1000,
    queryFn: async () => {
      const { data: sessao } = await supabase.auth.getSession();
      return diagnostico({ data: { token: sessao.session?.access_token } });
    },
  });
  if (!d.data || !d.data.detalhe) return null;
  const problemas = problemasDaPlataforma(d.data);
  if (problemas.length === 0) return null;
  return (
    <div className="mb-4 rounded-lg border-2 border-destructive bg-card p-4 text-sm">
      <p className="font-semibold text-destructive">
        {problemas.length === 1 ? "A plataforma tem 1 problema" : `A plataforma tem ${problemas.length} problemas`}
      </p>
      <ul className="mt-2 list-disc space-y-1 pl-5">
        {problemas.slice(0, 8).map((x) => (
          <li key={x}>{x}</li>
        ))}
      </ul>
      {problemas.length > 8 && <p className="mt-1 text-muted-foreground">e mais {problemas.length - 8}.</p>}
      <Link to="/saude" className="mt-2 inline-block font-medium underline">
        Ver a Saúde do sistema
      </Link>
    </div>
  );
}
