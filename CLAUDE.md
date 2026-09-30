# STGame: instruções para o Claude Code

**Produto multi-empresa (SaaS)**, chamado **STGame** (antes "Game GB"), de gamificação e gestão de lojas: tarefas com pontos, validação de entregas, ranking, loja de recompensas, metas, agenda, escala, RH e estoque. Ele nasceu do sistema da loja Gela Boca (Python + SQL Server + Tkinter + bot do Telegram) e está sendo reconstruído como aplicação web vendida para várias empresas.

**Sempre leia `docs/PLANO_MIGRACAO.md` antes de começar.** Ele define as fases, a ordem e o que já foi feito. Ao terminar um item, marque o checkbox, atualize a tabela "Status geral" e registre decisões novas em "Registro de decisões".

## Modelo de negócio (a regra mais importante)
- **Administrador geral:** somente o login `wisley_anderson@hotmail.com`, reconhecido no banco pela função `eh_admin_geral()`. Ele acessa `/admin`, cadastra as contas (clientes) e define `limitelojas`. Não vê os dados operacionais dos clientes.
- **Conta = cliente = usuário master.** Cada login pertence a uma única conta (`contasusuarios`). O master acessa `/gestao` e o app.
- **Lojas** pertencem a uma conta, e cada conta tem no máximo `contas.limitelojas` lojas ativas.
- **Funcionários e tarefas** são da conta. Um funcionário pode estar em várias lojas (`funcionarioslojas`) e uma tarefa pode valer em várias lojas (`tarefaslojas`).
- **Isolamento total entre contas:** nenhum dado de uma conta pode ser lido ou alterado por outra.

## Regras de isolamento (obrigatórias em todo código novo)
- **Toda** tabela de dados tem `contaid NOT NULL` com padrão `minha_conta()`. As tabelas de nível loja têm também `lojaid`. Consulte a classificação conta/loja em `docs/DICIONARIO_BANCO.md`.
- **Única exceção: tabela da PLATAFORMA**, que não pertence a conta nenhuma e é só do admin geral (hoje: `redes`). Ela entra na lista declarada na seção 14 do teste de isolamento, que confere que toda policy dela é só `eh_admin_geral()`. Não use a exceção para dado de cliente.
- **Nunca recrie uma função que foi apagada de propósito.** Antes de copiar "a versão mais recente", procure também `DROP FUNCTION ... <nome>` depois dela (em 27/09/2026 `conta_por_codigo`, apagada por dizer o nome da empresa a quem tivesse o código, quase voltou assim; o teste de isolamento pegou).
- **Toda** tabela tem RLS com `contaid = minha_conta()`. **Nunca** crie policy `USING (true)`.
- O front-end **nunca** envia `contaid`, e nunca confie em `contaid` vindo do navegador. O banco preenche e confere.
- FKs entre tabelas precisam garantir a mesma conta (ex.: um funcionário só pode ser ligado a lojas da própria conta). Use triggers ou FKs compostas (`contaid`, id).
- Unicidades são **por conta ou por loja**, nunca globais (ex.: `UNIQUE (contaid, nomegrupo)`).
- Arquivos no Storage ficam em `<contaid>/<lojaid>/...`, com policies por pasta.
- Toda migração passa pelo **teste de isolamento** (duas contas; A não lê, altera nem apaga nada de B) antes de ir para o Supabase.
- A chave `service_role` só existe em variável de servidor (nunca `VITE_`) e só é usada em funções de servidor para tarefas de admin (convites).
- **Funções SQL nascem sem permissão para ninguém** (negadas por padrão desde a Etapa 1.6). Toda função nova precisa de `GRANT EXECUTE ... TO authenticated` explícito na própria migração. Função `security definer` que recebe `contaid` ou `lojaid` como parâmetro **nunca** é liberada: ela é interna, chamada só por outra função que confere quem pediu. O teste de isolamento reprova qualquer exceção.
- O visitante sem login (`anon`) só chama `painel_da_tv` e não lê nenhuma tabela.
- **Usuários gerenciais (permissão por cargo e loja, `docs/MAPA_PERMISSOES.md`):** toda operação de gestão nova confere a permissão **no banco**, com `pode('<codigo do catálogo>', loja)`, e o código entra em `catalogo_de_permissoes()`. A trava estrutural (seção 91 do teste de isolamento) reprova qualquer função que grava, liberada para quem está logado, que não chame `pode(...)` nem esteja numa lista fechada — e toda tabela com escrita direta fora de uma lista fechada. Permissão nova nasce negada para todo cargo. Esconder o botão não é permissão.
- **QUEM NÃO PODE VER UM VALOR NÃO PODE GRAVÁ-LO** (regra geral do Wisley, 30/09/2026, vale para toda operação futura com R$). Sem "Ver valores em R$" (`valores.ver_rs`) na loja, ninguém grava valor em R$ nela: pagamento e valor da agenda, abate em comanda, lançamento de venda, e o que vier. A seção 114 do teste de isolamento reprova função liberada que receba valor em R$ (parâmetro `numeric` `p_valor...`) sem conferir `pode('valores.ver_rs', loja)` — fora a lista fechada das que são só do master.
- **`user_metadata` do Supabase Auth (tema, nome de exibição) é editável pelo próprio usuário.** Serve só para preferências de exibição. **Nunca** use esses dados em policies, funções de permissão ou qualquer decisão de acesso. O teste de isolamento reprova policy ou função que os leia.
- O canal confidencial só pode ser lido pelo master da conta. Nenhum papel futuro (gerente, líder) terá acesso. A entrada é só pelo servidor, sem identificar quem envia, e nenhum log pode guardar o texto junto com quem mandou.

