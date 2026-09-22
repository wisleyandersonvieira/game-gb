# Tarefa: aplicar a nova marca STGame no sistema

O produto que era "Game GB" agora se chama **STGame**. Esta pasta traz tudo o que é preciso para aplicar a identidade visual no código. Veja `referencia-marca.png` para o resultado esperado do logo.

Antes de começar, leia `CLAUDE.md` e `docs/PLANO_MIGRACAO.md`, como sempre. Esta tarefa é só visual: **não mexa no banco, nas migrações, nas regras de isolamento nem na lógica.**

## O que tem nesta pasta

| Arquivo | Para quê |
|---|---|
| `logos/stgame-logo.svg` | Logo horizontal principal (fundos claros) |
| `logos/stgame-logo-negativo.svg` | Logo para fundo escuro (tema escuro, faixas azul-noite) |
| `logos/stgame-logo-mono.svg` | Logo em uma cor (impressão, PDFs, relatórios) |
| `logos/stgame-simbolo.svg` | Símbolo sozinho (menu recolhido, loading, avatar) |
| `logos/stgame-simbolo-branco.svg` | Símbolo para fundos escuros |
| `logos/stgame-wordmark.svg` | Só o nome, sem símbolo |
| `public/*` | favicon.svg, favicon.ico, apple-touch-icon.png, icon-192.png, icon-512.png |
| `stgame-theme.css` | Cores, fontes, raios e sombras da marca, prontos para Tailwind v4 |
| `referencia-marca.png` | Painel visual aprovado pelo Wisley |

## Passos (um commit pequeno por passo, em português)

1. **Arquivos.** Copie `logos/` para `src/assets/brand/` e o conteúdo de `public/` para `public/`, substituindo o favicon antigo.
2. **Fontes.** `bun add @fontsource/sora @fontsource/ibm-plex-sans @fontsource/ibm-plex-mono` e importe no ponto de entrada só os pesos usados: Sora 600, 700 e 800; IBM Plex Sans 400, 500 e 600; IBM Plex Mono 500.
3. **Tema.** Copie `stgame-theme.css` para `src/styles/` e importe no CSS principal, logo depois de `@import "tailwindcss"`. Se o projeto já usa variáveis estilo shadcn (`--primary`, `--background`, `--foreground`, `--muted`, `--border`, `--ring`, `--destructive`...), **aponte-as para os tokens da marca** em vez de criar um segundo sistema:
   - `--background` → `--stg-surface` · `--card`/`--popover` → `--stg-surface-raised`
   - `--foreground` → `--stg-ink` · `--muted-foreground` → `--stg-ink-muted`
   - `--primary` → `--stg-azul` · `--primary-foreground` → `--stg-on-azul`
   - `--accent` → `--stg-azul-soft` · `--border`/`--input` → `--stg-line` · `--ring` → `--stg-azul`
   - `--destructive` → `--stg-perigo`
   - Troque cores fixas espalhadas nos componentes (ex.: `bg-blue-600`, `#hex`) pelos tokens.
   - Confirme como o tema escuro é ativado no projeto (classe `.dark` ou outro seletor) e ajuste o seletor em `stgame-theme.css` se for diferente.
4. **Nome.** Troque "Game GB" por "STGame" em todo texto visível: `<title>`, cabeçalho, tela de login, menu, e-mails de convite, manifest e metadados. Escreva sempre `STGame`, junto, com "ST" e "G" maiúsculos. **Não** renomeie tabelas, pastas do repositório, a pasta `legado/` nem as variáveis de ambiente.
5. **Logo nas telas.**
   - Login e cadastro: `stgame-logo.svg` centralizado, com 40px de altura (versão negativa no tema escuro).
   - Barra lateral ou topo: logo horizontal com 28px de altura; com o menu recolhido, só o símbolo com 32px.
   - Painel `/admin`: mesmo logo do app.
   - Use `<img>` com `alt="STGame"`. Deixe em volta do logo um espaço livre de pelo menos 18px (em 64px de altura).
6. **Tipografia.** Títulos de tela e seção em `font-display` (Sora 600); todo o resto em `font-sans` (IBM Plex Sans); pontos, posições do ranking e colunas numéricas em `font-mono` com `tabular-nums`.
7. **Regras de cor.**
   - `azul` só em ação principal, link e item ativo do menu, ocupando no máximo cerca de 10% da tela. Texto sobre azul é `on-azul`, nunca `text-white` fixo.
   - `ouro` **só** para pontos, medalhas e 1º lugar do ranking. Chip de pontos: fundo `ouro-soft`, texto `ouro-ink`, com uma bolinha `ouro`.
   - Status da tarefa: pendente `azul-soft`/`azul`, aprovada `sucesso-soft`/`sucesso`, recusada `perigo-soft`/`perigo`, sempre com ícone ou palavra junto.
   - Foco do teclado: `outline` de 2px em `azul`, com `outline-offset: 2px`.
   - Ícones: Lucide, traço 1,75, 20px.
8. **Documentação.** Atualize o título do `CLAUDE.md` para "STGame" e registre em "Registro de decisões" do `docs/PLANO_MIGRACAO.md`: "22/09/2026 — produto renomeado para STGame; identidade visual aplicada (tokens em `src/styles/stgame-theme.css`)." Copie também esta pasta para `docs/marca/`, como referência.
9. **Verificação.** Rode `bun run build` sem erros. Abra o app nos temas claro e escuro e confira login, menu, ranking e loja de recompensas. Procure por "Game GB" e "GameGB" no `src/` e confirme que não sobrou nenhum.

## Ao terminar

Explique ao Wisley, em linguagem simples, o que mudou e o que ele deve abrir para conferir (quais telas, nos dois temas).
