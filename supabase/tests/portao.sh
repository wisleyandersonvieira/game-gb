#!/usr/bin/env bash
# O PORTÃO do WhatsApp com o PostgREST DE VERDADE (06/10/2026, obrigatório).
#
# Quem tiver a nossa chave de assinatura fabrica um token de SERVIDOR. A
# migração 20261006100000 faz o banco, pela API, aceitar dessa chave só os
# formatos A e B (portao.antes_de_cada_pedido). Esta trava sobe um Postgres
# com todas as migrações e o PostgREST nas versões em uso, assina tokens com
# uma chave "nossa" e outra "do Supabase" (as duas nascem aqui e morrem no
# fim) e confere a resposta de cada pedido.
#
# O teste de isolamento (seção 122) prova a DECISÃO; esta prova que o PostgREST
# entrega o cabeçalho do token à função antes de cada pedido. Se ele chegar
# vazio (relato do PostgREST #2855), o servidor fabricado passa e esta trava
# reprova. Sabotagem: PORTAO_SABOTAGEM=<arquivo.sql> aplica o arquivo por
# último.
#
# Saída: 0 = tudo como esperado nas duas versões; 1 = alguma resposta errada.
set -uo pipefail
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERSOES="${PORTAO_VERSOES:-v12.2.12 v13.0.7}"
PG="gamegb-portao-pg"; RS="gamegb-portao-rest"
DIR="$(mktemp -d /tmp/portao-XXXX)"
limpar() { docker rm -f -v "$PG" "$RS" >/dev/null 2>&1 || true; rm -rf "$DIR"; }
trap limpar EXIT
limpar; DIR="$(mktemp -d /tmp/portao-XXXX)"

# As duas chaves (ES256) e a lista pública que o PostgREST confere.
NOSSA_KID="$(bun "$RAIZ/supabase/tests/portao-tokens.ts" chave "$DIR" nossa)"
bun "$RAIZ/supabase/tests/portao-tokens.ts" chave "$DIR" supabase >/dev/null
[ -n "$NOSSA_KID" ] && [ -s "$DIR/supabase.publica.json" ] || { echo "    PAROU: as chaves do teste nao foram geradas"; exit 2; }
python3 -c "import json,sys; d=sys.argv[1]; json.dump({'keys':[json.load(open(f'{d}/{n}.publica.json')) for n in ('supabase','nossa')]}, open(f'{d}/jwks.json','w'))" "$DIR"

docker run -d --name "$PG" -p 127.0.0.1::3000 --tmpfs /var/lib/postgresql/data -e POSTGRES_PASSWORD=teste postgres:17 >/dev/null
for _ in $(seq 1 60); do
  sleep 1
  prontos=$(docker logs "$PG" 2>&1 | grep -c "ready to accept connections" || true)
  if [ "$prontos" -ge 2 ] && docker exec "$PG" psql -U postgres -qtAc "select 1" >/dev/null 2>&1; then break; fi
