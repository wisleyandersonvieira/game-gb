-- Uma das duas conexoes: lanca a venda de hoje e segura a transacao por 2 s.
SET ROLE authenticated;
SET teste.uid = 'ffffffff-ffff-ffff-ffff-ffffffffffff';
BEGIN;
SELECT public.lancar_venda_do_dia(90, public.dia_em_sao_paulo(now()), :valor, 'Conferido no caixa');
SELECT pg_sleep(2);
COMMIT;
