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
# Mais a linha que confere TODAS as migrações, item a item (30/09/2026).
esperadas=$((esperadas + 1))

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
s="$(conferir "CREATE TABLE public.telegramvinculos (x integer);")"
if echo "$s" | grep -q "|rode aplicar-tirar-telegram.sql"; then
  echo "    ok  entrega mais nova faltando: manda rodar o arquivo dela"
else
  echo "    FALHOU: a entrega mais nova falta e o conferidor nao manda rodar:"; echo "$s" | grep "FALTA" | head -3; falhou=1
fi
# 4. O caso do erro no ar (30/09/2026): a migração 20260929231000 na primeira
#    versão, sem a coluna entregas.fotoaguardaremocaoem. A amostra da linha 260
#    não percebia; a conferência item a item tem de acusar a migração pelo nome
#    e NÃO mandar rodar arquivo nenhum.
s="$(conferir "ALTER TABLE public.entregas DROP COLUMN fotoaguardaremocaoem;")"
if echo "$s" | grep "FALTA|TODAS|migracao|20260929231000_fotos_de_verdade_e_saude: " | grep -q "coluna entregas.fotoaguardaremocaoem (não existe)" \
   && echo "$s" | grep "20260929231000" | grep -q "NÃO rode mais nada: mande-a para o Claude"; then
  echo "    ok  coluna que falta (o erro de 30/09): acusa a migração 20260929231000 e manda chamar o Claude"
else
  echo "    FALHOU: sem a coluna fotoaguardaremocaoem, o conferidor nao acusou a migracao 20260929231000:"; echo "$s" | grep "FALTA" | head -3; falhou=1
fi
# 5. O banco do Wisley no dia da entrega (30/09/2026): TUDO menos a entrega
#    mais nova. Foi o que ele rodou, e o conferidor nem abriu (uma linha nova
#    lia uma tabela que ainda nao existia). Aqui ele tem de rodar inteiro, mandar
#    rodar o arquivo novo e nao acusar mais nada.
novo=$(grep -oE "^\s*\('aplicar-[^']+\.sql', '[0-9]{14}'\)" "$RAIZ/supabase/conferir-o-banco.sql" | sed -E "s/.*'(aplicar-[^']+)', '([0-9]+)'.*/\2 \1/" | sort | tail -1)
versao_nova=${novo%% *}; arquivo_novo=${novo#* }
# O corte: tudo ATE a entrega anterior (o arquivo novo pode trazer varias
# migracoes; a primeira versao deste teste so tirava a ultima e passava com a
# linha quebrada — sabotagem que passou, 30/09/2026).
versao_anterior=$(grep -oE "^\s*\('aplicar-[^']+\.sql', '[0-9]{14}'\)" "$RAIZ/supabase/conferir-o-banco.sql" | sed -E "s/.*'([0-9]+)'.*/\1/" | sort -u | tail -2 | head -1)
C5="gamegb-conferidor-antes"
docker rm -f -v "$C5" >/dev/null 2>&1
docker run -d --name "$C5" --tmpfs /var/lib/postgresql/data -e POSTGRES_PASSWORD=teste postgres:17 >/dev/null
for _ in $(seq 1 60); do
  sleep 1
  prontos=$(docker logs "$C5" 2>&1 | grep -c "ready to accept connections" || true)
  if [ "$prontos" -ge 2 ] && docker exec "$C5" psql -U postgres -qtAc "select 1" >/dev/null 2>&1; then break; fi
done
rodar5() { docker cp "$1" "$C5:/x.sql" >/dev/null; docker exec "$C5" psql -U postgres -q -v ON_ERROR_STOP=1 -f /x.sql >/dev/null 2>&1; }
rodar5 "$RAIZ/supabase/tests/_ambiente_local.sql"
for m in "$RAIZ"/supabase/migrations/*.sql; do
  b=$(basename "$m"); [[ ! "${b:0:14}" > "$versao_anterior" ]] && rodar5 "$m"
done
docker cp "$RAIZ/supabase/conferir-o-banco.sql" "$C5:/conferidor.sql" >/dev/null
s="$(docker exec "$C5" psql -U postgres -qtA -F '|' -f /conferidor.sql 2>&1)"
docker rm -f -v "$C5" >/dev/null 2>&1
outras=$(echo "$s" | grep "FALTA" | grep -v "|rode $arquivo_novo\$" | grep -v "|TODAS|" || true)
if echo "$s" | grep -q "ERROR"; then
  echo "    FALHOU: sem a entrega mais nova ($arquivo_novo), o conferidor nem roda:"; echo "$s" | grep "ERROR" | head -3; falhou=1
elif ! echo "$s" | grep -q "|rode $arquivo_novo"; then
  echo "    FALHOU: sem a entrega mais nova, o conferidor nao manda rodar $arquivo_novo"; falhou=1
elif [ -n "$outras" ]; then
  echo "    FALHOU: sem a entrega mais nova, o conferidor acusa outra coisa:"; echo "$outras" | head -3; falhou=1
else
  echo "    ok  banco sem a entrega mais nova: roda inteiro e manda rodar $arquivo_novo"
fi
exit $falhou
