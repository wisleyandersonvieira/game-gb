#!/usr/bin/env bash
# Trava (01/10/2026, pedido do Wisley): os segredos do servidor NUNCA chegam
# ao navegador. A STGAME_SERVICE_ROLE_KEY passa por cima de todas as regras de
# acesso; o STGAME_PIN_PEPPER resume PIN, códigos e CPF da trava.
#
# 1. O BUILD, com valores-isca: monta o site com cada segredo valendo uma isca
#    (e também a variante VITE_, que o Vite embute no navegador por desenho) e
#    procura as iscas em TODO arquivo gerado. Em .output/public (o que vai para
#    o navegador) é vazamento; em .output/server, é segredo embutido no pacote
#    publicado (também não pode: ele tem de ser lido só na hora, do ambiente).
# 2. O CÓDIGO: só os arquivos da lista fechada leem esses segredos do ambiente,
#    e nenhum arquivo usa um nome VITE_ para eles.
#
# Roda todas as conferências e reprova se qualquer uma falhar.
#   bash scripts/segredos-fora-do-navegador.sh
set -uo pipefail
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$RAIZ"

SEGREDOS=(STGAME_SERVICE_ROLE_KEY SUPABASE_SERVICE_ROLE_KEY STGAME_PIN_PEPPER STGAME_SAUDE_CHAVE)
# Quem pode ler cada segredo do ambiente (todos são do servidor).
declare -A LEITORES=(
  [STGAME_SERVICE_ROLE_KEY]="src/integrations/supabase/client.server.ts src/servidor/acesso.ts"
  [SUPABASE_SERVICE_ROLE_KEY]="src/integrations/supabase/client.server.ts src/servidor/acesso.ts"
  [STGAME_PIN_PEPPER]="src/servidor/segredos.ts src/servidor/acesso.ts"
  [STGAME_SAUDE_CHAVE]="src/servidor/acesso.ts"
)
falhou=0

# --- 1. O build com iscas -----------------------------------------------------
declare -A ISCA
envs=()
for s in "${SEGREDOS[@]}"; do
  ISCA[$s]="ISCA${RANDOM}${RANDOM}X${s}X$(date +%s%N)"
  envs+=("$s=${ISCA[$s]}" "VITE_$s=${ISCA[$s]}")
done
rm -rf .output
if ! env "${envs[@]}" bun run build >/tmp/segredos-build.log 2>&1; then
  echo "FALHOU: o build com as iscas nao terminou (veja /tmp/segredos-build.log)"; exit 1
fi
[ -d .output/public ] || { echo "FALHOU: o build nao gerou .output/public (a trava estaria olhando o lugar errado)"; exit 1; }
nnav=$(find .output/public -type f | wc -l)
[ "$nnav" -gt 10 ] || { echo "FALHOU: so $nnav arquivos em .output/public (a trava estaria olhando o lugar errado)"; exit 1; }
for s in "${SEGREDOS[@]}"; do
  nav=$(grep -rlF "${ISCA[$s]}" .output/public || true)
  srv=$(grep -rlF "${ISCA[$s]}" .output/server || true)
  if [ -n "$nav" ]; then echo "FALHOU: o valor de $s foi parar em arquivo que VAI PARA O NAVEGADOR:"; echo "$nav" | head -5; falhou=1; fi
  if [ -n "$srv" ]; then echo "FALHOU: o valor de $s foi embutido no pacote do servidor (tem de ser lido do ambiente, na hora):"; echo "$srv" | head -5; falhou=1; fi
done
[ $falhou = 0 ] && echo "ok  build com iscas: nenhum segredo em nenhum dos $nnav arquivos do navegador, nem no pacote do servidor"
rm -rf .output

# --- 2. O código ----------------------------------------------------------------
for s in "${SEGREDOS[@]}"; do
  for f in $(grep -rlE "(process\.env|import\.meta\.env)\s*(\[\s*['\"]|\.)$s\b" src --include=*.ts --include=*.tsx | grep -v '\.test\.ts$' || true); do
    if [[ " ${LEITORES[$s]} " != *" $f "* ]]; then
      echo "FALHOU: $f le o segredo $s do ambiente (so pode: ${LEITORES[$s]})"; falhou=1
    fi
  done
  vite=$(grep -rnE "VITE_$s\b" src vite.config.ts --include=*.ts --include=*.tsx 2>/dev/null | grep -v '\.test\.ts:' || true)
  if [ -n "$vite" ]; then echo "FALHOU: nome VITE_$s no codigo (variavel VITE_ vai para o navegador por desenho):"; echo "$vite" | head -3; falhou=1; fi
done
[ $falhou = 0 ] && echo "ok  codigo: so os arquivos do servidor da lista leem os segredos; nenhum nome VITE_ para eles"

exit $falhou
