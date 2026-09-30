-- =========================================================================
-- STGame — Conserto do banco no ar: a coluna das fotos (erro no Quadro do master).
--
-- Como usar: Supabase -> SQL Editor -> New query -> colar TUDO -> Run.
-- Se der erro, NADA é aplicado: me mande a mensagem.
-- Pode rodar duas vezes sem problema.
--
-- ATENÇÃO: aplique antes o aplicar-valor-e-entrega-sem-foto.sql (e os
-- anteriores). Aplique ESTE ARQUIVO ANTES de publicar a versão nova.
--
-- Este arquivo é UMA migração só:
--   20260929289000_conserto_da_migracao_das_fotos.sql
--
-- CLASSIFICAÇÃO: ACRESCENTA (cria uma coluna, recria uma função interna das rotinas das fotos e apaga uma função que ninguém chama; o site no ar não usa nada que saia)
--
-- O QUE MUDA: o Quadro do master volta a abrir o histórico (Pendentes, Aprovadas, Recusadas). As fotos que já passaram do prazo e ainda apareciam somem das telas e entram na fila para serem apagadas (a política de uso promete isso); a entrega diz "foto vencida, sendo apagada". Foto dentro do prazo não muda.
-- =========================================================================


BEGIN;

-- CLASSIFICAÇÃO: ACRESCENTA
-- (cria uma coluna, recria uma função interna das rotinas e apaga uma função
-- que ninguém chama; o site no ar não usa nada que saia.)
--
-- Conserto do banco no ar (30/09/2026): a migração 20260929231000 foi
-- EDITADA 20 minutos depois de publicada (27/09, 17:30 -> 17:50). O banco no
-- ar ficou com a PRIMEIRA versão: sem a coluna entregas.fotoaguardaremocaoem
-- (o Quadro do master quebra: "column e.fotoaguardaremocaoem does not exist")
-- e com a rotina das fotos antiga. Pior: a primeira versão fazia as fotos
-- VENCIDAS que diziam "removida" com o arquivo ainda guardado voltarem a
-- aparecer; a segunda as esconde ("foto vencida, sendo apagada").
--
-- Esta migração leva o banco ao estado da segunda versão, sem reaplicar a
-- 20260929231000 inteira (isso desfaria o que as migrações seguintes mudaram):
--   1. a coluna;
--   2. a rotina das fotos na versão de hoje (a da 20260929231000, a mais nova);
--   3. os dados, com a regra de sempre: foto vencida some das telas e entra
--      na fila para ser apagada; o arquivo que ainda serve a uma entrega
--      dentro do prazo NUNCA entra na fila (e sai dela, se estiver);
--   4. apaga marcar_senha_trocada: função morta desde 27/09 (a coluna que ela
--      usava saiu na 20260927100500); ninguém a chama.
-- Pode rodar duas vezes: a segunda não muda nada.

-- 1. A coluna.
ALTER TABLE public.entregas ADD COLUMN IF NOT EXISTS fotoaguardaremocaoem timestamptz;
COMMENT ON COLUMN public.entregas.fotoaguardaremocaoem IS
  'Quando a foto passou do prazo e o arquivo entrou na fila para ser apagado. Daí em diante a foto não aparece em tela nenhuma; fotoexpiradaem só é gravado quando o arquivo sai de verdade.';

