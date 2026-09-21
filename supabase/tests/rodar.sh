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
for _ in $(seq 1 30); do
  sleep 2
  docker exec "$CONTAINER" pg_isready -U postgres >/dev/null 2>&1 && break
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
  rodar "$m" >/dev/null && echo "ok"
done

echo "==> teste de isolamento entre contas"
saida="$(rodar "$RAIZ/supabase/tests/isolamento.sql" 2>&1)" && ok=1 || ok=0
echo "$saida" | sed -n 's/^psql:[^ ]* //p' | grep -vE '^(DO|SET|INSERT|CREATE|RESET)' || true

echo
if [ "$ok" = "1" ]; then
  echo "TESTE DE ISOLAMENTO: PASSOU"
else
  echo "TESTE DE ISOLAMENTO: FALHOU"
  echo "$saida" | grep -E 'ERROR|FALHOU' || true
  exit 1
fi
