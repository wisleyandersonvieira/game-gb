#!/usr/bin/env bash
# Sobe um Postgres descartavel, aplica todas as migracoes e roda o teste de
# isolamento entre contas. Nao toca no Supabase.
#
#   bash supabase/tests/rodar.sh
#
# Sai com codigo 0 se tudo passou, diferente de 0 se qualquer checagem falhou.

set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONTAINER="gamegb-teste"
IMAGEM="postgres:17"

limpar() { docker rm -f "$CONTAINER" >/dev/null 2>&1 || true; }
trap limpar EXIT
limpar

echo "==> subindo $IMAGEM"
docker run -d --name "$CONTAINER" -e POSTGRES_PASSWORD=teste "$IMAGEM" >/dev/null
# A imagem oficial sobe um servidor temporario, roda a inicializacao e
# reinicia. So consideramos pronto quando o servidor definitivo responde, que
# e quando a mensagem "ready to accept connections" aparece pela segunda vez.
for _ in $(seq 1 60); do
  sleep 1
  prontos=$(docker logs "$CONTAINER" 2>&1 | grep -c "ready to accept connections" || true)
  if [ "$prontos" -ge 2 ] && docker exec "$CONTAINER" psql -U postgres -qtAc "select 1" >/dev/null 2>&1; then
    break
  fi
done

rodar() {
  docker cp "$1" "$CONTAINER:/$(basename "$1")" >/dev/null
  docker exec "$CONTAINER" psql -U postgres -q -v ON_ERROR_STOP=1 -f "/$(basename "$1")"
}

echo "==> simulando o ambiente do Supabase (auth, storage, papeis)"
rodar "$RAIZ/supabase/tests/_ambiente_local.sql" >/dev/null

echo "==> aplicando as migracoes"
for m in "$RAIZ"/supabase/migrations/*.sql; do
  printf '    %-52s ' "$(basename "$m")"
  if saida_m="$(rodar "$m" 2>&1 >/dev/null)"; then
    echo "ok"
  else
    echo "FALHOU"
    echo "$saida_m" | grep -E "ERROR" | head -5
    echo
    echo "TESTE DE ISOLAMENTO: FALHOU (migracao nao aplicou)"
    exit 1
  fi
done

echo "==> teste de isolamento entre contas"
saida="$(rodar "$RAIZ/supabase/tests/isolamento.sql" 2>&1)" && ok=1 || ok=0
echo "$saida" | sed -n 's/^psql:[^ ]* //p' | grep -vE '^(DO|SET|INSERT|CREATE|RESET)' || true

if [ "$ok" != "1" ]; then
  echo
  echo "TESTE DE ISOLAMENTO: FALHOU"
  echo "$saida" | grep -E 'ERROR|FALHOU' || true
  exit 1
fi

echo "==> dois resgates ao mesmo tempo (duas conexoes em paralelo)"
rodar "$RAIZ/supabase/tests/concorrencia_preparo.sql" >/dev/null
docker cp "$RAIZ/supabase/tests/concorrencia_sessao.sql" "$CONTAINER:/sessao.sql" >/dev/null
docker exec "$CONTAINER" psql -U postgres -q -f /sessao.sql >/tmp/gamegb-sessao1.txt 2>&1 &
p1=$!
docker exec "$CONTAINER" psql -U postgres -q -f /sessao.sql >/tmp/gamegb-sessao2.txt 2>&1 &
p2=$!
wait "$p1" "$p2" || true
recusas=$(cat /tmp/gamegb-sessao1.txt /tmp/gamegb-sessao2.txt | grep -c "Saldo insuficiente" || true)
echo "    conexao recusada por saldo insuficiente: $recusas de 2"
rm -f /tmp/gamegb-sessao1.txt /tmp/gamegb-sessao2.txt

saida_c="$(rodar "$RAIZ/supabase/tests/concorrencia_confere.sql" 2>&1)" && ok_c=1 || ok_c=0
echo "$saida_c" | sed -n 's/^psql:[^ ]* //p' | grep -vE '^(DO|SET)' || true

echo "==> duas aprovacoes ao mesmo tempo disputando a mesma conquista"
rodar "$RAIZ/supabase/tests/concorrencia_conquista_preparo.sql" >/dev/null
docker cp "$RAIZ/supabase/tests/concorrencia_conquista_sessao.sql" "$CONTAINER:/sessao_c.sql" >/dev/null
docker exec "$CONTAINER" psql -U postgres -q -v entrega=9201 -f /sessao_c.sql >/tmp/gamegb-sessao3.txt 2>&1 &
p3=$!
docker exec "$CONTAINER" psql -U postgres -q -v entrega=9202 -f /sessao_c.sql >/tmp/gamegb-sessao4.txt 2>&1 &
p4=$!
wait "$p3" "$p4" || true
erros_c=$(cat /tmp/gamegb-sessao3.txt /tmp/gamegb-sessao4.txt | grep -c "ERROR" || true)
grep -h ERROR /tmp/gamegb-sessao3.txt /tmp/gamegb-sessao4.txt || true; rm -f /tmp/gamegb-sessao3.txt /tmp/gamegb-sessao4.txt
echo "    conexoes com erro: $erros_c de 2"

saida_q="$(rodar "$RAIZ/supabase/tests/concorrencia_conquista_confere.sql" 2>&1)" && ok_q=1 || ok_q=0
echo "$saida_q" | sed -n 's/^psql:[^ ]* //p' | grep -vE '^(DO|SET)' || true
if [ "$ok_q" != "1" ] || [ "$erros_c" != "0" ]; then
  ok_c=0
  saida_c="$saida_c
$saida_q"
fi

echo
if [ "$ok_c" = "1" ] && [ "$recusas" = "1" ]; then
  echo "TESTE DE ISOLAMENTO: PASSOU"
else
  echo "TESTE DE ISOLAMENTO: FALHOU (concorrencia)"
  echo "$saida_c" | grep -E 'ERROR|FALHOU' || true
  exit 1
fi
