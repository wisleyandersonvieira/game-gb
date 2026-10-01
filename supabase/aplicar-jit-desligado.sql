-- =========================================================================
-- STGame — JIT desligado nas consultas pequenas (resumo do mês e Início).
--
-- Como usar: Supabase -> SQL Editor -> New query -> colar TUDO -> Run.
-- Se der erro, NADA é aplicado: me mande a mensagem.
-- Pode rodar duas vezes sem problema.
--
-- ATENÇÃO: aplique antes o aplicar-meta-pela-janela.sql (e os anteriores).
-- Aplique ESTE ARQUIVO ANTES de publicar a versão nova.
--
-- Este arquivo tem UMA migração:
--   20261001200000_jit_desligado_nas_consultas_pequenas.sql
--
-- CLASSIFICAÇÃO: ACRESCENTA (só liga uma configuração em quatro funções que já existem; nome, parâmetros, código e resposta não mudam. O site no ar continua funcionando com o banco novo)
--
-- O QUE MUDA: nada que se veja, só a velocidade: o resumo do mês (tela Metas) e o Início não compilam mais a consulta antes de rodar. Se o banco no ar tem o JIT ligado, a tela de Metas do gerente cai de cerca de 1 s para cerca de 0,1 s.
-- =========================================================================


BEGIN;

-- ======== 20261001200000_jit_desligado_nas_consultas_pequenas.sql ========
-- CLASSIFICAÇÃO: ACRESCENTA
-- (só liga uma configuração em quatro funções que já existem; nome,
-- parâmetros, código e resposta não mudam.)
--
-- JIT desligado nas consultas pequenas (01/10/2026, pedido do Wisley).
--
-- O JIT do Postgres compila a consulta antes de rodar quando a ESTIMATIVA de
-- custo passa de um limite. Nestas funções a estimativa é absurda (até 790
-- milhões, para 31 dias: o planejador supõe 1.000 linhas em cada
-- generate_series e em cada meta_do_dia), e a compilação custava mais do que a
-- consulta: o resumo do mês levava 469 ms (master) e 1.000 ms (gerente, que
-- compila duas vezes), contra 8 e 15 ms sem o JIT, com volume de loja real.
--
-- O padrão do JIT é da plataforma, não nosso: se o Supabase o mudar, ou num
-- projeto novo, a tela não pode ficar 60 vezes mais lenta sozinha. Por isso a
-- configuração fica NA FUNÇÃO, valendo em qualquer banco.
--
-- As quatro são TODAS as funções em que o JIT ligou na varredura (o teste de
-- isolamento inteiro e todas as telas medidas com volume de loja real). A trava
-- (supabase/tests/jit.sh, no rodar.sh) roda as telas com volume e reprova se
-- qualquer consulta ligar o JIT de novo.
ALTER FUNCTION public.metas_do_mes(integer, date) SET jit = off;
ALTER FUNCTION public.metas_do_mes_gerente(integer, date) SET jit = off;
ALTER FUNCTION public.painel_inicio(integer) SET jit = off;
ALTER FUNCTION public.painel_inicio_gerente(integer) SET jit = off;

COMMIT;
