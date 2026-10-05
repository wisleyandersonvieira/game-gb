#!/usr/bin/env bash
# A ferramenta de sabotagem (01/10/2026, pedido do Wisley).
#
# "Toda trava se prova reprovando": a sabotagem reabre UMA porta e o teste tem
# de reprovar. Cinco vezes uma sabotagem passou pelo motivo errado; na última,
# a ferramenta apontava para o arquivo da entrega ANTERIOR e a migração nova
# tapava a porta antes do teste rodar — a sabotagem "passava" sem nunca ter
# aberto nada. Esta ferramenta confere a mira e PARA COM ERRO antes de dizer
# qualquer coisa sobre o teste.
#
# A sabotagem é um arquivo .sql que começa com a linha
#   -- ALVO: <arquivo da migração que ela desmonta>
# e recria as funções da migração com o defeito de propósito.
#
#   bash supabase/tests/sabotar.sh <sabotagem.sql> [--entrega-anterior] [--trava jit] [--desligar '<texto exato de uma linha do teste>']...
#
# Antes de montar o banco, PARA se:
#   1. o ALVO não é uma migração DESTA entrega (está na origin/main). Para
#      sabotar de propósito uma trava de entrega anterior, passe
#      --entrega-anterior (o relatório diz isso);
#   2. o ALVO não é a versão MAIS RECENTE de cada função sabotada (uma
#      migração posterior a recria e tapa a porta).
# Depois de montar (todas as migrações e a sabotagem POR ÚLTIMO), PARA se:
#   3. a sabotagem não mudou as funções no banco (a porta não abriu).
# Só então roda o teste de isolamento (numa cópia; --desligar troca uma linha
# do teste por um comentário, para provar que a checagem SEGUINTE também pega),
# ou, com --trava jit, roda supabase/tests/jit.sh (isolamento e telas com volume).
#
# Saída: 0 = uma checagem REPROVOU (FALHOU: a trava pegou; diz qual);
#        1 = o teste PASSOU (sabotagem não pega: o teste está incompleto);
#        2 = parou: a mira está errada, ou o teste quebrou com outro erro
#            antes de alguma checagem reprovar (nada foi provado).
set -uo pipefail
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$RAIZ"
C="gamegb-sabotagem"
SAB="${1:-}"; shift || true
ANTERIOR=0; DESLIGAR=(); TRAVA=isolamento
while [ $# -gt 0 ]; do
  case "$1" in
    --entrega-anterior) ANTERIOR=1 ;;
    --desligar) shift; DESLIGAR+=("$1") ;;
    --trava) shift; TRAVA="$1" ;;
    *) echo "PAROU: opcao desconhecida $1"; exit 2 ;;
  esac
  shift
done
parar() { echo "PAROU (a mira esta errada, nada foi provado): $*"; exit 2; }
[ -f "$SAB" ] || parar "sabotagem nao encontrada: $SAB"

ALVO="$(sed -n 's/^-- ALVO: *\([^ ]*\.sql\).*/\1/p' "$SAB" | head -1)"
[ -n "$ALVO" ] || parar "a sabotagem nao diz o ALVO (primeira linha: -- ALVO: <migracao>.sql)"
[ -f "supabase/migrations/$ALVO" ] || parar "o ALVO $ALVO nao existe em supabase/migrations"

# 1. O ALVO é desta entrega?
git fetch -q origin main 2>/dev/null || true
if git cat-file -e "origin/main:supabase/migrations/$ALVO" 2>/dev/null; then
  if [ "$ANTERIOR" = 1 ]; then
    echo "AVISO: o ALVO $ALVO e de uma entrega anterior (de proposito, --entrega-anterior)"
  else
    parar "o ALVO $ALVO ja esta na main: e de uma entrega ANTERIOR. Mire a migracao desta entrega (ou passe --entrega-anterior, de proposito)"
  fi
fi

