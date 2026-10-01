#!/usr/bin/env bash
# Nenhuma função do sistema liga o JIT do Postgres (01/10/2026, pedido do Wisley).
#
# O JIT compila a consulta antes de rodar quando a ESTIMATIVA de custo passa
# de um limite. Em consulta pequena com estimativa absurda, a compilação custa
# mais que a consulta: o resumo do mês do gerente levava 1.000 ms em vez de
# 15 ms. O padrão do JIT é da plataforma; aqui ele é LIGADO de propósito, no
# limite padrão do Postgres, para a trava não depender do que o Supabase usa.
#
# Recebe um banco com as migrações (e nada mais) e roda, registrando o plano
# de toda consulta que levou 5 ms ou mais (a mais rápida com JIT, na varredura,
# levou 28 ms), inclusive as de dentro das funções:
#   1. o teste de isolamento inteiro (as contas pequenas e variadas do teste);
#   2. o volume de loja real e cada tela do volume_medir.sql, uma vez.
# Reprova se algum plano de FUNÇÃO DO SISTEMA usou o JIT (as funções do
# próprio teste não contam). Conserto: SET jit = off na função (ver a migração
# 20261001200000). Os planos vão só para arquivos em /tmp (apagados no fim),
# nunca para o log do servidor (o log do Docker fica no disco).
#
#   bash supabase/tests/jit.sh <container com as migrações aplicadas>
set -uo pipefail
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
C="$1"
ISO=/tmp/gamegb-jit-isolamento.txt; VOL=/tmp/gamegb-jit-volume.txt
trap 'rm -f "$ISO" "$VOL"' EXIT
OPCOES="-c jit=on -c jit_above_cost=100000 -c session_preload_libraries=auto_explain -c auto_explain.log_min_duration=5 -c auto_explain.log_nested_statements=on -c auto_explain.log_analyze=on -c auto_explain.log_timing=off -c client_min_messages=log -c log_min_messages=panic"
rodar() { docker cp "$1" "$C:/$(basename "$1")" >/dev/null
          docker exec -e PGOPTIONS="$OPCOES $2" "$C" psql -U postgres -q -v ON_ERROR_STOP=1 -f "/$(basename "$1")"; }

rodar "$RAIZ/supabase/tests/isolamento.sql" "" > "$ISO" 2>&1 \
  || { echo "    FALHOU: o teste de isolamento nao rodou inteiro na passada do JIT"; grep -E "ERROR" "$ISO" | head -3; exit 1; }
docker cp "$RAIZ/supabase/tests/volume_semear.sql" "$C:/volume_semear.sql" >/dev/null
docker exec "$C" psql -U postgres -q -v ON_ERROR_STOP=1 -f /volume_semear.sql >/dev/null 2>&1 \
  || { echo "    FALHOU: nao deu para semear o volume de loja real"; exit 1; }
rodar "$RAIZ/supabase/tests/volume_medir.sql" "-c medir.vezes=1 -c medir.so_jit=sim" > "$VOL" 2>&1 \
  || { echo "    FALHOU: as telas nao rodaram na passada do JIT"; grep -E "ERROR|FALHOU" "$VOL" | head -3; exit 1; }

# As funções do sistema e as do próprio teste (criadas pelo isolamento.sql).
docker exec "$C" psql -U postgres -qtAc "SELECT json_agg(json_build_object('n', proname, 's', prosrc)) FROM pg_proc WHERE pronamespace = 'public'::regnamespace" > /tmp/gamegb-jit-funcoes.json
python3 - "$ISO" "$VOL" "$RAIZ/supabase/tests/isolamento.sql" <<'PY'
import json, re, sys
iso, vol, teste = sys.argv[1:4]
funcs = [(f['n'], re.sub(r'\s+', ' ', f['s'])) for f in json.load(open('/tmp/gamegb-jit-funcoes.json'))]
do_teste = set(re.findall(r'CREATE (?:OR REPLACE )?FUNCTION public\.([a-z_0-9]+)', open(teste).read()))
planos, achados, telas = 0, {}, 0
for nome in (iso, vol):
    t = open(nome, errors='replace').read()
    telas += t.count('mediana') if nome == vol else 0
    for b in t.split('LOG:  duration:')[1:]:
        planos += 1
        if not re.search(r'^JIT:', b, re.M):
            continue
        linhas = b.split('\n')[1:]
        q = []
        for l in linhas:
            l2 = l[11:] if l.startswith('Query Text:') else l
            if q and (re.match(r'^(Query Parameters:|\S.*\(cost=)', l) or l.startswith('psql:')):
                break
            q.append(l2)
        q = re.sub(r'\s+', ' ', ' '.join(q)).strip()
        donos = sorted({n for n, s in funcs if q[:300] and q[:300] in s and n not in do_teste})
        if donos:
            k = ', '.join(donos)
            achados[k] = achados.get(k, 0) + 1
open('/tmp/gamegb-jit-resultado.txt', 'w').write(json.dumps({'planos': planos, 'telas': telas, 'achados': achados}))
PY
r="$(cat /tmp/gamegb-jit-resultado.txt)"; rm -f /tmp/gamegb-jit-resultado.txt /tmp/gamegb-jit-funcoes.json
planos=$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['planos'])" "$r")
telas=$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['telas'])" "$r")
achados=$(python3 -c "import json,sys; a=json.loads(sys.argv[1])['achados']; print('\n'.join(f'      {v} plano(s): {k}' for k, v in sorted(a.items())))" "$r")
if [ "$planos" -lt 200 ] || [ "$telas" -lt 20 ]; then
  echo "    FALHOU: a trava do JIT nao olhou o bastante ($planos planos, $telas telas): esta olhando o lugar errado"; exit 1
fi
if [ -n "$achados" ]; then
  echo "    FALHOU: funcao do sistema ligando o JIT (compila mais do que roda; ponha SET jit = off nela):"
  echo "$achados"; exit 1
fi
echo "    ok  nenhuma funcao do sistema liga o JIT: teste de isolamento e $telas telas com volume ($planos planos de 5 ms ou mais, JIT ligado no limite padrao)"
