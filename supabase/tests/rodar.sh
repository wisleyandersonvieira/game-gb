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

echo "==> conferindo que nenhuma coluna apagada voltou numa migracao posterior"
if ! bash "$RAIZ/supabase/tests/colunas-apagadas.sh"; then
  echo
  echo "TESTE DE ISOLAMENTO: FALHOU (coluna apagada ressuscitada)"
  exit 1
fi

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

echo "==> colaborador pedindo resgate: dois toques, e estoque 1"
rodar "$RAIZ/supabase/tests/concorrencia_resgate_colab_preparo.sql" >/dev/null
docker cp "$RAIZ/supabase/tests/concorrencia_resgate_colab_sessao.sql" "$CONTAINER:/sessao_rc.sql" >/dev/null
# (a) a MESMA pessoa tocando duas vezes
docker exec "$CONTAINER" psql -U postgres -q -v pessoa=910 -v produto=910 -f /sessao_rc.sql >/tmp/gamegb-rc1.txt 2>&1 &
pa=$!
docker exec "$CONTAINER" psql -U postgres -q -v pessoa=910 -v produto=910 -f /sessao_rc.sql >/tmp/gamegb-rc2.txt 2>&1 &
pb=$!
wait "$pa" "$pb" || true
rc_a=0
for f in /tmp/gamegb-rc1.txt /tmp/gamegb-rc2.txt; do grep -q "ERROR" "$f" && rc_a=$((rc_a + 1)); done
echo "    dois toques: conexao recusada $rc_a de 2"
# (b) DUAS pessoas disputando o ultimo do estoque
docker exec "$CONTAINER" psql -U postgres -q -v pessoa=912 -v produto=911 -f /sessao_rc.sql >/tmp/gamegb-rc3.txt 2>&1 &
pc=$!
docker exec "$CONTAINER" psql -U postgres -q -v pessoa=913 -v produto=911 -f /sessao_rc.sql >/tmp/gamegb-rc4.txt 2>&1 &
pd=$!
wait "$pc" "$pd" || true
rc_b=0
for f in /tmp/gamegb-rc3.txt /tmp/gamegb-rc4.txt; do grep -q "ERROR" "$f" && rc_b=$((rc_b + 1)); done
echo "    estoque 1: conexao recusada $rc_b de 2"
grep -h ERROR /tmp/gamegb-rc1.txt /tmp/gamegb-rc2.txt /tmp/gamegb-rc3.txt /tmp/gamegb-rc4.txt || true
rm -f /tmp/gamegb-rc1.txt /tmp/gamegb-rc2.txt /tmp/gamegb-rc3.txt /tmp/gamegb-rc4.txt

saida_rc="$(rodar "$RAIZ/supabase/tests/concorrencia_resgate_colab_confere.sql" 2>&1)" && ok_rc=1 || ok_rc=0
echo "$saida_rc" | sed -n 's/^psql:[^ ]* //p' | grep -vE '^(DO|SET)' || true
if [ "$ok_rc" != "1" ] || [ "$rc_a" != "1" ] || [ "$rc_b" != "1" ]; then
  ok_c=0
  saida_c="$saida_c
$saida_rc"
fi

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

echo "==> dois feedbacks do mesmo dia ao mesmo tempo"
rodar "$RAIZ/supabase/tests/concorrencia_feedback_preparo.sql" >/dev/null
docker cp "$RAIZ/supabase/tests/concorrencia_feedback_sessao.sql" "$CONTAINER:/sessao_f.sql" >/dev/null
docker exec "$CONTAINER" psql -U postgres -q -f /sessao_f.sql >/tmp/gamegb-sessao5.txt 2>&1 &
p5=$!
docker exec "$CONTAINER" psql -U postgres -q -f /sessao_f.sql >/tmp/gamegb-sessao6.txt 2>&1 &
p6=$!
wait "$p5" "$p6" || true
duplicados=$(cat /tmp/gamegb-sessao5.txt /tmp/gamegb-sessao6.txt | grep -c "já tem feedback" || true)
rm -f /tmp/gamegb-sessao5.txt /tmp/gamegb-sessao6.txt
echo "    conexao recusada por feedback duplicado: $duplicados de 2"

saida_f="$(rodar "$RAIZ/supabase/tests/concorrencia_feedback_confere.sql" 2>&1)" && ok_f=1 || ok_f=0
echo "$saida_f" | sed -n 's/^psql:[^ ]* //p' | grep -vE '^(DO|SET)' || true
if [ "$ok_f" != "1" ] || [ "$duplicados" != "1" ]; then
  ok_c=0
  saida_c="$saida_c