## Stack
- React 19 + TanStack Start/Router (rotas por arquivo em `src/routes/`) + TanStack Query + Tailwind v4
- Supabase (Postgres, Auth, Storage). Cliente em `src/integrations/supabase/client.ts`, que lê do `.env`
- Gerenciador de pacotes: **bun** (`bun install`, `bun run dev` → http://localhost:8080, `bun run build`)
- Migrações: `supabase/migrations/*.sql` (Supabase CLI)

## Estrutura
- `src/routes/admin/*` é o painel do administrador geral. `src/routes/_authenticated/*` são as telas do master (gestão e app). O seletor de loja ativa fica no topo.
- `legado/` é o sistema antigo em Python, **só para consulta**. Use-o como referência de regra de negócio. Nunca o execute nem o edite.
  - `legado/database.py` tem todas as consultas e regras (pontos, saldo, validação, metas).
  - `legado/main.py` é o painel desktop do gestor (14 abas).
  - `legado/api_server.py` + `legado/templates/painel.html` + `legado/static/js/painel.js` são o painel web antigo.
  - `legado/telegram_bot.py`, `legado/agendador*.py` são o bot e as rotinas: a especificação da Etapa 1.13.
  - `legado/config.py` tem parâmetros. **Contém segredos: nunca copie valores dele.**
- `docs/SEGREDOS.md` lista todo segredo e endereço obrigatório (só nomes, nunca valores). Segredo novo entra lá na mesma entrega.
- `docs/DICIONARIO_BANCO.md` tem as tabelas, as colunas, os relacionamentos e o nível conta/loja de cada tabela.

## Regras do banco
- Banco limpo: nenhum dado do sistema antigo é importado.
- Nomes originais do SQL Server **em minúsculas, sem aspas, sem underscores** (`FuncionarioID` → `funcionarioid`). Nomes novos seguem o mesmo padrão (`contaid`, `lojaid`, `limitelojas`).
- Chaves primárias `integer GENERATED BY DEFAULT AS IDENTITY` (não UUID), exceto `userid` do Supabase Auth.
- Datas em `timestamptz`, fuso `America/Sao_Paulo`.
- **"Que dia é hoje" tem um lugar só: `hoje_da_conta(conta)`** (hora do servidor + fuso da conta, de `fuso_da_conta`). Para saber em que dia caiu um instante: `dia_da_conta(conta, instante)`, ou, linha a linha, busque o fuso **uma vez** e use `dia_no_fuso(instante, fuso)` — buscar o fuso a cada linha deixa a consulta 15× mais lenta. Nas telas: `useHojeDaConta()` ou o `hoje`/`fuso` que a fila já traz, e `quandoFoi()` para escrever a hora ("ontem às 19h47"). **Nunca** `dia_em_sao_paulo`, fuso escrito à mão, `current_date` ou o relógio/fuso do aparelho em código novo. Duas catracas contam quem ainda decide sozinho (seção 68 do teste de isolamento e `src/ui/hoje-catraca.test.ts`) e reprovam se o número subir.
- Saldo de pontos em `funcionarios.saldopontos`, que é sempre a soma do livro `movimentospontos` (desde a Etapa 1.7).
- **Todo ponto que entra ou sai passa por `movimentospontos`, na mesma operação que altera o saldo. Nenhuma função futura (bônus de feedback, meta, nota fiscal, conquistas) pode mexer no saldo de outro jeito.** Na prática: grave o movimento, e o gatilho do livro atualiza `saldopontos`/`pontostotal`. Qualquer outro `UPDATE`/`INSERT` que mude o saldo é recusado pelo banco, até para o dono. Movimento nunca se altera nem se apaga: corrige-se com outro movimento. O teste de isolamento reprova qualquer caminho que altere o saldo sem gravar o movimento.
- **NINGUÉM GERA PONTOS PARA SI MESMO** (regra geral do Wisley, 29/09/2026, vale para tudo que vier depois). Quem dá pontos (registrar e aprovar entrega, feedback, ciência registrada por outro, comunicado com pontos, conquista, e qualquer bônus futuro) nunca pode ser o login ligado à pessoa que recebe. Hoje só o gerente pode ser as duas coisas (ligado à pessoa pelo usuário gerencial, `e_o_proprio`); o banco proíbe o master de ser pessoa da equipe (`contasusuarios_vinculo_do_papel`). Comunicado com pontos: quem publica fica fora dos destinatários, ninguém se inclui e ninguém dá pontos a um em que é destinatário. Todo caminho novo que dê pontos confere `e_o_proprio` e entra no teste (seção 110). O colaborador registrar a PRÓPRIA entrega é o fluxo normal: quem dá os pontos é quem aprova.
- Nada de IDs fixos no código: parâmetros e IDs especiais ficam em `configuracoes` (por conta).
- **Rotina acha tarefa pelo CÓDIGO interno (`tarefas.sistema`), nunca pelo nome** — o nome é editável. Rotina que não acha a tarefa (desativada ou apagada) **não falha em silêncio**: grava `avisossistema` tipo `rotina_sem_tarefa` (aparece no Início e na `/saude`). Rotina nova que passar a usar uma tarefa entra em `src/tarefas/rotinas.ts`, para a tela avisar antes de desativar. A seção 76 do teste de isolamento reprova função que procure tarefa pelo título.
- Toda mudança de estrutura é uma **nova** migração (nunca edite uma já aplicada). Depois dela, regenere `src/integrations/supabase/types.ts`.
- **Ao recriar uma função (`CREATE OR REPLACE`), parta da versão MAIS RECENTE dela**, não da primeira. Ache todas com `grep -rln "FUNCTION public.<nome>" supabase/migrations/`, copie a da migração de data mais alta, aplique só a sua mudança e **confira o `diff`** antes de fechar. Copiar uma versão antiga desfaz consertos e ressuscita colunas já apagadas — aconteceu duas vezes (23 e 25/09/2026). A verificação `supabase/tests/colunas-apagadas.sh` (roda no `rodar.sh` e no GitHub) barra o caso da coluna ressuscitada, mas ela não pega conserto de lógica desfeito: o `diff` é seu.
- Operações com pontos ou saldo são atômicas, em funções SQL (RPC).
- **Tempo das telas é teste** (pedido do Wisley, 29/09/2026): `supabase/tests/volume_medir.sql` mede cada tela com volume de loja real (`volume_semear.sql`), para o master e o gerente, e reprova acima de 1,5 s ou com a lista principal vazia. Tela nova de gestão entra nele.
- **Toda migração que mexe em COMPORTAMENTO é provada por comparação exaustiva, não com "testei e funcionou"** (regra do Wisley, 27/09/2026). Num Postgres de teste com dados realistas: grave a saída da função afetada ANTES, numa grade densa de entradas (ex.: a decisão do bot a cada 15 minutos, por 9 dias, para várias pessoas e turnos), aplique a migração (duas vezes, para provar que não duplica), recalcule e compare. O número de casos comparados e o de diferenças (tem de ser 0, ou cada diferença explicada e aprovada) vão no relatório da entrega e no plano. Foi assim na migração das jornadas: 38.925 decisões, 0 diferenças. Lembre o limite: a prova compara o que existe; o que muda quando alguém EDITAR depois (ex.: saída que era regra e virou valor escrito) é avaliado à parte.
- **Toda trava se prova reprovando, não só passando** (regra do Wisley, 28/09/2026). Trava é todo teste que existe para barrar um erro: catraca, lista fechada, verificação de isolamento, teste de regra. Ao criar ou mudar uma, **quebre de propósito** o que ela protege (uma leitura proibida num arquivo temporário, a regra antiga de volta, uma policy aberta) e mostre que ela **reprova**; depois desfaça e mostre que passa. Uma trava que nunca foi vista reprovando pode estar olhando para o lugar errado. O relatório da entrega diz o que foi quebrado e o que reprovou. Foi assim em 27/09/2026: uma leitura de `intervalosdomapa` num arquivo temporário fez `mapa-catraca.test.ts` reprovar. **Sabotagem que passa é sinal de teste incompleto, não de código correto** (29/09/2026): o "Em andamento" da TV montado por outra regra passou porque faltava no teste uma tarefa "pegou e já entregou" — o caso que a regra errada confunde. Quando uma sabotagem passar, acrescente ao teste o caso que falta até ela reprovar; nunca aceite a sabotagem como prova de que o código está certo. **E sabotagem que reprova pelo motivo errado também não prova nada** (29/09/2026): confira que ela abriu a porta DE VERDADE (a mudança aconteceu, o dado voltou) e que quem reprovou foi a checagem que ela mirava — se outra trava pegou antes, desligue essa outra de propósito e rode de novo.

**Teste de negação confere o RESULTADO, nunca o erro** (regra do Wisley, 29/09/2026). "Não deu erro" e "não aconteceu nada" são coisas diferentes: o banco pode recusar respondendo "0 linhas", sem erro. Negação de gravação: `guardar_foto()` antes e `exigir(nada_mudou(), ...)` depois (a foto é o banco inteiro, lido por cima das regras de acesso). Negação de leitura: `guardar_resultado(...)` e `exigir(nada_voltou(), ...)`. Continue pegando só os erros ESPERADOS, para um erro do próprio teste (nome errado) derrubar a rodada em vez de passar. A catraca `src/ui/negacao-catraca.test.ts` reprova qualquer `exigir(var)` em que `var` só marca "deu erro".

## Ordem de trabalho (decisões do Wisley)
- O plano tem **FASE 1 — Lançamento** (etapas 1.1 a 1.14) e **FASE 2 — Expansão** (etapas 2.1 a 2.3, adiada). Siga as etapas da Fase 1 **em ordem**.
- O registro de decisões e os commits antigos usam a numeração antiga ("Fase 7" = Etapa 1.7 etc.); a tabela de tradução está no topo do plano.
- **Stripe (Etapa 1.12) e Telegram/WhatsApp (Etapa 1.13) ficam para o fim da Fase 1.** Não implemente envio de mensagens nem cobrança antes disso. Mas já prepare o modelo: `contas.status`, `contas.limitelojas`.
- O **endurecimento** de segurança fica para a Etapa 1.14. O **isolamento entre contas não é opcional** e vale desde a Etapa 1.2.
- **Não construir nada da Fase 2 sem pedido explícito. As tabelas existem, mas ficam sem tela.** (Fase 2 = escala, mapa e pausas; estoque, incluindo nota fiscal pelo bot e "guardar mercadoria"; financeiro de lucro.)

## Padrões de código
- Interface **em português (pt-BR)**. Datas dd/mm/aaaa, moeda R$ (`Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' })`).
- Leitura com `useQuery`, escrita com `useMutation` + `invalidateQueries`. Inclua a loja ativa na `queryKey`.
- Componentes pequenos. Adicione cada tela nova ao menu.
- Antes de concluir, rode `bun run build` sem erros de TypeScript.

## O STGame não controla jornada
O sistema **não** acompanha entrada e saída de turno, e nenhuma tela mostra "quem está na loja agora". Isso é posição de produto, para reduzir risco trabalhista — a mesma razão de não existir notificação no aparelho pessoal.

Na prática: não construa contagem de presença, relógio de ponto, "na equipe agora" nem nada que se pareça, em tela nenhuma — e menos ainda na TV, que fica à vista de todos. Se um pedido levar a isso, diga antes de implementar. (Recusado em 25/09/2026, na faixa de números do rodapé da TV.)

O **Mapa da jornada** (Pessoas → Jornada → Mapa, 27/09/2026) é **planejamento de escala**, montado só com o cadastro: não olha a hora de agora, não destaca "a hora atual" e não vai para a TV. O **intervalo do mapa** (`intervalosdomapa`, "Intervalo (planejamento, não afeta o sistema)") é outro campo que o intervalo da jornada (silêncio do bot): **nenhuma regra do sistema pode lê-lo** — bot, tarefa, liberação, nota, rodízio. Só `mapa_da_jornada` e `salvar_intervalo_do_mapa`; a seção 75 do teste de isolamento e `src/jornada/mapa-catraca.test.ts` reprovam qualquer outra leitura. Se um dia ele precisar afetar algo, é decisão do Wisley, com prova de antes e depois.

## Espaço em disco do Codespace
- `bun run espaco` mostra quanto do disco está ocupado e por quem, do maior para o menor, sem apagar nada, e avisa quando o livre cai abaixo de 5 GB.
- `bun run limpar-espaco` libera o que é seguro (bancos de teste que sobraram, build, caches) e diz quanto cada passo rendeu.
- Todo Postgres descartável (teste, prova, medição) sobe com `--tmpfs /var/lib/postgresql/data` e sai com `docker rm -f -v`. Sem isso, cada um deixa ~51 MB no disco para sempre (em 28/09/2026 eram 220, 11 GB, e o Codespace encheu). Saídas de teste, capturas e PDFs de conferência vão para a pasta temporária (`/tmp`, outro disco), nunca para o projeto.

## Como fechar uma entrega (obrigatório)
Commit **não** é publicação: o Lovable publica do GitHub, e commit que não foi **enviado** não chega no ar. Isso já custou um dia de teste em 25/09/2026, com o Wisley procurando defeito numa tela que nunca tinha sido publicada.

A mensagem final de **toda** entrega diz, sempre, nesta ordem:
1. **`enviado ao GitHub: <commit>`** — enviado, não só commitado. Confira com `git status -sb` que não sobrou nada em `ahead`. **E as verificações do GitHub desse commit estão VERDES** (`gh run list --commit <commit>` / `gh run watch`), não só as locais: de 25 a 29/09/2026 a `main` ficou 51 rodadas vermelha (um `bun.lock` com um pacote que já tinha saído do `package.json`, e um comentário que a verificação lia como chamada), inclusive a versão no ar, e ninguém olhou — o "passou" era só local, com `node_modules` já instalado. Antes de enviar, rode os passos do `.github/workflows/verificacao.yml` numa cópia limpa do commit (sem `node_modules`), não só a suíte local.
2. **Quantas migrações** tem o arquivo de aplicar, qual é o nome dele, e a **CLASSIFICAÇÃO** (regra do Wisley, 29/09/2026), que vai também no cabeçalho do arquivo, na linha `-- CLASSIFICAÇÃO: ACRESCENTA` ou `-- CLASSIFICAÇÃO: TIRA`:
   - **ACRESCENTA:** o site que está no ar continua funcionando com o banco novo (só cria, ou muda sem tirar nada que a versão no ar usa). Ordem: **aplica o SQL primeiro, confere, e só então faz o merge**. Fazer o merge antes quebra o site novo até o SQL entrar (29/09/2026: o merge do PR #2 foi antes do SQL e o site novo ficou pedindo funções que ainda não existiam).
   - **TIRA:** apaga ou muda algo que a versão no ar usa. Aplica e publica **juntos, com as lojas fechadas**.
   Quem classifica é o Claude, olhando o que o site no ar chama; nunca deixe para o Wisley deduzir. `src/ui/classificacao.test.ts` reprova arquivo de aplicar novo sem a linha.
3. **O que o Wisley precisa fazer, na ordem** (aplicar o SQL → publicar → conferir).

Ele confere em `/saude` se a **versão no ar** é esse commit antes de testar qualquer coisa. A `/saude` mostra o commit e a hora do build, sem precisar de login.

**O conferidor (`supabase/conferir-o-banco.sql`) nunca manda rodar arquivo mais velho que o já aplicado** (29/09/2026: a linha 340 quase mandou reaplicar a barra antiga por cima da entrega seguinte). Toda entrega com migração entra nele com uma linha e com a data do arquivo na tabela `arquivos` (`src/ui/conferidor.test.ts` confere). Onde der, a conferência RODA a função (sem gravar) em vez de procurar texto no código. `supabase/tests/conferidor.sh` roda o conferidor de verdade no `rodar.sh`: num banco completo, toda linha tem de dar "ok".

E **nunca junte numa entrega o que não foi testado junto**: um `git add -A` já levou para o ar, sem querer, um conserto pela metade que um agente de revisão tinha começado. Antes de commitar, olhe o `git status` e confirme que cada arquivo mexido é seu.

## Como se comunicar com o Wisley
- Ele não é programador. Explique o que foi feito e o que testar em linguagem simples e passos curtos.
- Decisões de negócio, layout ou prioridade são dele: pergunte antes (veja "Decisões em aberto" no plano).
- Commits pequenos, em português, um por item do plano.
