# Rascunho: Termos de Uso e Política de Privacidade

> **RASCUNHO PARA REVISÃO JURÍDICA. Não publicar sem revisão de advogado.**
> Escrito a partir do que o sistema faz hoje (setembro de 2026). Os trechos entre colchetes `[ ]` precisam ser preenchidos ou decididos.
> `[PRODUTO]` = nome do produto (ainda não escolhido). `[EMPRESA]` = razão social e CNPJ de quem vende o sistema.

---

## Nota para o advogado: como o sistema trata dados

**O que é:** um sistema na internet (SaaS) de gestão de lojas e gamificação de equipes: tarefas com pontos, validação de entregas com foto, ranking, loja de prêmios, metas de venda, agenda de eventos com clientes, comunicados, documentos pessoais de RH (holerites, atestados), onboarding e um canal confidencial de denúncias.

**Quem usa:**
- **Cliente:** a empresa que contrata. Hoje, só o responsável da empresa (usuário "master") faz login.
- **Funcionários do cliente:** têm os dados cadastrados pelo cliente. Hoje não fazem login; no futuro vão interagir por um bot de Telegram/WhatsApp.
- **Clientes finais do cliente:** pessoas que agendam eventos (nome, CPF, telefone).

**Papéis na LGPD (proposta):**

| Dados | Controlador | Operador |
|---|---|---|
| Funcionários do cliente (nome, CPF, telefone, cargo, folgas, afastamentos, fotos de tarefas, documentos pessoais, feedbacks) | **O cliente** (a empresa contratante) | **[EMPRESA]** |
| Clientes finais da agenda (nome, CPF, telefone, observações) | **O cliente** | **[EMPRESA]** |
| Relatos do canal confidencial | **O cliente** | **[EMPRESA]** |
| Cadastro do próprio cliente (razão social, e-mail e telefone do responsável, dados de cobrança, registros de acesso ao sistema) | **[EMPRESA]** | — |

**Pontos sensíveis:**
- **Documentos pessoais:** holerites, atestados, contratos e documentos de identidade. Atestados podem conter **dado de saúde**, que é dado sensível (art. 11 da LGPD).
- **Onde ficam os arquivos:** em armazenamento privado. São abertos só pelo responsável da conta, com link que vale 5 minutos, e cada acesso é registrado.
- **Canal confidencial:** o sistema **não guarda quem enviou** (nem login, nem telefone, nem hora; só o dia). Só o responsável da conta lê. O texto pode citar terceiros.
- **Isolamento:** nenhum cliente vê dados de outro. O administrador da plataforma **não vê os dados operacionais** dos clientes: só o cadastro da empresa e a situação da assinatura.
- **CPF e telefone** nunca aparecem no painel de TV da loja nem no resumo inicial.

**Suboperadores (a confirmar na contratação):**

| Fornecedor | Para quê | País |
|---|---|---|
| Supabase | Banco de dados, login e arquivos | Produção prevista em São Paulo (sa-east-1); ambiente de teste nos EUA, sem dados reais |
| [Hospedagem: Cloudflare/Netlify/Vercel] | Servir o site | Rede mundial (EUA) |
| Stripe | Cobrança | Brasil/EUA |
| [Resend] | Envio de e-mails de convite e senha | EUA |
| [Telegram/WhatsApp (Z-API)] | Mensagens | Futuro (Etapa 1.13) |

Vários ficam fora do Brasil: é preciso cláusula de **transferência internacional** (art. 33).

**Retenção que o sistema já pratica:**
- O livro de pontos nunca se apaga (é contábil).
- O registro de acesso a documentos pessoais não é apagado pela limpeza automática.
- O registro das rotinas automáticas é apagado após 180 dias.
- Os backups ficam por 7 dias.

---

## TERMOS DE USO: [PRODUTO]

**Última atualização:** [dd/mm/aaaa]

### 1. Quem somos
O [PRODUTO] é oferecido por [EMPRESA], inscrita no CNPJ [número], com sede em [endereço] ("nós"). Contato: [e-mail de suporte].

### 2. O que é o serviço
O [PRODUTO] é um sistema online para gestão de lojas e engajamento de equipes: tarefas com pontos, validação de entregas, ranking, prêmios, metas de venda, agenda, comunicados, documentos de RH, onboarding e canal confidencial. É acessado pela internet; não há instalação.