$saida_f"
fi

echo "==> dois lancamentos da meta do dia ao mesmo tempo"
rodar "$RAIZ/supabase/tests/concorrencia_meta_preparo.sql" >/dev/null
docker cp "$RAIZ/supabase/tests/concorrencia_meta_sessao.sql" "$CONTAINER:/sessao_m.sql" >/dev/null
docker exec "$CONTAINER" psql -U postgres -q -v valor=1500 -f /sessao_m.sql >/tmp/gamegb-sessao7.txt 2>&1 &
p7=$!
docker exec "$CONTAINER" psql -U postgres -q -v valor=1600 -f /sessao_m.sql >/tmp/gamegb-sessao8.txt 2>&1 &
p8=$!
wait "$p7" "$p8" || true
erros_m=$(cat /tmp/gamegb-sessao7.txt /tmp/gamegb-sessao8.txt | grep -c "ERROR" || true)
grep -h ERROR /tmp/gamegb-sessao7.txt /tmp/gamegb-sessao8.txt || true
rm -f /tmp/gamegb-sessao7.txt /tmp/gamegb-sessao8.txt
echo "    conexoes com erro: $erros_m de 2"

saida_m="$(rodar "$RAIZ/supabase/tests/concorrencia_meta_confere.sql" 2>&1)" && ok_m=1 || ok_m=0
echo "$saida_m" | sed -n 's/^psql:[^ ]* //p' | grep -vE '^(DO|SET)' || true
if [ "$ok_m" != "1" ] || [ "$erros_m" != "0" ]; then
  ok_c=0
  saida_c="$saida_c
$saida_m"
fi

echo "==> duas ciencias do mesmo comunicado ao mesmo tempo"
rodar "$RAIZ/supabase/tests/concorrencia_ciencia_preparo.sql" >/dev/null
docker cp "$RAIZ/supabase/tests/concorrencia_ciencia_sessao.sql" "$CONTAINER:/sessao_ci.sql" >/dev/null
docker exec "$CONTAINER" psql -U postgres -q -f /sessao_ci.sql >/tmp/gamegb-sessao9.txt 2>&1 &
p9=$!
docker exec "$CONTAINER" psql -U postgres -q -f /sessao_ci.sql >/tmp/gamegb-sessao10.txt 2>&1 &
p10=$!
wait "$p9" "$p10" || true
erros_ci=$(cat /tmp/gamegb-sessao9.txt /tmp/gamegb-sessao10.txt | grep -c "ERROR" || true)
rm -f /tmp/gamegb-sessao9.txt /tmp/gamegb-sessao10.txt
echo "    conexoes com erro: $erros_ci de 2"

saida_ci="$(rodar "$RAIZ/supabase/tests/concorrencia_ciencia_confere.sql" 2>&1)" && ok_ci=1 || ok_ci=0
echo "$saida_ci" | sed -n 's/^psql:[^ ]* //p' | grep -vE '^(DO|SET)' || true
if [ "$ok_ci" != "1" ] || [ "$erros_ci" != "0" ]; then
  ok_c=0
  saida_c="$saida_c
$saida_ci"
fi

echo "==> rotinas ao mesmo tempo (duas rodadas e o mesmo repasse de folga)"
rodar "$RAIZ/supabase/tests/concorrencia_rotina_preparo.sql" >/dev/null
docker cp "$RAIZ/supabase/tests/concorrencia_rotina_sessao.sql" "$CONTAINER:/sessao_r.sql" >/dev/null
docker exec "$CONTAINER" psql -U postgres -q -v pessoa=1202 -f /sessao_r.sql >/tmp/gamegb-sessao11.txt 2>&1 &
p11=$!
docker exec "$CONTAINER" psql -U postgres -q -v pessoa=1203 -f /sessao_r.sql >/tmp/gamegb-sessao12.txt 2>&1 &
p12=$!
wait "$p11" "$p12" || true
repasse=$(cat /tmp/gamegb-sessao11.txt /tmp/gamegb-sessao12.txt | grep -c "já foi passada" || true)
erros_r=$(cat /tmp/gamegb-sessao11.txt /tmp/gamegb-sessao12.txt | grep "ERROR" | grep -vc "já foi passada" || true)
grep -h ERROR /tmp/gamegb-sessao11.txt /tmp/gamegb-sessao12.txt | grep -v "já foi passada" || true
rm -f /tmp/gamegb-sessao11.txt /tmp/gamegb-sessao12.txt
echo "    conexao recusada por repasse duplicado: $repasse de 2; outros erros: $erros_r"

