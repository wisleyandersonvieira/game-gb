# Segredos e endereços obrigatórios do STGame

Lista única (28/09/2026). **Aqui só vão os NOMES, nunca os valores.** Os valores ficam no gerenciador de senhas do Wisley.

Todos são **do projeto inteiro**, um para a plataforma toda. **Nenhum se cadastra por cliente:** uma conta nova de cliente não pede segredo nenhum. Eles só precisam ser refeitos se o **projeto Supabase** for trocado (por exemplo, na mudança para São Paulo da Etapa 2.0) ou se o site for publicado em outro lugar.

Estão em três lugares diferentes. O nome muda de lugar para lugar: repare nas maiúsculas.

## 1. Lovable → Secrets (o servidor do site)

| Nome | Obrigatório? | Para que serve | A /saude avisa? |
|---|---|---|---|
| `STGAME_SERVICE_ROLE_KEY` | sim | Chave de administrador do banco, só no servidor (convites, tablet, celular). Vem de Supabase → Project Settings → API Keys → service_role. | sim |
| `STGAME_PIN_PEPPER` | sim | Embaralha PIN e senhas internas. No mínimo 16 caracteres. **Nunca trocar:** todos os acessos teriam de ser refeitos. | sim |
| `SITE_URL` | sim | Endereço do site, para o link do convite. | sim |
| `STGAME_SAUDE_CHAVE` | recomendado | Abre o detalhe da /saude sem login (`?chave=...`), para o dia em que ninguém consegue entrar. | — |

## 2. Supabase → Vault (o cofre do banco)

| Nome | Obrigatório? | Para que serve | Tem par? |
|---|---|---|---|
| `stgame_funcoes_url` | sim | Endereço das Edge Functions: `https://<id-do-projeto>.supabase.co/functions/v1` (sem nada depois do `v1`). | — |
| `stgame_expurgo_segredo` | sim | Senha com que o banco chama a função que apaga as fotos vencidas. | **igual** ao `STGAME_EXPURGO_SEGREDO` do item 3 |
| `stgame_fila_segredo` | só com o Telegram (Etapa 1.13) | Senha com que o banco chama a fila de mensagens. | **igual** ao `TELEGRAM_FILA_SEGREDO` do item 3 |

A /saude avisa quando um deles **não existe**. Ela **não consegue** saber se o par do item 3 está igual: isso se confere chamando a função (o passo a passo está no registro de 28/09/2026 do plano).

## 3. Supabase → Edge Functions → Secrets (as funções do servidor)

| Nome | Obrigatório? | Para que serve |
|---|---|---|
| `STGAME_EXPURGO_SEGREDO` | sim | O mesmo valor do `stgame_expurgo_segredo` do cofre. Mínimo 16 caracteres: com menos, a função recusa tudo. |
| `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` | automáticos | O Supabase já coloca. Não cadastrar. |
| `TELEGRAM_BOT_TOKEN`, `TELEGRAM_BOT_USERNAME`, `TELEGRAM_WEBHOOK_SECRET`, `TELEGRAM_FILA_SEGREDO` | só com o Telegram (Etapa 1.13) | O bot. `TELEGRAM_FILA_SEGREDO` é o par do `stgame_fila_segredo` do cofre. |

## 4. O que não é segredo, mas também é obrigatório

- **Extensões ligadas no Supabase** (Database → Extensions): `pg_cron`, `pg_net` e `supabase_vault`.
- **Agendamento `gamegb-rotinas`** (a cada 5 minutos), que a migração cria. A /saude avisa se faltar ou parar.
- **Edge Function `expurgo-fotos` publicada.** Se não estiver, a chamada de teste responde 404.
