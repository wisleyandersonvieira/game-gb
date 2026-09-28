#!/usr/bin/env bash
# Mostra quanto do disco do Codespace está ocupado e por quem. NÃO apaga nada.
#
#   bun run espaco
#
# O disco do Codespace é um só para o projeto, o Docker e a pasta pessoal
# (/home). A pasta /tmp fica em OUTRO disco, bem maior: o que está lá não
# enche este.

set -uo pipefail
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 12345678 -> "11,8 MB"
legivel() {
  awk -v b="${1:-0}" 'BEGIN {
    split("bytes KB MB GB TB", u, " "); i = 1
    while (b >= 1024 && i < 5) { b /= 1024; i++ }
    s = (i == 1) ? sprintf("%d", b) : sprintf("%.1f", b)
    sub(/\./, ",", s); printf "%s %s", s, u[i] }'
}
# Tamanho de pastas, em bytes (0 se não existir).
tamanho() {
  local total=0 t
  for p in "$@"; do
    [ -e "$p" ] || continue
    t=$(du -sb "$p" 2>/dev/null | cut -f1)
    total=$((total + ${t:-0}))
  done
  echo "$total"
}
# "12.2GB" -> bytes
para_bytes() {
  awk -v s="$1" 'BEGIN {
    n = s + 0; u = s; gsub(/[0-9.]/, "", u)
    m = 1
    if (u == "kB" || u == "KB") m = 1000; else if (u == "MB") m = 1000^2
    else if (u == "GB") m = 1000^3; else if (u == "TB") m = 1000^4
    printf "%d", n * m }'
}

linhas=()
anota() { linhas+=("$1|$2|$3"); }   # bytes | o que é | pode limpar?

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  # Volumes sem uso: os bancos descartáveis dos testes que ficaram para trás.
  orfaos=0; n_orfaos=0
  while read -r nome links tam; do
    [ "$links" = "0" ] || continue
    orfaos=$((orfaos + $(para_bytes "$tam"))); n_orfaos=$((n_orfaos + 1))
  done < <(docker system df -v 2>/dev/null | awk '/^VOLUME NAME/{f=1; next} /^$/{f=0} f {print $1, $2, $3}')
  anota "$orfaos" "Docker: $n_orfaos bancos de teste descartáveis que ficaram para trás (volumes sem uso)" "sim"
  imagens=$(para_bytes "$(docker system df --format '{{.Type}} {{.Size}}' | awk '$1=="Images"{print $2}')")
  anota "$imagens" "Docker: imagens do Postgres e do Deno (usadas pelos testes)" "não (baixaria de novo)"
  parados=$(docker ps -aq --filter status=exited | wc -l)
  anota 0 "Docker: $parados containers parados (o peso está nos volumes acima)" "sim"
else
  anota 0 "Docker: não está rodando agora (não deu para medir)" "-"
fi

anota "$(tamanho "$RAIZ/node_modules")" "node_modules (bibliotecas do projeto)" "não (bun install recria)"
anota "$(tamanho "$HOME/.cache/ms-playwright")" "Navegadores do Playwright (conferência de tela)" "não (teria de baixar)"
anota "$(tamanho "$HOME/.bun/install/cache")" "Cache do bun" "sim"
anota "$(tamanho "$HOME/.npm")" "Cache do npm" "sim"
anota "$(tamanho "$RAIZ/.git")" "Histórico do Git (.git)" "não"
anota "$(tamanho "$RAIZ/.output" "$RAIZ/dist" "$RAIZ/.vinxi")" "Saída do build (.output, dist)" "sim (o build recria)"
anota "$(tamanho "$RAIZ/prints")" "prints/ (suas capturas de conferência, só nesta máquina)" "não (são suas)"
anota "$(tamanho "$HOME/.cache/copilot" "$HOME/.vscode-remote")" "Fora do projeto: VS Code e Copilot" "não (é do editor)"

# Arquivos grandes soltos no projeto (fora de node_modules e .git).
grandes=$(find "$RAIZ" \( -path "$RAIZ/node_modules" -o -path "$RAIZ/.git" \) -prune -o -type f -size +5M -printf '%s %P\n' 2>/dev/null | sort -rn)
soma_grandes=$(echo "$grandes" | awk '{s += $1} END {printf "%d", s}')
anota "$soma_grandes" "Arquivos grandes soltos no projeto (mais de 5 MB)" "ver lista"

# O limite do aviso: abaixo de 5 GB livres, o build e os testes começam a
# correr risco de travar no meio.
LIMITE=$(( ${ESPACO_LIMITE_GB:-5} * 1024 * 1024 * 1024 ))
livre=$(df -B1 --output=avail /workspaces | tail -1 | tr -d ' ')
aviso() {
  if [ "$livre" -lt "$LIMITE" ]; then
    echo "  ⚠ ATENÇÃO: só $(legivel "$livre") livres, abaixo do limite de ${ESPACO_LIMITE_GB:-5} GB."
    echo "    Rode agora: bun run limpar-espaco"
  else
    echo "  ✓ Espaço livre acima do limite de ${ESPACO_LIMITE_GB:-5} GB."
  fi
}

echo
echo "Disco do Codespace (projeto + Docker + /home):"
df -h /workspaces | awk 'NR==2 {printf "  tamanho %s · ocupado %s (%s) · livre %s\n", $2, $3, $5, $4}'
aviso
echo
echo "Quem ocupa, do maior para o menor:"
printf '%s\n' "${linhas[@]}" | sort -t'|' -k1,1 -rn | while IFS='|' read -r b oque limpa; do
  printf "  %10s  %s  (limpar: %s)\n" "$(legivel "$b")" "$oque" "$limpa"
done
if [ -n "$grandes" ]; then
  echo
  echo "Arquivos grandes soltos:"
  echo "$grandes" | while read -r b nome; do printf "  %10s  %s\n" "$(legivel "$b")" "$nome"; done
fi
echo
echo "O resto do disco é o próprio sistema do Codespace (Linux, ferramentas): não dá para limpar."
echo "Para liberar o que é seguro: bun run limpar-espaco"
# Repete no fim, onde o olho para depois da tabela.
[ "$livre" -lt "$LIMITE" ] && { echo; aviso; }
exit 0
