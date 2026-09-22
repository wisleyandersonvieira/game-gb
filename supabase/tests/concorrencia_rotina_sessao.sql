-- Uma das duas conexoes: roda o despachante, a geracao da conta 12 e tenta
-- passar a tarefa da folguista (a outra conexao tenta o mesmo, para outra pessoa).
SELECT public.rotinas_despachar();
BEGIN;
SELECT public.lista_do_dia_gerar(12, public.dia_em_sao_paulo(now()), public.dia_em_sao_paulo(now()), false);
SELECT pg_sleep(1);
COMMIT;
SET ROLE authenticated;
SET teste.uid = '0c0c0c0c-0c0c-0c0c-0c0c-0c0c0c0c0c0c';
-- Um comando só: a trava do repasse fica segura durante a pausa.
SELECT public.passar_tarefa_de_folga(1220, :pessoa), pg_sleep(1);