-- 2. A rotina das fotos: a versão de hoje (de 20260929231000_fotos_de_verdade_e_saude), igual.
CREATE OR REPLACE FUNCTION public.rotina_expurgo_fotos(p_contaid integer, p_agora timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_hoje   date;
  v_hora   time;
  v_inicio timestamptz := clock_timestamp();
  v_dias   integer;
  v_n      integer;
  v_presas integer;
  v_atraso integer;
BEGIN
  SELECT x.dia, x.hora INTO v_hoje, v_hora FROM public.rotina_hora_local(p_agora) x;
  BEGIN
    IF v_hora < public.rotina_horario(p_contaid, 'HORARIO_CONFERENCIA_LIVRO', '03:00') THEN
      RETURN jsonb_build_object('acao', 'antes do horario');
    END IF;
    -- Já fez o trabalho do dia: com "ok", ou com o aviso de fila parada (que
    -- tem os números). Erro inesperado (sem números) tenta de novo.
    IF EXISTS (SELECT 1 FROM public.rotinasexecucoes
                WHERE contaid = p_contaid AND rotina = 'expurgo_fotos' AND referencia = v_hoje
                  AND (resultado = 'ok' OR detalhe ? 'enfileiradas')) THEN
      RETURN jsonb_build_object('acao', 'ja rodou hoje');
    END IF;

    v_dias := public.dias_guardar_foto(p_contaid);

    -- 29/09/2026: a rotina só PÕE NA FILA o arquivo vencido. A entrega NÃO
    -- é marcada aqui: "foto removida" só é gravado quando o arquivo sai de
    -- verdade (expurgo_resultado). Antes, a entrega era marcada antes, e uma
    -- remoção que nunca rodava deixava gravado "apagada" para foto que
    -- continuava guardada.
    -- Fica de fora o arquivo que ainda serve a uma entrega DENTRO do prazo
    -- (apagá-lo levaria a foto dela junto) e o que já está na fila.
    INSERT INTO public.fotosexpurgo (contaid, entregaid, caminho)
    SELECT p_contaid, e.entregaid, e.pathfotoevidencia
      FROM public.entregas e
     WHERE e.contaid = p_contaid
       AND e.pathfotoevidencia IS NOT NULL
       AND e.fotoexpiradaem IS NULL
       AND e.dataenvio < p_agora - make_interval(days => v_dias)
       AND NOT EXISTS (SELECT 1 FROM public.fotosexpurgo f
                        WHERE f.contaid = p_contaid AND f.caminho = e.pathfotoevidencia)
       AND NOT EXISTS (SELECT 1 FROM public.entregas r
                        WHERE r.contaid = p_contaid AND r.pathfotoevidencia = e.pathfotoevidencia
                          AND r.dataenvio >= p_agora - make_interval(days => v_dias))
     ORDER BY e.dataenvio
     LIMIT 2000
    ON CONFLICT (contaid, caminho) DO NOTHING;
    GET DIAGNOSTICS v_n = ROW_COUNT;

    -- Na fila = vencida: some das telas (a política promete), sem dizer
    -- "removida". Todas as entregas que usam o arquivo estão vencidas: o
    -- arquivo que ainda serve a uma no prazo não entra na fila.
    UPDATE public.entregas e
       SET fotoaguardaremocaoem = p_agora
      FROM public.fotosexpurgo f
     WHERE f.contaid = p_contaid AND f.removidoem IS NULL
       AND e.contaid = p_contaid AND e.pathfotoevidencia = f.caminho
       AND e.fotoaguardaremocaoem IS NULL AND e.fotoexpiradaem IS NULL;

    IF EXISTS (SELECT 1 FROM public.fotosexpurgo
                WHERE contaid = p_contaid AND removidoem IS NULL AND tentativas < 5) THEN
      PERFORM public.fotos_expurgo_disparar();
    END IF;

    -- Remoção que não acontece não fica calada: presa (5 tentativas) ou
    -- atrasada (na fila há mais de 2 dias, sinal de que a remoção nem roda).
    SELECT count(*) FILTER (WHERE tentativas >= 5),
           coalesce(max(extract(day FROM p_agora - criadoem))::integer, 0)
      INTO v_presas, v_atraso
      FROM public.fotosexpurgo
     WHERE contaid = p_contaid AND removidoem IS NULL;
    IF v_presas > 0 OR v_atraso > 2 THEN
      INSERT INTO public.avisossistema (contaid, tipo, texto)
      SELECT p_contaid, 'expurgo_preso', left(
               'Fotos vencidas continuam guardadas: ' ||
               (SELECT count(*) FROM public.fotosexpurgo WHERE contaid = p_contaid AND removidoem IS NULL) ||
               ' esperando para sair, a mais antiga há ' || v_atraso || ' dia(s)' ||
               CASE WHEN v_presas > 0 THEN ', ' || v_presas || ' com a remoção falhando 5 vezes' ELSE '' END ||
               '. Veja a Saúde do sistema.', 300)
       WHERE NOT EXISTS (SELECT 1 FROM public.avisossistema
                          WHERE contaid = p_contaid AND tipo = 'expurgo_preso' AND lidoem IS NULL);
      PERFORM public.rotina_registrar(p_contaid, 'expurgo_fotos', v_hoje, 'agendada', v_inicio, 'erro',
                                      jsonb_build_object('enfileiradas', v_n, 'dias', v_dias, 'presas', v_presas, 'atraso', v_atraso),
                                      'fotos vencidas continuam no armazenamento');
      RETURN jsonb_build_object('enfileiradas', v_n, 'dias', v_dias, 'presas', v_presas, 'atraso', v_atraso);
    END IF;

    PERFORM public.rotina_registrar(p_contaid, 'expurgo_fotos', v_hoje, 'agendada', v_inicio, 'ok',
                                    jsonb_build_object('enfileiradas', v_n, 'dias', v_dias), NULL);
    RETURN jsonb_build_object('enfileiradas', v_n, 'dias', v_dias);
  EXCEPTION WHEN OTHERS THEN
    PERFORM public.rotina_registrar(p_contaid, 'expurgo_fotos', v_hoje, 'agendada', v_inicio, 'erro', NULL, SQLERRM);
    RETURN jsonb_build_object('erro', SQLERRM);
  END;
END;
$function$;

-- 3. Os dados.
-- (a) A entrega que dizia "removida" com o arquivo ainda na fila (a primeira
--     versão já tinha devolvido o caminho; aqui só o caso que sobrou): volta
--     o caminho, e ela passa a dizer "sendo apagada".
UPDATE public.entregas e
   SET pathfotoevidencia = f.caminho, fotoexpiradaem = NULL, fotoaguardaremocaoem = f.criadoem
  FROM public.fotosexpurgo f
 WHERE f.contaid = e.contaid AND f.entregaid = e.entregaid
   AND f.removidoem IS NULL
   AND e.fotoexpiradaem IS NOT NULL AND e.pathfotoevidencia IS NULL;
-- (b) Arquivo na fila (ainda não apagado) que serve a uma entrega DENTRO do
--     prazo: sai da fila, e a foto continua aparecendo (a regra da rotina:
--     o arquivo que ainda serve a uma entrega no prazo nunca é apagado).
DELETE FROM public.fotosexpurgo f
 WHERE f.removidoem IS NULL
   AND EXISTS (SELECT 1 FROM public.entregas r
                WHERE r.contaid = f.contaid AND r.pathfotoevidencia = f.caminho
                  AND r.dataenvio >= now() - make_interval(days => public.dias_guardar_foto(r.contaid)));
UPDATE public.entregas e
   SET fotoaguardaremocaoem = NULL
 WHERE e.fotoaguardaremocaoem IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM public.fotosexpurgo f
                    WHERE f.contaid = e.contaid AND f.caminho = e.pathfotoevidencia AND f.removidoem IS NULL);