saida_r="$(rodar "$RAIZ/supabase/tests/concorrencia_rotina_confere.sql" 2>&1)" && ok_r=1 || ok_r=0
echo "$saida_r" | sed -n 's/^psql:[^ ]* //p' | grep -vE '^(DO|SET)' || true
if [ "$ok_r" != "1" ] || [ "$repasse" != "1" ] || [ "$erros_r" != "0" ]; then
  ok_c=0
  saida_c="$saida_c
$saida_r"
fi

echo "==> duas aprovacoes pelo Telegram ao mesmo tempo (validador e master)"
rodar "$RAIZ/supabase/tests/concorrencia_telegram_preparo.sql" >/dev/null
docker cp "$RAIZ/supabase/tests/concorrencia_telegram_sessao.sql" "$CONTAINER:/sessao_t.sql" >/dev/null
docker exec "$CONTAINER" psql -U postgres -q -v usuario=13002 -f /sessao_t.sql >/tmp/gamegb-sessao13.txt 2>&1 &
p13=$!
docker exec "$CONTAINER" psql -U postgres -q -v usuario=13000 -f /sessao_t.sql >/tmp/gamegb-sessao14.txt 2>&1 &
p14=$!
wait "$p13" "$p14" || true
ja_validada=$(cat /tmp/gamegb-sessao13.txt /tmp/gamegb-sessao14.txt | grep -c "ja_validada" || true)
erros_t=$(cat /tmp/gamegb-sessao13.txt /tmp/gamegb-sessao14.txt | grep -c "ERROR" || true)
grep -h ERROR /tmp/gamegb-sessao13.txt /tmp/gamegb-sessao14.txt || true
rm -f /tmp/gamegb-sessao13.txt /tmp/gamegb-sessao14.txt
echo "    conexao que encontrou a entrega ja aprovada: $ja_validada de 2; erros: $erros_t"

saida_t="$(rodar "$RAIZ/supabase/tests/concorrencia_telegram_confere.sql" 2>&1)" && ok_t=1 || ok_t=0
echo "$saida_t" | sed -n 's/^psql:[^ ]* //p' | grep -vE '^(DO|SET)' || true
if [ "$ok_t" != "1" ] || [ "$ja_validada" != "1" ] || [ "$erros_t" != "0" ]; then
  ok_c=0
  saida_c="$saida_c
$saida_t"
fi

echo "==> dois cliques em \"Eu aceito\" (missao da equipe) ao mesmo tempo"
rodar "$RAIZ/supabase/tests/concorrencia_missao_preparo.sql" >/dev/null
docker cp "$RAIZ/supabase/tests/concorrencia_missao_sessao.sql" "$CONTAINER:/sessao_m.sql" >/dev/null
docker exec "$CONTAINER" psql -U postgres -q -v usuario=14001 -f /sessao_m.sql >/tmp/gamegb-sessao15.txt 2>&1 &
p15=$!
docker exec "$CONTAINER" psql -U postgres -q -v usuario=14002 -f /sessao_m.sql >/tmp/gamegb-sessao16.txt 2>&1 &
p16=$!
wait "$p15" "$p16" || true
ja_pega=$(cat /tmp/gamegb-sessao15.txt /tmp/gamegb-sessao16.txt | grep -c "ja_pega" || true)
erros_m=$(cat /tmp/gamegb-sessao15.txt /tmp/gamegb-sessao16.txt | grep -c "ERROR" || true)
grep -h ERROR /tmp/gamegb-sessao15.txt /tmp/gamegb-sessao16.txt || true
rm -f /tmp/gamegb-sessao15.txt /tmp/gamegb-sessao16.txt
echo "    conexao que encontrou a missao ja pega: $ja_pega de 2; erros: $erros_m"

saida_m="$(rodar "$RAIZ/supabase/tests/concorrencia_missao_confere.sql" 2>&1)" && ok_m=1 || ok_m=0
echo "$saida_m" | sed -n 's/^psql:[^ ]* //p' | grep -vE '^(DO|SET)' || true
if [ "$ok_m" != "1" ] || [ "$ja_pega" != "1" ] || [ "$erros_m" != "0" ]; then
  ok_c=0
  saida_c="$saida_c
