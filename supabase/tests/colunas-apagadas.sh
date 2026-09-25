#!/usr/bin/env bash
# Nenhuma migração pode ressuscitar coluna que outra já apagou.
#
# Por que existe: duas vezes eu recriei uma função copiando uma versão ANTIGA
# dela, e junto voltaram colunas que uma migração posterior tinha apagado
# (funcionarios.senhaprovisoria, em 25/09/2026). O banco só reclama na hora de
# rodar a função, então o defeito passava despercebido até alguém usar a tela.
#
# Regra: se a migração N apaga a coluna X, nenhuma migração DEPOIS da N pode
# mencionar X — a não ser que ela mesma volte a criar a coluna (ADD COLUMN X).
set -uo pipefail
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MIGS=$(ls "$RAIZ"/supabase/migrations/*.sql | sort)
problemas=0

for m in $MIGS; do
  for col in $(grep -oE "DROP COLUMN( IF EXISTS)? [a-z_]+" "$m" | awk '{print $NF}' | sort -u); do
    for depois in $MIGS; do
      [ "$depois" \> "$m" ] || continue
      # A migração pode recriar a coluna de propósito: aí não é ressurreição.
      grep -qE "ADD COLUMN( IF NOT EXISTS)? $col\b" "$depois" && continue
      # Tira o que está entre aspas antes de procurar: 'senhahash' como NOME
      # de campo num jsonb_build_object não é a coluna senhahash.
      achou=$(sed "s/'[^']*'/''/g" "$depois" | grep -nE "(^|[^a-z_])$col([^a-z_]|\$)" | head -3)
      if [ -n "$achou" ]; then
        echo "::error::$(basename "$depois") menciona '$col', que $(basename "$m") apagou:"
        echo "$achou" | sed 's/^/    /'
        problemas=$((problemas + 1))
      fi
    done
  done
done

if [ "$problemas" -gt 0 ]; then
  echo
  echo "Coluna apagada voltou em migração posterior ($problemas ocorrência(s))."
  echo "Quase sempre é uma função recriada a partir de uma versão ANTIGA dela."
  echo "O que fazer: pegue a versão MAIS RECENTE da função (a última migração"
  echo "que a define), aplique só a sua mudança em cima dela e confira o diff."
  exit 1
fi
echo "Nenhuma coluna apagada voltou em migração posterior."
