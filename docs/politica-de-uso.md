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
O sistema não envia mensagens, avisos nem notificações para o seu celular. Você abre quando quiser. Se algum dia a empresa passar a enviar mensagens por aplicativo, esta política será atualizada e comunicada antes.

4. **Fora do expediente**
A [EMPRESA] não espera que você use o sistema fora do seu horário de trabalho, em folgas, férias ou afastamentos. Se abrir nesses momentos, é por sua conta e não é tempo de trabalho.

5. **Isto não é registro de ponto**
O STGame não controla jornada. Os horários cadastrados servem apenas para organizar as tarefas do dia. O registro de ponto continua sendo feito da forma oficial da empresa.

6. **Fotos das tarefas**
A foto serve só para comprovar o serviço feito. Fotografe o serviço, não as pessoas. As fotos são guardadas por tempo limitado e depois apagadas automaticamente; o registro da tarefa e os pontos permanecem. Elas são vistas pela gestão e por você, nas suas próprias entregas.

7. **Seus documentos**
Holerites e outros documentos ficam disponíveis só para você e para a gestão, por links que expiram em poucos minutos. Cada abertura é registrada.

8. **Pontos e prêmios**
Os pontos são um reconhecimento pelo desempenho, concedido por liberalidade da [EMPRESA]. Não são salário, não substituem qualquer verba trabalhista e não geram direito adquirido. As regras podem mudar, e a mudança é comunicada com antecedência.
Pontos lançados por engano podem ser estornados, sempre com registro do motivo.

9. **Canal confidencial**
Você pode enviar um relato sem se identificar. O sistema não guarda quem enviou nem o horário exato, só o dia. Você recebe um protocolo para acompanhar.

10. **Seus dados**
A [EMPRESA] trata seus dados (nome, CPF, telefone, cargo, loja, tarefas, pontos e documentos) para gerenciar o trabalho e cumprir obrigações legais. Você pode pedir acesso, correção ou informações sobre esses dados pelo contato abaixo.

11. **Bom senso**
Não use o sistema para ofender colegas, registrar tarefa que não foi feita ou acessar dados de outra pessoa. Isso pode gerar medidas disciplinares.

12. **Dúvidas**
Fale com: [NOME DO RESPONSÁVEL] — [E-MAIL OU TELEFONE].

Ao dar ciência neste comunicado, você confirma que leu e entendeu estas regras.

---

## Estado da conferência (contra o que o sistema faz)

| Item | Situação |
|---|---|
| 6 — fotos apagadas automaticamente | ✅ Pronto (23/09/2026): prazo por conta em Configurações (`DIAS_GUARDAR_FOTO_ENTREGA`, padrão 180, mínimo 90), rotina diária que apaga só o arquivo e Edge Function `expurgo-fotos` que o remove do Storage. A entrega, os pontos e o histórico ficam; o Quadro mostra "foto removida por tempo". |
| 3 — nenhuma mensagem enviada | 🟨 Verdade com o Telegram desligado (padrão). Trava aprovada: ligar o bot exige publicar uma versão nova desta política e colher ciência de novo; sem 100% de ciência, o bot fica desligado. |
| 6 — quem vê a foto | ✅ Texto corrigido: gestão e a própria pessoa, nas entregas dela. |
| 10 — lista de dados | ✅ Telefone incluído. |
| 7 — links de poucos minutos, cada abertura registrada | ✅ Confere (5 minutos + registro obrigatório em `documentosacessos`). Documento de RH **não** entra no expurgo de fotos: tem regra própria. |
| 9 — só o dia, sem quem enviou | ✅ Confere (`denunciasanonimas` não tem coluna de autor e guarda só a data). |
| 8 — estorno com motivo registrado | ✅ Confere (livro `movimentospontos`, motivo obrigatório). |
| 2 — troca de senha e PIN no primeiro acesso | 🟨 Etapa 1.12, parte A. |
| 12 — responsável | ✅ Campo `CONTATO_PRIVACIDADE` em Configurações (grupo "Política de uso"), preenchido pelo master. |

## Versões
Cada mudança neste texto gera uma **versão nova**, publicada como comunicado. As ciências
antigas continuam guardadas, ligadas à versão que valia na época. A tela Equipe mostra quem
já deu ciência **na versão atual**.

**Revisão jurídica:** este texto não foi revisado por advogado. Antes de vender para outras
empresas (Etapa 2.0), ele deve passar por revisão trabalhista e de LGPD, junto com os termos
de uso e a política de privacidade do produto.
