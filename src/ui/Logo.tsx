// Logo STGame. No tema escuro entra a versão negativa. Em volta do logo fica
// um espaço livre proporcional (18px a cada 64px de altura).
import logoClaro from "@/assets/brand/stgame-logo.svg";
import logoEscuro from "@/assets/brand/stgame-logo-negativo.svg";
import simbolo from "@/assets/brand/stgame-simbolo.svg";

const PROPORCAO = 260 / 64;

export function Logo({ altura = 28, respiro = true, className = "" }: { altura?: number; respiro?: boolean; className?: string }) {
  const largura = Math.round(altura * PROPORCAO);
  const espaco = respiro ? Math.round((altura * 18) / 64) : 0;
  return (
    <span className={`inline-flex shrink-0 ${className}`} style={{ padding: espaco }}>
      <img src={logoClaro} alt="STGame" width={largura} height={altura} className="block dark:hidden" style={{ height: altura, width: "auto" }} />
      <img src={logoEscuro} alt="STGame" width={largura} height={altura} className="hidden dark:block" style={{ height: altura, width: "auto" }} />
    </span>
  );
}

export function Simbolo({ tamanho = 32, className = "" }: { tamanho?: number; className?: string }) {
  return <img src={simbolo} alt="STGame" width={tamanho} height={tamanho} className={`block shrink-0 ${className}`} style={{ height: tamanho, width: tamanho }} />;
}
