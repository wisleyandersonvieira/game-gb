// Botão padrão do sistema. No celular a área de toque já é grande (44 px).
import { cva, type VariantProps } from "class-variance-authority";
import type { ButtonHTMLAttributes } from "react";

export const estiloBotao = cva(
  "inline-flex items-center justify-center gap-2 rounded-lg font-semibold transition disabled:cursor-not-allowed disabled:opacity-50 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
  {
    variants: {
      variante: {
        primario: "bg-primary text-primary-foreground hover:opacity-90",
        secundario: "border border-border bg-card text-foreground hover:bg-muted",
        perigo: "border border-destructive text-destructive hover:bg-destructive/10",
        fantasma: "text-muted-foreground hover:bg-muted hover:text-foreground",
      },
      tamanho: {
        normal: "px-4 py-2 text-sm",
        pequeno: "px-3 py-1.5 text-xs",
        icone: "h-10 w-10 p-0",
      },
    },
    defaultVariants: { variante: "primario", tamanho: "normal" },
  },
);

export type PropsBotao = ButtonHTMLAttributes<HTMLButtonElement> & VariantProps<typeof estiloBotao>;

export function Botao({ variante, tamanho, className, type = "button", ...resto }: PropsBotao) {
  return <button type={type} className={estiloBotao({ variante, tamanho, className })} {...resto} />;
}
