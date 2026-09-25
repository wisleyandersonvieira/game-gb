// Os três gráficos do Início, num arquivo separado de propósito: a biblioteca
// de gráficos pesa ~330 KB e o Início é a primeira tela depois do login. Assim
// ela só é baixada quando há dado para desenhar (ver inicio.tsx).
import { CaixaGrafico, GraficoEntregas, GraficoPontos, GraficoVendas } from "@/inicio/Graficos";
import type { PainelInicio } from "@/inicio/tipos";

export default function PainelDeGraficos({ p }: { p: PainelInicio }) {
  return (
    <div className="grid gap-4 lg:grid-cols-2">
      <div className="lg:col-span-2">
        <CaixaGrafico titulo="Vendas do mês" descricao="Vendido por dia contra a meta do dia. Verde: meta batida.">
          <GraficoVendas dados={p.vendas} hoje={p.hoje} />
        </CaixaGrafico>
      </div>
      <CaixaGrafico titulo="Pontos por semana" descricao="Entraram (aprovações e bônus, já sem estornos) e saíram (resgates).">
        <GraficoPontos dados={p.pontos} />
      </CaixaGrafico>
      <CaixaGrafico titulo="Entregas no mês" descricao="Aprovadas e recusadas, por semana.">
        <GraficoEntregas dados={p.entregas} />
      </CaixaGrafico>
    </div>
  );
}
