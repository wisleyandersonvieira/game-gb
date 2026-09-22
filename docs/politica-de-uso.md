# Política de uso do sistema STGame

> **Modelo (texto do Wisley, 23/09/2026).** Vira um comunicado publicado em cada conta,
> com ciência obrigatória no primeiro acesso do colaborador (Etapa 1.12, parte A).
> Publicar sempre com **0 pontos de ciência**: ninguém ganha ponto por entrar.
> `[EMPRESA]` é preenchido com o nome da conta; o responsável do item 12 é preenchido
> pelo master. As pendências estão no fim do arquivo.

1. **O que é**
A [EMPRESA] usa o STGame para organizar as tarefas da loja, registrar entregas, acompanhar metas, comunicar avisos internos e premiar quem se destaca.

2. **Como você acessa**
Você entra com o seu CPF e uma senha pessoal. No tablet da loja, você usa um número (PIN) de 6 dígitos.
A senha e o PIN são pessoais e intransferíveis. Não empreste nem peça o de outra pessoa: tudo o que for feito com o seu número fica registrado no seu nome.
No primeiro acesso você troca os dois. Se esquecer, peça ao gestor para redefinir.

3. **Uso do seu celular é opcional**
Usar o seu aparelho é uma escolha sua. Tudo o que é obrigação do trabalho pode ser feito no tablet da loja, dentro do expediente.
O sistema não envia mensagens, avisos nem notificações para o seu celular. Você abre quando quiser.

4. **Fora do expediente**
A [EMPRESA] não espera que você use o sistema fora do seu horário de trabalho, em folgas, férias ou afastamentos. Se abrir nesses momentos, é por sua conta e não é tempo de trabalho.

5. **Isto não é registro de ponto**
O STGame não controla jornada. Os horários cadastrados servem apenas para organizar as tarefas do dia. O registro de ponto continua sendo feito da forma oficial da empresa.

6. **Fotos das tarefas**
A foto serve só para comprovar o serviço feito. Fotografe o serviço, não as pessoas. As fotos são guardadas por tempo limitado e vistas apenas pela gestão.

7. **Seus documentos**
Holerites e outros documentos ficam disponíveis só para você e para a gestão, por links que expiram em poucos minutos. Cada abertura é registrada.

8. **Pontos e prêmios**
Os pontos são um reconhecimento pelo desempenho, concedido por liberalidade da [EMPRESA]. Não são salário, não substituem qualquer verba trabalhista e não geram direito adquirido. As regras podem mudar, e a mudança é comunicada com antecedência.
Pontos lançados por engano podem ser estornados, sempre com registro do motivo.

9. **Canal confidencial**
Você pode enviar um relato sem se identificar. O sistema não guarda quem enviou nem o horário exato, só o dia. Você recebe um protocolo para acompanhar.

10. **Seus dados**
A [EMPRESA] trata seus dados (nome, CPF, cargo, loja, tarefas, pontos e documentos) para gerenciar o trabalho e cumprir obrigações legais. Você pode pedir acesso, correção ou informações sobre esses dados pelo contato abaixo.

11. **Bom senso**
Não use o sistema para ofender colegas, registrar tarefa que não foi feita ou acessar dados de outra pessoa. Isso pode gerar medidas disciplinares.

12. **Dúvidas**
Fale com: [NOME DO RESPONSÁVEL] — [E-MAIL OU TELEFONE].

Ao dar ciência neste comunicado, você confirma que leu e entendeu estas regras.

---

## Pendências antes de publicar (conferência contra o que o sistema faz hoje)

| Item | Situação | O que fazer |
|---|---|---|
| 6 — "guardadas por tempo limitado" | ❌ **Não é verdade hoje.** Não existe nenhum expurgo: a foto de entrega fica no Storage para sempre. | Criar a limpeza automática (rotina diária, prazo em `configuracoes`, ex.: 180 dias) **ou** tirar a frase. |
| 6 — "vistas apenas pela gestão" | ⚠️ Fica incompleto quando o colaborador vir as próprias entregas no celular. | Acrescentar "e por você, nas suas entregas". |
| 3 — "não envia mensagens nem notificações" | ⚠️ Verdade só com o Telegram desligado (padrão da 1.12). Se a conta ligar o bot, a frase deixa de valer. | O sistema deve recusar ligar o bot sem publicar uma versão nova da política. |
| 10 — lista de dados | ⚠️ Falta o telefone (`funcionarios.telefonewhatsapp`) e, se o bot for ligado, o Telegram. | Acrescentar "telefone". |
| 7 — links de poucos minutos, cada abertura registrada | ✅ Confere (5 minutos + registro obrigatório em `documentosacessos`). | — |
| 9 — só o dia, sem quem enviou | ✅ Confere (`denunciasanonimas` não tem coluna de autor e guarda só a data). | — |
| 8 — estorno com motivo registrado | ✅ Confere (livro `movimentospontos`, motivo obrigatório). | — |
| 2 — troca de senha e PIN no primeiro acesso | ✅ É o que a Etapa 1.12 parte A vai fazer. | — |
| 12 — responsável | Campo por conta. | Guardar em `configuracoes` (ex.: `CONTATO_PRIVACIDADE`). |

**Revisão jurídica:** este texto não foi revisado por advogado. Antes de vender para outras
empresas (Etapa 2.0), ele deve passar por revisão trabalhista e de LGPD, junto com os termos
de uso e a política de privacidade do produto.