-- (c) Toda foto que já passou do prazo e ainda não está na fila entra nela
--     (as mesmas regras da rotina).
INSERT INTO public.fotosexpurgo (contaid, entregaid, caminho)
SELECT DISTINCT ON (e.contaid, e.pathfotoevidencia) e.contaid, e.entregaid, e.pathfotoevidencia
  FROM public.entregas e
 WHERE e.pathfotoevidencia IS NOT NULL AND e.fotoexpiradaem IS NULL
   AND e.dataenvio < now() - make_interval(days => public.dias_guardar_foto(e.contaid))
   AND NOT EXISTS (SELECT 1 FROM public.fotosexpurgo f
                    WHERE f.contaid = e.contaid AND f.caminho = e.pathfotoevidencia)
   AND NOT EXISTS (SELECT 1 FROM public.entregas r
                    WHERE r.contaid = e.contaid AND r.pathfotoevidencia = e.pathfotoevidencia
                      AND r.dataenvio >= now() - make_interval(days => public.dias_guardar_foto(e.contaid)))
 ORDER BY e.contaid, e.pathfotoevidencia, e.dataenvio
ON CONFLICT (contaid, caminho) DO NOTHING;
-- (d) Na fila = some das telas: "sendo apagada".
UPDATE public.entregas e
   SET fotoaguardaremocaoem = now()
  FROM public.fotosexpurgo f
 WHERE f.contaid = e.contaid AND f.removidoem IS NULL AND e.pathfotoevidencia = f.caminho
   AND e.fotoaguardaremocaoem IS NULL AND e.fotoexpiradaem IS NULL;
-- (e) E pede a remoção já (sem o cofre e o pg_net, como no teste, não faz nada).
SELECT public.fotos_expurgo_disparar();

-- 4. Função morta.
DROP FUNCTION IF EXISTS public.marcar_senha_trocada(integer, integer);

COMMIT;