done
rodar() { docker cp "$1" "$PG:/x.sql" >/dev/null; docker exec "$PG" psql -U postgres -q -v ON_ERROR_STOP=1 -f /x.sql; }
rodar "$RAIZ/supabase/tests/_ambiente_local.sql" >/dev/null
# O papel do PostgREST existe ANTES das migrações, como no Supabase: assim a
# própria migração do portão é que liga a função antes de cada pedido.
docker exec "$PG" psql -U postgres -qc "CREATE ROLE authenticator LOGIN NOINHERIT PASSWORD 'portao'; GRANT anon, authenticated, service_role TO authenticator;" >/dev/null
for m in "$RAIZ"/supabase/migrations/*.sql; do rodar "$m" >/dev/null 2>&1 || { echo "    FALHOU: a migracao $(basename "$m") nao aplicou"; exit 1; }; done
# Só do teste: o papel do formato B (no ar, ele nasce na fatia 2) e a nossa chave registrada.
docker exec "$PG" psql -U postgres -qc "CREATE ROLE wa_porteiro NOLOGIN; GRANT wa_porteiro TO authenticator; GRANT USAGE ON SCHEMA portao TO wa_porteiro; GRANT EXECUTE ON FUNCTION portao.antes_de_cada_pedido() TO wa_porteiro; INSERT INTO portao.chavesproprias (kid, motivo) VALUES ('$NOSSA_KID', 'teste portao.sh');" >/dev/null
ligado="$(docker exec "$PG" psql -U postgres -qtAc "SELECT count(*) FROM pg_db_role_setting d JOIN pg_roles r ON r.oid = d.setrole, unnest(d.setconfig) s WHERE r.rolname = 'authenticator' AND s = 'pgrst.db_pre_request=portao.antes_de_cada_pedido'")"
[ "$ligado" = 1 ] || { echo "    FALHOU: a migracao nao ligou a funcao antes de cada pedido no PostgREST"; exit 1; }
if [ -n "${PORTAO_SABOTAGEM:-}" ]; then rodar "$PORTAO_SABOTAGEM" >/dev/null || { echo "    PAROU: a sabotagem nao aplicou"; exit 2; }; echo "    SABOTAGEM aplicada: $(head -1 "$PORTAO_SABOTAGEM")"; fi
PORTA="$(docker port "$PG" 3000/tcp | head -1 | sed 's/.*://')"

falhou=0
U=aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa
pede() { # rotulo chave tipo esperado(200|recusado|negado)
  local h=() tok cod corpo
  if [ "$2" != "-" ]; then tok="$(bun "$RAIZ/supabase/tests/portao-tokens.ts" token "$DIR" "$2" "$3" "$U")"; h=(-H "Authorization: Bearer $tok"); fi
  cod="$(curl -s -o "$DIR/r.json" -w '%{http_code}' -X POST "localhost:$PORTA/rpc/painel_da_tv" -H 'Content-Type: application/json' -d '{"p_codigo":"x"}' "${h[@]}")"
  corpo="$(head -c 200 "$DIR/r.json")"
  case "$4" in
    200)      [ "$cod" = 200 ] ;;
    recusado) [ "$cod" = 403 ] && echo "$corpo" | grep -q '"message":"Token recusado."' ;;
    negado)   [ "$cod" = 403 ] && ! echo "$corpo" | grep -q 'Token recusado' ;;
  esac
  if [ $? = 0 ]; then printf '    ok  %-48s %s\n' "$1" "$cod"; else printf '    FALHOU: %-44s %s %s\n' "$1" "$cod" "$corpo"; falhou=1; fi
}
for V in $VERSOES; do
  docker rm -f "$RS" >/dev/null 2>&1 || true
  docker run -d --name "$RS" --network "container:$PG" \
    -e PGRST_DB_URI="postgres://authenticator:portao@localhost:5432/postgres" -e PGRST_DB_SCHEMAS=public \
    -e PGRST_DB_ANON_ROLE=anon -e PGRST_JWT_SECRET="$(cat "$DIR/jwks.json")" "postgrest/postgrest:$V" >/dev/null || { echo "    FALHOU: sem a imagem do PostgREST $V"; falhou=1; continue; }
  for _ in $(seq 1 90); do
    sleep 1; c="$(curl -s -o /dev/null -w '%{http_code}' "localhost:$PORTA/")"
    [ "$c" != 503 ] && [ "$c" != 000 ] && break
  done
  echo "    PostgREST $V"
  pede "sem token (visitante)"                   -        -                  200
  pede "chave do Supabase: servidor"             supabase servidor           200
  pede "chave do Supabase: login comum"          supabase comum              200
  pede "nossa chave: formato A"                  nossa    A                  200
  pede "nossa chave: formato B (passa o portao)" nossa    B                  negado
  pede "nossa chave: SERVIDOR fabricado"         nossa    servidor           recusado
  pede "nossa chave: servidor com a marca"       nossa    servidor_com_marca recusado
  pede "nossa chave: formato A de 1 hora"        nossa    A_longo            recusado
  pede "nossa chave: login sem a marca"          nossa    sem_marca          recusado
done
exit $falhou