### 3. Conta e acesso
3.1. A conta é da empresa contratante ("Cliente"), representada por um usuário responsável.
3.2. O Cliente é responsável por guardar a senha e por tudo o que é feito com o seu acesso.
3.3. O plano define o número máximo de lojas ativas.

### 4. Planos, preço e pagamento
4.1. O preço é cobrado por loja ativa por mês, conforme a tabela vigente em [link], [com/sem] período de teste de [N] dias.
4.2. A cobrança é feita pela Stripe, por [cartão de crédito / boleto / Pix].
4.3. Mudanças de preço serão avisadas com [30] dias de antecedência.
4.4. Aumentar o número de lojas gera cobrança proporcional no ciclo atual. Reduzir vale a partir do próximo ciclo.
4.5. A nota fiscal de serviço é enviada por [e-mail] em até [N] dias após o pagamento.

### 5. Atraso e cancelamento
5.1. Pagamento não recebido: aviso por e-mail. Depois de [7] dias, a conta fica **somente leitura**. Depois de [30] dias, a conta é **cancelada**.
5.2. O Cliente pode cancelar a qualquer momento pelo portal de pagamento. O acesso continua até o fim do período já pago.
5.3. Depois do cancelamento, o Cliente tem [30] dias para pedir a **exportação** dos seus dados. Depois desse prazo, os dados são apagados em até [60] dias, salvo o que a lei obrigar a guardar (ver a Política de Privacidade).
5.4. Não há reembolso de período já iniciado, [salvo exigência legal / direito de arrependimento de 7 dias, se aplicável].

### 6. Responsabilidades do Cliente
6.1. Cadastrar dados de funcionários e de clientes finais **somente com base legal** (LGPD), informando-os de que usa o [PRODUTO].
6.2. Não cadastrar dados além do necessário (ex.: não anexar documentos que não sejam de RH).
6.3. Usar o canal confidencial de boa-fé e não tentar identificar quem enviou relatos.
6.4. Não usar o serviço para fins ilegais, nem tentar acessar dados de outros clientes.
6.5. Premiações, bônus e metas definidos no sistema são **regras internas do Cliente** com seus funcionários. Nós não somos parte dessa relação trabalhista.

### 7. Nossas responsabilidades
7.1. Manter o serviço funcionando com esforço razoável, sem garantia de disponibilidade ininterrupta [ou: disponibilidade-alvo de 99% ao mês].
7.2. Proteger os dados conforme a Política de Privacidade.
7.3. Avisar com antecedência sobre manutenções programadas, quando possível.

### 8. Limitação de responsabilidade
[Cláusula a redigir pelo advogado: limite de responsabilidade ao valor pago nos últimos 12 meses; exclusão de lucros cessantes; situações de força maior.]

### 9. Propriedade intelectual
O sistema, a marca e o código são de [EMPRESA]. Os **dados** inseridos são do Cliente.

### 10. Alterações destes termos
Mudanças relevantes serão avisadas com [30] dias de antecedência, por e-mail e no sistema.

### 11. Foro
Fica eleito o foro da comarca de [cidade/UF], [ressalvado o foro do consumidor, quando aplicável].

---

## POLÍTICA DE PRIVACIDADE: [PRODUTO]

**Última atualização:** [dd/mm/aaaa]

### 1. Quem é responsável pelos dados
- **Dados do responsável pela conta** (nome, e-mail, telefone, dados de cobrança, registros de acesso): [EMPRESA] é a **controladora**.
- **Dados que o Cliente coloca no sistema** (funcionários, clientes finais, relatos, documentos): o **Cliente é o controlador** e [EMPRESA] é a **operadora**. Tratamos esses dados só para prestar o serviço, conforme as instruções do Cliente e este documento.
- **Encarregado (DPO) de [EMPRESA]:** [nome], [e-mail].

### 2. Quais dados tratamos

