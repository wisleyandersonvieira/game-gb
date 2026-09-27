-- Entrega da cópia de tarefa que se repete (29/09/2026, defeito achado pelo
-- Wisley no tablet).
--
-- O defeito: aceitar uma tarefa COMPARTILHADA ou uma missão (ou receber a
-- tarefa de quem está de folga) cria uma cópia no nome da pessoa, e a cópia
-- nasce sempre "Unica". registrar_entrega aplicava a regra da Única olhando
-- o tipo da CÓPIA, e a regra da Única olha a original e TODAS as cópias, de
-- qualquer dia. Numa tarefa diária entregue por alguém num dia anterior, a
-- entrega de hoje era recusada com "Esta tarefa única já foi entregue" —
-- para sempre —, enquanto o tablet (que olha a original, diária) mostrava
-- "Em andamento" com o botão de entregar. A tela oferecia o que o banco
-- sempre recusava.
--
-- O conserto: a regra da Única vale pelo tipo da tarefa ORIGINAL. A cópia de
-- tarefa que se repete tem a trava de sempre (uma entrega por dia). Nada
-- mais muda: a tarefa Única de verdade continua acabando na primeira
-- entrega, com dono ou compartilhada.
--
-- Parte da versão mais recente (20260929140000_hoje_da_conta.sql), com o
-- diff conferido: só a condição da Única.
CREATE OR REPLACE FUNCTION public.registrar_entrega(
  p_atribuicaoid integer,
  p_observacao   text    DEFAULT NULL,
  p_pathfoto     text    DEFAULT NULL,
  p_aprovar      boolean DEFAULT false,
  -- Impressão digital da imagem: a mesma foto não prova duas tarefas, nem
  -- que o arquivo mude de nome. O Telegram já usava este campo com o id dele.
  p_fotoidunico  text    DEFAULT NULL,
  -- true quando o arquivo não trazia a hora em que a foto foi tirada. A
  -- entrega entra assim mesmo e o Quadro avisa: o gestor decide na aprovação.
  p_semhorafoto  boolean DEFAULT false
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_conta integer := public.minha_conta_editavel();
  v_atr   public.tarefasatribuidas%ROWTYPE;
  v_hoje  date    := public.hoje_da_conta(v_conta);
  v_foto  text    := nullif(btrim(coalesce(p_pathfoto, '')), '');
  v_id    integer;
BEGIN
  IF v_conta IS NULL THEN
    RAISE EXCEPTION 'Sua conta não pode alterar dados no momento.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_atr FROM public.tarefasatribuidas
  WHERE atribuicaoid = p_atribuicaoid AND contaid = v_conta
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Atribuição não encontrada.' USING ERRCODE = 'no_data_found';
  END IF;

  IF v_atr.datafimvigencia IS NOT NULL THEN
    RAISE EXCEPTION 'Esta atribuição foi encerrada.' USING ERRCODE = 'check_violation';
  END IF;

  IF v_atr.funcionarioid IS NULL THEN
    RAISE EXCEPTION 'Atribuição sem funcionário não recebe entrega.' USING ERRCODE = 'check_violation';
  END IF;

  IF NOT public.tarefa_cai_no_dia(v_atr.tipofrequencia, v_atr.valorfrequencia, v_atr.dataagendamento, v_hoje, public.fuso_da_conta(v_conta)) THEN
    RAISE EXCEPTION 'Esta tarefa não cai hoje.' USING ERRCODE = 'check_violation';
  END IF;

  -- Unica: depois de entregue (pendente ou aprovada) em qualquer dia, acabou.
  -- Na compartilhada, vale para qualquer cópia: senão a tarefa voltava todo
  -- dia e pagava de novo.
  -- 29/09/2026: vale pelo tipo da tarefa ORIGINAL. A cópia de quem pegou uma
  -- tarefa compartilhada (ou recebeu a de quem está de folga) nasce sempre
  -- "Unica", até quando a original é diária; antes, a regra olhava o tipo da
  -- CÓPIA e, numa tarefa diária, achava a entrega de uma cópia de ONTEM: o
  -- tablet mostrava "Em andamento" (a fila olha a original) e a entrega era
  -- recusada para sempre com "já foi entregue". Na cópia de tarefa que se
  -- repete, a trava é a de sempre: uma entrega por dia.
  IF coalesce((SELECT o.tipofrequencia FROM public.tarefasatribuidas o
                WHERE o.contaid = v_conta AND o.atribuicaoid = v_atr.origematribuicaoid),
              v_atr.tipofrequencia) = 'Unica'
     AND public.tarefa_unica_ja_cumprida(v_conta, coalesce(v_atr.origematribuicaoid, p_atribuicaoid)) THEN
    RAISE EXCEPTION 'Esta tarefa única já foi entregue.' USING ERRCODE = 'unique_violation';
  END IF;

  IF v_foto IS NOT NULL AND v_foto NOT LIKE v_conta || '/' || v_atr.lojaid || '/%' THEN
    RAISE EXCEPTION 'A foto precisa estar na pasta da própria loja.' USING ERRCODE = 'check_violation';
  END IF;

  -- A mesma foto não prova duas tarefas: pelo caminho e pela imagem em si.
  IF v_foto IS NOT NULL AND EXISTS (SELECT 1 FROM public.entregas e
                                     WHERE e.contaid = v_conta AND e.pathfotoevidencia = v_foto) THEN
    RAISE EXCEPTION 'Esta foto já foi usada em outra entrega. Tire uma foto nova.'
      USING ERRCODE = 'unique_violation';
  END IF;
  IF p_fotoidunico IS NOT NULL AND EXISTS (SELECT 1 FROM public.entregas e
                                            WHERE e.contaid = v_conta AND e.fotoidunico = p_fotoidunico) THEN
    RAISE EXCEPTION 'Esta foto já foi usada em outra entrega. Tire uma foto nova.'
      USING ERRCODE = 'unique_violation';
  END IF;

  -- Entregar vale como aceite (tarefa com dono; a cópia da compartilhada já
  -- nasceu de um aceite).
  IF v_atr.origematribuicaoid IS NULL THEN
    INSERT INTO public.missoesaceites (contaid, atribuicaoid, dia, funcionarioid, canal)
    VALUES (v_conta, p_atribuicaoid, v_hoje, v_atr.funcionarioid, public.canal_atual())
    ON CONFLICT (contaid, atribuicaoid, dia) WHERE revogadoem IS NULL DO NOTHING;
  END IF;

  BEGIN
    INSERT INTO public.entregas (
      contaid, tarefaid, funcionarioid, lojaid, atribuicaoid,
      dataenvio, pathfotoevidencia, observacao, statusvalidacao,
      fotoidunico, semhorafoto
    ) VALUES (
      v_conta, v_atr.tarefaid, v_atr.funcionarioid, v_atr.lojaid, p_atribuicaoid,
      now(), v_foto, nullif(btrim(coalesce(p_observacao, '')), ''), 'Pendente',
      nullif(btrim(coalesce(p_fotoidunico, '')), ''), coalesce(p_semhorafoto, false)
    )
    RETURNING entregaid INTO v_id;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'Já existe uma entrega desta atribuição hoje, pendente ou aprovada.'
      USING ERRCODE = 'unique_violation';
  END;

  IF p_aprovar THEN
    PERFORM public.aprovar_entrega(v_id);
  END IF;

  RETURN v_id;
END;
$$;
