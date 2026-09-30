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

A /saude avisa quando um deles **não existe**, e desde 30/09/2026 mostra a **resposta** da última chamada à função: 401 = o par do item 3 não está igual; 404 = a função não está publicada.

## 3. Supabase → Edge Functions → Secrets (as funções do servidor)

| Nome | Obrigatório? | Para que serve |
|---|---|---|
| `STGAME_EXPURGO_SEGREDO` | sim | O mesmo valor do `stgame_expurgo_segredo` do cofre. Mínimo 16 caracteres: com menos, a função recusa tudo. |
| `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` | automáticos | O Supabase já coloca. Não cadastrar. |
| `TELEGRAM_BOT_TOKEN`, `TELEGRAM_BOT_USERNAME`, `TELEGRAM_WEBHOOK_SECRET`, `TELEGRAM_FILA_SEGREDO` | só com o Telegram (Etapa 1.13) | O bot. `TELEGRAM_FILA_SEGREDO` é o par do `stgame_fila_segredo` do cofre. |

## Passo a passo: o apagamento das fotos (30/09/2026)

**Nenhum valor passa pelo chat nem pelo seu teclado:** a senha é sorteada dentro do próprio banco e copiada uma única vez, do resultado do SQL Editor para o campo do segredo da função.

1. **Extensões.** Supabase → Database → Extensions: `pg_net`, `pg_cron` e `supabase_vault` ligadas (a /saude diz se falta alguma).
2. **O que já existe no cofre** (mostra só o nome e o tamanho, nunca o valor). SQL Editor → New query:
   ```sql
   select name, length(decrypted_secret) as tamanho, created_at
     from vault.decrypted_secrets where name like 'stgame_%';
   ```
   Se `stgame_funcoes_url` ou `stgame_expurgo_segredo` já aparecer, **pare e chame o Claude** (o passo 3 daria erro de nome repetido, e o valor antigo pode estar errado).
3. **Criar os dois segredos do cofre** (a senha é sorteada aqui, 64 caracteres):
   ```sql
   select vault.create_secret('https://asgdynxdcdnjglgyyaek.supabase.co/functions/v1',
                              'stgame_funcoes_url', 'Endereço das Edge Functions do STGame');
   select vault.create_secret(replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', ''),
                              'stgame_expurgo_segredo', 'Senha com que o banco chama a função expurgo-fotos');
   ```
   (O endereço não é segredo: é o do projeto, o mesmo que o site usa.)
4. **Ler a senha UMA vez** para copiá-la para a função:
   ```sql
   select decrypted_secret from vault.decrypted_secrets where name = 'stgame_expurgo_segredo';
   ```
   Copie o valor (64 caracteres, sem espaço). Não cole em nenhum outro lugar além do passo 5 (e, se quiser, do seu gerenciador de senhas).
5. **O segredo da função:** Supabase → Edge Functions → Secrets → Add new secret. Name: `STGAME_EXPURGO_SEGREDO` (maiúsculas). Value: o que você copiou. Save. Depois, feche a aba do SQL Editor com o resultado.
6. **A função está publicada?** Supabase → Edge Functions → Functions: tem de aparecer `expurgo-fotos`. Se **não** aparecer, pare e chame o Claude: publicar a função é um passo à parte (ela precisa ir com "Verify JWT" desligado).
7. **Disparar e conferir:** no SQL Editor, `select public.fotos_expurgo_disparar();` (uma chamada apaga até 5.000 fotos). Espere 5 minutos e abra a /saude: a linha "Última chamada à função que apaga" tem de dizer **respondeu OK: apagou N**. 401 = o segredo do passo 5 não é igual ao do cofre (refaça o 4 e o 5); 404 = a função não está publicada (passo 6).

## 4. O que não é segredo, mas também é obrigatório

- **Extensões ligadas no Supabase** (Database → Extensions): `pg_cron`, `pg_net` e `supabase_vault`.
- **Agendamento `gamegb-rotinas`** (a cada 5 minutos), que a migração cria. A /saude avisa se faltar ou parar.
- **Edge Function `expurgo-fotos` publicada.** Se não estiver, a chamada de teste responde 404.
- **Os 7 buckets do Storage existem e são PRIVADOS** (`entregas`, `agendamentos`, `documentos-rh`, `administracao`, `logos-redes`, `notas-fiscais`, `layout-loja`). A /saude confere e a faixa do /admin avisa (01/10/2026). Bucket público: qualquer link que vazou abre sem login, para sempre.

## 5. Conferência mensal, na mão (sem token nenhum) — 01/10/2026

O que o banco não enxerga e a /saude não confere. Uma vez por mês, no painel do Supabase:

**Authentication → URL Configuration**
- [ ] *Site URL* = o endereço do site (o mesmo do `SITE_URL`). Errado: o convite e a troca de senha levam a lugar errado.
- [ ] *Redirect URLs* contém `<endereço do site>/definir-senha`. Sem ele: o link do convite e o de "esqueci a senha" não abrem a página certa.

**Authentication → Sign In / Providers → Email**
- [ ] *Allow new users to sign up*: o site NÃO usa cadastro aberto (todo login é criado pelo servidor). Se estiver ligado, avise o Claude antes de desligar.
- [ ] *Email OTP Expiration* = 86400 (24 horas, o máximo; decisão do convite de 30/09/2026).

**Authentication → Email Templates**
- [ ] *Invite user* e *Reset password* com o texto em português que foi combinado (não o padrão em inglês).

**Edge Functions → Functions**
- [ ] `expurgo-fotos` aparece, com *Verify JWT* DESLIGADO. A data de atualização é igual ou posterior à da última mudança no repositório: **27/09/2026** (commit `2a9549e`). Anterior a isso: a versão publicada é velha — publique de novo.
- [ ] (Só com o Telegram, Etapa 1.13) `telegram-webhook` e `telegram-fila`, *Verify JWT* desligado; última mudança no repositório: 22/09/2026.

**Edge Functions → Secrets**
- [ ] `STGAME_EXPURGO_SEGREDO` existe (o valor não aparece; se o par estiver errado, a /saude mostra "respondeu 401").

A data de cada função no repositório muda quando ela muda: a lista acima é atualizada na mesma entrega.