| Grupo | Dados | Para quê |
|---|---|---|
| Responsável pela conta | Nome, e-mail, telefone, cidade, razão social, CNPJ, dados de pagamento (guardados pela Stripe; nós não guardamos o número do cartão) | Criar e manter a conta, cobrar, emitir nota fiscal, dar suporte |
| Funcionários do Cliente | Nome, CPF, telefone/WhatsApp, cargo, setor, lojas, dia de folga, períodos de afastamento, pontos, tarefas, fotos das entregas, feedbacks, ciência de comunicados, etapas de onboarding | Funcionamento das tarefas, pontos, ranking, prêmios e RH |
| Documentos pessoais de funcionários | Holerites, atestados (podem conter **dado de saúde**), contratos, documentos de identidade | Guarda e entrega de documentos de RH, a pedido do Cliente |
| Clientes finais do Cliente (agenda) | Nome, CPF, telefone, observações do evento, anexos | Agenda de eventos e serviços do Cliente |
| Canal confidencial | Texto do relato e o dia. **Não guardamos quem enviou.** | Receber e responder denúncias internas do Cliente |
| Uso do sistema | Registros de acesso, datas e horários de ações importantes | Segurança, auditoria e cumprimento legal (Marco Civil da Internet) |

### 3. Bases legais (a validar)
- **Execução de contrato** (art. 7º, V): dados do responsável e do serviço contratado.
- **Obrigação legal** (art. 7º, II): nota fiscal e registros de acesso.
- **Legítimo interesse** (art. 7º, IX): segurança e prevenção a fraudes.
- **Dados de funcionários e de clientes finais:** a base legal é definida pelo Cliente, que é o controlador (ex.: execução do contrato de trabalho, obrigação legal, legítimo interesse).
- **Dado sensível** (atestados): art. 11, II (ex.: obrigação legal/regulatória, exercício de direitos em contrato), definido pelo Cliente.

### 4. Com quem compartilhamos
Só com fornecedores necessários ao serviço (suboperadores): [Supabase (banco e arquivos), hospedagem, Stripe (pagamentos), Resend (e-mails), e futuramente Telegram/WhatsApp]. **Não vendemos dados.** Não compartilhamos dados de um Cliente com outro.

### 5. Transferência internacional
Alguns fornecedores guardam ou processam dados fora do Brasil (ex.: EUA). Essa transferência segue o art. 33 da LGPD, com [cláusulas contratuais padrão / garantias dos fornecedores]. [O banco de dados de produção fica em São Paulo.]

### 6. Segurança
- Cada Cliente só enxerga os próprios dados (isolamento no banco).
- Documentos pessoais em armazenamento privado, com link temporário de 5 minutos e registro de cada acesso.
- CPF e documentos nunca aparecem na TV da loja nem no painel inicial.
- O canal confidencial não registra quem enviou, nem em logs.
- Senhas guardadas pelo provedor de login (nunca em texto aberto); conexões criptografadas (HTTPS).
- Backups diários, guardados por 7 dias.
- O administrador da plataforma não acessa os dados operacionais dos Clientes.

### 7. Por quanto tempo guardamos
- **Enquanto a conta estiver ativa:** todos os dados do serviço.
- **Depois do cancelamento:** [30] dias para o Cliente pedir a exportação; depois, exclusão em até [60] dias. Os backups expiram sozinhos em 7 dias.
- **O que guardamos por mais tempo, por obrigação legal:** dados de cobrança e notas fiscais ([5] anos), registros de acesso ([6] meses, Marco Civil).
- O livro de pontos e o registro de acesso a documentos acompanham a conta e são apagados junto com ela.

### 8. Direitos dos titulares
- **Funcionários e clientes finais** devem procurar **a empresa (Cliente)**, que é a controladora. Nós ajudamos o Cliente a atender o pedido (acesso, correção, exclusão, portabilidade) em até [15] dias.
- **O responsável pela conta** pode exercer seus direitos diretamente com o encarregado de [EMPRESA]: [e-mail].

### 9. Incidentes de segurança
Se houver um incidente que possa causar risco ou dano relevante, avisaremos o Cliente em até [48 horas] com as informações disponíveis, para que ele comunique a ANPD e os titulares quando necessário (art. 48).

### 10. Cookies e armazenamento no navegador
Usamos o armazenamento do navegador só para o funcionamento do sistema: sessão de login, tema claro/escuro, loja escolhida e menu recolhido. Não usamos cookies de publicidade.

### 11. Alterações
Mudanças relevantes serão avisadas por e-mail e no sistema.

---

## Anexo sugerido: Acordo de Tratamento de Dados (DPA) com o Cliente
[O advogado pode avaliar um anexo curto, aceito no cadastro, com:]
- objeto e duração;
- instruções do controlador;
- confidencialidade da equipe;
- lista de suboperadores e aviso de troca;
- apoio aos direitos dos titulares;
- aviso de incidentes;
- devolução e exclusão dos dados no fim do contrato;
- auditoria.
