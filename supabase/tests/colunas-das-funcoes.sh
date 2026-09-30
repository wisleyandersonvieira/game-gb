#!/usr/bin/env bash
# Toda coluna e tabela que uma função do banco usa EXISTE (30/09/2026).
#
# O Postgres só confere o que uma função plpgsql usa quando ela RODA: a função
# nasce sem erro e a tela quebra depois ("column e.fotoaguardaremocaoem does
# not exist", Quadro do master, 30/09/2026). Aqui o plpgsql_check lê TODAS as
# funções (inclusive as de gatilho, com a tabela de cada gatilho) e reprova
# qualquer coluna ou tabela que não existe.
#
# Sobe um Postgres descartável, aplica as migrações (ou, com BANCO=<container>
# já montado, usa ele) e confere.
#   bash supabase/tests/colunas-das-funcoes.sh
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
C="${BANCO:-gamegb-colunas}"

limpar() { [ -z "${BANCO:-}" ] && docker rm -f -v "$C" >/dev/null 2>&1 || true; }
trap limpar EXIT

rodar() {
  docker cp "$1" "$C:/x.sql" >/dev/null
  docker exec "$C" psql -U postgres -q -v ON_ERROR_STOP=1 -f /x.sql
}

if [ -z "${BANCO:-}" ]; then
  limpar
  # Na memória (--tmpfs), e sai com -v: não deixa nada no disco.
  docker run -d --name "$C" --tmpfs /var/lib/postgresql/data -e POSTGRES_PASSWORD=teste postgres:17 >/dev/null
  for _ in $(seq 1 60); do
    sleep 1
    prontos=$(docker logs "$C" 2>&1 | grep -c "ready to accept connections" || true)
    if [ "$prontos" -ge 2 ] && docker exec "$C" psql -U postgres -qtAc "select 1" >/dev/null 2>&1; then break; fi
  done
  rodar "$RAIZ/supabase/tests/_ambiente_local.sql" >/dev/null
  for m in "$RAIZ"/supabase/migrations/*.sql; do
    if ! rodar "$m" >/dev/null 2>&1; then echo "a migração $(basename "$m") não aplicou"; exit 1; fi
  done
fi

echo "==> instalando o plpgsql_check (o mesmo que o Supabase oferece)"
docker exec "$C" bash -c "apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq postgresql-17-plpgsql-check >/dev/null 2>&1"
docker exec "$C" psql -U postgres -qtAc "CREATE EXTENSION IF NOT EXISTS plpgsql_check" >/dev/null

cat > /tmp/colunas-das-funcoes.sql <<'SQL'
-- Cada função plpgsql do public; a de gatilho, com cada tabela em que ela está.
WITH alvos AS (
  SELECT p.oid, p.proname::text AS nome, 0::oid AS tabela, 1 AS tabelas, ARRAY[]::text[] AS transicao
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.prolang = (SELECT oid FROM pg_language WHERE lanname = 'plpgsql')
     AND p.prorettype <> 'trigger'::regtype
  UNION
  SELECT p.oid, p.proname::text || ' (gatilho ' || t.tgname || ')', t.tgrelid,
         (SELECT count(DISTINCT t2.tgrelid)::integer FROM pg_trigger t2 WHERE t2.tgfoid = p.oid),
         array_remove(ARRAY[t.tgoldtable::text, t.tgnewtable::text], NULL)
    FROM pg_trigger t JOIN pg_proc p ON p.oid = t.tgfoid JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE NOT t.tgisinternal AND n.nspname = 'public'
     AND p.prolang = (SELECT oid FROM pg_language WHERE lanname = 'plpgsql')
)
SELECT DISTINCT a.nome || ': ' || r.message
  FROM alvos a,
       LATERAL public.plpgsql_check_function_tb(a.oid, a.tabela, fatal_errors := false,
               other_warnings := false, performance_warnings := false, extra_warnings := false) r
 WHERE r.level = 'error'
   -- O que é do próprio Supabase (cofre de segredos, agendador, chamadas web)
   -- não existe no Postgres de teste: não é erro nosso.
   AND r.message !~ '"(vault\.[a-z_]+|cron\.[a-z_]+|net)"'
   -- Gatilho de VÁRIAS tabelas (escolhe o campo pelo nome da tabela, ex.
   -- autor_mudou): o campo que falta numa tabela é do ramo de outra.
   AND NOT (a.tabelas > 1 AND r.message ~ '^record "(new|old)" has no field')
   -- A tabela de transição (REFERENCING OLD TABLE AS ...) só existe no gatilho.
   AND NOT EXISTS (SELECT 1 FROM unnest(a.transicao) x WHERE r.message = format('relation "%s" does not exist', x))
 ORDER BY 1;
SQL
docker cp /tmp/colunas-das-funcoes.sql "$C:/colunas.sql" >/dev/null
erros="$(docker exec "$C" psql -U postgres -qtA -v ON_ERROR_STOP=1 -f /colunas.sql)"

# Lista FECHADA do que já se sabe quebrado e tem conserto marcado. Cada linha
# que some do banco tem de sair daqui (a lista não guarda coisa velha).
# (Vazia desde o conserto de 30/09/2026, que apagou marcar_senha_trocada.)
CONHECIDAS=()
for k in ${CONHECIDAS[@]+"${CONHECIDAS[@]}"}; do
  if ! grep -qxF "$k" <<<"$erros"; then
    echo "::error::A lista de quebradas conhecidas tem uma linha que já não acontece; tire-a: $k"
    exit 1
  fi
  erros="$(grep -vxF "$k" <<<"$erros" || true)"
done
if [ -n "$erros" ]; then
  echo "::error::Função do banco usa coluna ou tabela que não existe:"
  echo "$erros"
  echo
  echo "O Postgres só descobre isso quando a função roda (a tela quebra no ar)."
  echo "O que fazer: crie a coluna numa migração nova, ou recrie a função sem ela."
  exit 1
fi
echo "Toda coluna e tabela usada pelas funções do banco existe."
