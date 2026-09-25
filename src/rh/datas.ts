// Formatação de data usada nas telas de RH. Fica FORA de pdf.ts de propósito:
// aquele módulo carrega o gerador de PDF (340 KB), e telas que só queriam
// formatar uma data estavam baixando o gerador inteiro à toa (medido em
// 24/09/2026: Onboarding e Documentos pessoais).
const FUSO = "America/Sao_Paulo";

export const dataHoraBr = (iso: string | Date) =>
  new Date(iso).toLocaleString("pt-BR", {
    timeZone: FUSO,
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
