// CNPJ na tela do admin. A MESMA conta do banco (public.cnpj_valido): a tela
// avisa antes de salvar, e o banco recusa de qualquer jeito.

export const soDigitos = (v: string | null | undefined) => (v ?? "").replace(/\D/g, "");

export function cnpjValido(v: string | null | undefined): boolean {
  const d = soDigitos(v);
  if (d.length !== 14 || /^(\d)\1{13}$/.test(d)) return false;
  const digito = (base: string, pesos: number[]) => {
    const r = pesos.reduce((s, p, i) => s + Number(base[i]) * p, 0) % 11;
    return r < 2 ? 0 : 11 - r;
  };
  const d1 = digito(d, [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]);
  const d2 = digito(d, [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]);
  return d1 === Number(d[12]) && d2 === Number(d[13]);
}

/** "11.222.333/0001-81". Enquanto incompleto, formata o que já tem. */
export function formatarCnpj(v: string | null | undefined): string {
  const d = soDigitos(v).slice(0, 14);
  return d
    .replace(/^(\d{2})(\d)/, "$1.$2")
    .replace(/^(\d{2})\.(\d{3})(\d)/, "$1.$2.$3")
    .replace(/\.(\d{3})(\d)/, ".$1/$2")
    .replace(/(\d{4})(\d)/, "$1-$2");
}

/** O formato do código da empresa: só a-z e 0-9, de 4 a 20. */
export const codigoNoFormato = (v: string) => /^[a-z0-9]{4,20}$/.test(v);
