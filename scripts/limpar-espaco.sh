#!/usr/bin/env bash
# Libera o espaço que é SEGURO liberar e diz quanto cada passo rendeu.
#
#   bun run limpar-espaco
#
# Só apaga o que se recria sozinho ou não serve para mais nada:
#   * bancos de teste descartáveis que ficaram para trás (Docker);
#   * containers de teste parados (gamegb-*, stgame-*);
#   * imagens soltas do Docker (sem nome, restos de atualização);
#   * saída do build (o próximo build recria);
#   * caches do bun e do npm (o próximo bun install recria);
#   * saídas temporárias dos testes em /tmp.
# NUNCA toca em código, migração, configuração, .git, node_modules, nas
# suas capturas (prints/) nem nos navegadores do Playwright.

set -uo pipefail
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

livre() { df -B1 --output=avail /workspaces | tail -1 | tr -d ' '; }
legivel() {
  awk -v b="${1:-0}" 'BEGIN {
    if (b < 0) b = 0
    split("bytes KB MB GB TB", u, " "); i = 1
    while (b >= 1024 && i < 5) { b /= 1024; i++ }
    s = (i == 1) ? sprintf("%d", b) : sprintf("%.1f", b)
    sub(/\./, ",", s); printf "%s %s", s, u[i] }'
}

inicio=$(livre)
passo() {   # passo "descrição" comando...
  local desc="$1"; shift
  local antes depois
  antes=$(livre)
  "$@" >/dev/null 2>&1 || true
  depois=$(livre)
  printf "  %-62s liberou %s\n" "$desc" "$(legivel $((depois - antes)))"
}

echo "Limpando o que é seguro limpar..."
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  parados() {
    docker ps -aq --filter status=exited --filter status=created | while read -r id; do
      nome=$(docker inspect --format '{{.Name}}' "$id" | sed 's#^/##')
      case "$nome" in gamegb-*|stgame-*) docker rm -v "$id" ;; esac
    done
  }
  passo "Containers de teste parados" parados
  # Só volumes ANÔNIMOS e sem uso (o padrão do Docker desde a versão 23):
  # um banco de teste rodando agora não é tocado.
  passo "Bancos de teste descartáveis que ficaram (volumes sem uso)" docker volume prune -f
  passo "Imagens soltas do Docker (sem nome)" docker image prune -f
else
  echo "  Docker não está rodando: pulei a parte do Docker."
fi
passo "Saída do build (.output, dist)" rm -rf "$RAIZ/.output" "$RAIZ/dist" "$RAIZ/.vinxi"
passo "Cache do bun" bun pm cache rm
if command -v npm >/dev/null 2>&1; then passo "Cache do npm" npm cache clean --force; fi
limpar_tmp() { rm -f /tmp/gamegb-*.txt; }
passo "Saídas temporárias dos testes (/tmp, outro disco)" limpar_tmp

fim=$(livre)
echo
echo "Total liberado: $(legivel $((fim - inicio))). Livre agora: $(legivel "$fim")."