$saida_m"
fi

echo "==> revogar o aceite e entregar no mesmo instante (duas conexoes)"
rodar "$RAIZ/supabase/tests/concorrencia_revogar_preparo.sql" >/dev/null
docker cp "$RAIZ/supabase/tests/concorrencia_revogar_gestor.sql" "$CONTAINER:/rev_g.sql" >/dev/null
docker cp "$RAIZ/supabase/tests/concorrencia_revogar_tablet.sql" "$CONTAINER:/rev_t.sql" >/dev/null
docker exec "$CONTAINER" psql -U postgres -q -f /rev_g.sql >/tmp/gamegb-rev1.txt 2>&1 &
pr1=$!
docker exec "$CONTAINER" psql -U postgres -q -f /rev_t.sql >/tmp/gamegb-rev2.txt 2>&1 &
pr2=$!
wait "$pr1" "$pr2" || true
recusadas=$(cat /tmp/gamegb-rev1.txt /tmp/gamegb-rev2.txt | grep -c "ERROR" || true)
echo "    conexao recusada (uma das duas tem de perder): $recusadas de 2"
rm -f /tmp/gamegb-rev1.txt /tmp/gamegb-rev2.txt
saida_rv="$(rodar "$RAIZ/supabase/tests/concorrencia_revogar_confere.sql" 2>&1)" && ok_rv=1 || ok_rv=0
echo "$saida_rv" | sed -n 's/^psql:[^ ]* //p' | grep -vE '^(DO|SET)' || true
if [ "$ok_rv" != "1" ] || [ "$recusadas" != "1" ]; then
  echo "$saida_rv" | grep -E 'ERROR|FALHOU' || true
  ok_c=0
fi

echo "==> duas tentativas de acesso no mesmo instante (trava)"
rodar "$RAIZ/supabase/tests/concorrencia_trava_preparo.sql" >/dev/null
docker cp "$RAIZ/supabase/tests/concorrencia_trava_sessao.sql" "$CONTAINER:/sessao_t.sql" >/dev/null
docker exec "$CONTAINER" psql -U postgres -q -v origem=tablet-a -f /sessao_t.sql >/tmp/gamegb-trava1.txt 2>&1 &
t1=$!
docker exec "$CONTAINER" psql -U postgres -q -v origem=tablet-b -f /sessao_t.sql >/tmp/gamegb-trava2.txt 2>&1 &
t2=$!
wait "$t1" "$t2" || true
travadas=$(cat /tmp/gamegb-trava1.txt /tmp/gamegb-trava2.txt | grep -c "TRAVADA" || true)
echo "    conexao recusada pela trava: $travadas de 2"
rm -f /tmp/gamegb-trava1.txt /tmp/gamegb-trava2.txt

saida_t="$(rodar "$RAIZ/supabase/tests/concorrencia_trava_confere.sql" 2>&1)" && ok_t=1 || ok_t=0
echo "$saida_t" | sed -n 's/^psql:[^ ]* //p' | grep -vE '^(DO|SET|DELETE)' || true
if [ "$ok_t" != "1" ]; then
  echo
  echo "TESTE DE ISOLAMENTO: FALHOU (trava de tentativas)"
  echo "$saida_t" | grep -E 'ERROR|FALHOU' || true
  exit 1
fi

echo "==> bot do Telegram: chamada sem o segredo certo e recusada (401)"
if docker run --rm -v "$RAIZ/supabase/functions:/f" -w /f denoland/deno:2.1.4 \
     deno test --allow-env --no-check tests/ >/tmp/gamegb-deno.txt 2>&1; then
  echo "    $(grep -oE '[0-9]+ passed \| [0-9]+ failed' /tmp/gamegb-deno.txt | tail -1)"
else
  cat /tmp/gamegb-deno.txt
  ok_c=0
  saida_c="$saida_c
ERROR: teste do segredo do webhook FALHOU"
fi
rm -f /tmp/gamegb-deno.txt

echo
if [ "$ok_c" = "1" ] && [ "$recusas" = "1" ]; then
  echo "TESTE DE ISOLAMENTO: PASSOU"
else
  echo "TESTE DE ISOLAMENTO: FALHOU (concorrencia)"
  echo "$saida_c" | grep -E 'ERROR|FALHOU' || true
  exit 1
fi