# 2. O ALVO é a versão mais recente de cada função sabotada?
FUNCOES="$(grep -oiE '(CREATE (OR REPLACE )?|ALTER )FUNCTION public\.[a-z_0-9]+' "$SAB" | sed -E 's/.*public\.//' | sort -u)"
[ -n "$FUNCOES" ] || parar "a sabotagem nao recria nem altera nenhuma funcao"
for f in $FUNCOES; do
  ultima="$(grep -liE "(CREATE (OR REPLACE )?FUNCTION|ALTER FUNCTION) public\.$f *\(" supabase/migrations/*.sql | sort | tail -1)"
  [ "$(basename "$ultima")" = "$ALVO" ] \
    || parar "a versao mais recente de $f esta em $(basename "$ultima"), nao no ALVO $ALVO: essa migracao recriaria a funcao por cima da sabotagem"
done

# Monta o banco: todas as migrações e a sabotagem por último.
limpar() { docker rm -f -v "$C" >/dev/null 2>&1 || true; }
trap limpar EXIT
limpar
docker run -d --name "$C" --tmpfs /var/lib/postgresql/data -e POSTGRES_PASSWORD=teste postgres:17 >/dev/null
for _ in $(seq 1 60); do
  sleep 1
  prontos=$(docker logs "$C" 2>&1 | grep -c "ready to accept connections" || true)
  if [ "$prontos" -ge 2 ] && docker exec "$C" psql -U postgres -qtAc "select 1" >/dev/null 2>&1; then break; fi
done
rodar() { docker cp "$1" "$C:/x.sql" >/dev/null; docker exec "$C" psql -U postgres -q -v ON_ERROR_STOP=1 -f /x.sql; }
rodar supabase/tests/_ambiente_local.sql >/dev/null
for m in supabase/migrations/*.sql; do rodar "$m" >/dev/null 2>&1 || parar "a migracao $(basename "$m") nao aplicou"; done
lista="$(echo "$FUNCOES" | sed "s/.*/'&'/" | paste -sd,)"
impressao="SELECT md5(string_agg(p.oid::regprocedure::text || p.prosrc || coalesce(array_to_string(p.proconfig, ','), ''), '|' ORDER BY p.oid::regprocedure::text)) FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname IN ($lista)"
antes="$(docker exec "$C" psql -U postgres -qtAc "$impressao")"
rodar "$SAB" >/dev/null 2>&1 || parar "a sabotagem nao aplicou"
depois="$(docker exec "$C" psql -U postgres -qtAc "$impressao")"
# 3. A porta abriu de verdade?
[ "$antes" != "$depois" ] || parar "a sabotagem nao mudou nada no banco (as funcoes ficaram iguais): a porta nao abriu"
echo "mira conferida: ALVO $ALVO; funcoes sabotadas no banco: $(echo $FUNCOES)"

if [ "$TRAVA" = jit ]; then
  saida="$(bash supabase/tests/jit.sh "$C" 2>&1)"; rc=$?
  if [ "$rc" != 0 ]; then echo "REPROVOU (a trava pegou):"; echo "$saida" | head -4; exit 0; fi
  echo "PASSOU: a sabotagem nao foi pega ($saida). O teste esta incompleto."; exit 1
fi
[ "$TRAVA" = isolamento ] || parar "trava desconhecida: $TRAVA"

# O teste, numa cópia (com as linhas desligadas, se pedido).
COPIA="$(mktemp /tmp/isolamento-sabotagem-XXXX.sql)"
cp supabase/tests/isolamento.sql "$COPIA"
for d in "${DESLIGAR[@]+"${DESLIGAR[@]}"}"; do
  n="$(grep -cF -- "$d" "$COPIA")"
  [ "$n" = 1 ] || { rm -f "$COPIA"; parar "--desligar precisa casar com exatamente 1 linha do teste (casou com $n): $d"; }
  # Desliga o COMANDO inteiro a que a linha pertence (do PERFORM ao ";"), não
  # só a linha: um comando de várias linhas cortado ao meio quebraria o SQL.
  python3 - "$COPIA" "$d" <<'PY'
import sys
p, d = sys.argv[1], sys.argv[2]
t = open(p).read()
i = t.index(d)
ini = t.rfind('PERFORM ', 0, i)
ini = t.rfind('\n', 0, ini) + 1
fim = t.index(';', i) + 1
open(p, 'w').write(t[:ini] + '    -- (desligado de proposito pela sabotagem)' + t[fim:])
PY
  echo "desligado de proposito no teste: $d"
done
saida="$(rodar "$COPIA" 2>&1)"; rc=$?
rm -f "$COPIA"
if [ "$rc" != 0 ]; then
  erro="$(echo "$saida" | grep -E 'ERROR' | head -1 | sed 's/^psql:[^ ]* //')"
  # Só uma checagem que reprovou (FALHOU) prova a trava. Outro erro (o teste
  # quebrou, a sabotagem derrubou o preparo) não prova nada.
  if ! echo "$erro" | grep -q "FALHOU:"; then
    echo "PAROU (o teste quebrou antes de alguma checagem reprovar; nada foi provado): $erro"; exit 2
  fi
  echo "REPROVOU (a trava pegou): $erro"
  exit 0
fi
echo "PASSOU: a sabotagem nao foi pega. O teste esta incompleto (nao a sabotagem provada)."
exit 1
