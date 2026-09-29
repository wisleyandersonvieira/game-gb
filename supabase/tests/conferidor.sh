#!/usr/bin/env bash
# A trava do conferidor (29/09/2026). Roda o supabase/conferir-o-banco.sql de
# verdade, num banco com todas as migracoes, em tres situacoes:
#   1. banco completo: nenhuma linha pode dar FALTA (uma conferencia que
#      procura a coisa errada aparece aqui, antes de chegar ao Wisley);
#   2. uma entrega ANTIGA desfeita por cima (montar_painel de 29/09 manha):
#      o conferidor tem de dizer "NAO rode" e nunca mandar rodar o arquivo
#      velho (rodar desfaria o que veio depois);
#   3. a entrega MAIS NOVA faltando: ai sim ele manda rodar o arquivo dela.
# Uso: bash supabase/tests/conferidor.sh <container>
set -uo pipefail
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
C="$1"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

conferir() {  # conferir <sql antes> -> saida do conferidor, dentro de uma transacao desfeita
  { echo "BEGIN;"; printf '%s\n' "$1"; cat "$RAIZ/supabase/conferir-o-banco.sql"; echo "ROLLBACK;"; } > "$TMP/c.sql"
  docker cp "$TMP/c.sql" "$C:/conferidor.sql" >/dev/null
  docker exec "$C" psql -U postgres -qtA -F '|' -f /conferidor.sql 2>&1
}
falhou=0

# Quantas conferencias o arquivo tem (uma por linha com "'aplicar-...sql'" na lista).
esperadas=$(grep -cE "^\s*\(\s*[0-9]+,\s*'[^']*',\s*'[^']*',\s*'[^']*',\s*'aplicar-" "$RAIZ/supabase/conferir-o-banco.sql")

# 1. Banco completo: o conferidor RODA inteiro (sem erro) e nenhuma linha da FALTA.
#    "Nenhuma FALTA" sozinho nao prova nada: um conferidor quebrado tambem nao
#    mostra FALTA (aconteceu em 29/09/2026, por uma virgula).
s="$(conferir "")"
oks=$(echo "$s" | grep -c '^ok|')
if echo "$s" | grep -q "ERROR"; then
  echo "    FALHOU: o conferidor nem roda:"; echo "$s" | grep "ERROR" | head -3; falhou=1
elif echo "$s" | grep -q "FALTA"; then
  echo "    FALHOU: banco completo, e o conferidor acusa FALTA:"; echo "$s" | grep "FALTA" | head -5; falhou=1
elif [ "$oks" -ne "$esperadas" ]; then
  echo "    FALHOU: o conferidor devolveu $oks linhas ok, mas tem $esperadas conferencias"; falhou=1
else
  echo "    ok  banco completo: as $oks conferencias dao ok"
fi

# 2. Uma entrega antiga desfeita por cima: montar_painel como era em 29/09 de manha.
antigo="$(awk '/CREATE OR REPLACE FUNCTION public.montar_painel\(/,/^\$\$;/' "$RAIZ/supabase/migrations/20260929180000_primeiro_acesso_e_tv.sql")"
s="$(conferir "$antigo")"
if ! echo "$s" | grep -q "FALTA"; then
  echo "    FALHOU: com o painel antigo por cima, o conferidor nao percebeu"; falhou=1
elif echo "$s" | grep -E "\|rode aplicar-" >/dev/null; then
  echo "    FALHOU: o conferidor mandou rodar um arquivo mais velho que o ja aplicado:"; echo "$s" | grep -E "\|rode aplicar-" | head -3; falhou=1
elif ! echo "$s" | grep -q "NÃO rode aplicar-disponivel-uma-fonte.sql"; then
  echo "    FALHOU: faltou o \"NAO rode\" para o arquivo velho"; falhou=1
else
  echo "    ok  entrega antiga desfeita: diz \"NAO rode\" e nao manda rodar arquivo velho"
fi

# 3. A entrega mais nova faltando: manda rodar o arquivo dela.
s="$(conferir "CREATE OR REPLACE FUNCTION public.fila_no_dia(p_contaid integer, p_lojaid integer, p_dia date, p_fim timestamp with time zone)  RETURNS TABLE(atribuicaoid integer, entregarid integer, titulo character varying, pontos integer, tipofrequencia character varying, aberta boolean, donoid integer, quempegou integer, quempegounome text, pegaem timestamp with time zone, situacao text, atrasada boolean, disponiveldesde timestamp with time zone, rodizio boolean, agora timestamp with time zone, feitapor text, feitaem timestamp with time zone, feitasituacao text, liberada boolean, liberaas timestamp with time zone, hoje date, fuso text) LANGUAGE sql AS 'SELECT NULL::integer, NULL::integer, NULL::varchar, NULL::integer, NULL::varchar, NULL::boolean, NULL::integer, NULL::integer, NULL::text, NULL::timestamptz, NULL::text, NULL::boolean, NULL::timestamptz, NULL::boolean, NULL::timestamptz, NULL::text, NULL::timestamptz, NULL::text, NULL::boolean, NULL::timestamptz, NULL::date, NULL::text WHERE false';")"
if echo "$s" | grep -q "|rode aplicar-fila-fuso-uma-vez.sql"; then
  echo "    ok  entrega mais nova faltando: manda rodar o arquivo dela"
else
  echo "    FALHOU: a entrega mais nova falta e o conferidor nao manda rodar:"; echo "$s" | grep "FALTA" | head -3; falhou=1
fi
exit $falhou
