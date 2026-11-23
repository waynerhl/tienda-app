BEGIN;
CREATE TABLE public.ajustes_inventario (
  id_ajuste bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  solicitud_id uuid NOT NULL UNIQUE,
  producto_id integer NOT NULL REFERENCES public.productos(id_producto),
  lote_id integer REFERENCES public.lotes(id_lote),
  movimiento_id integer UNIQUE REFERENCES public.movimientos_inventario(id_movimiento_inventario),
  usuario_id uuid NOT NULL REFERENCES public.usuarios(id_usuario),
  fecha timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  tipo text NOT NULL CHECK(tipo IN ('CONTEO','PERDIDA','VENCIMIENTO','AJUSTE_POSITIVO','AJUSTE_NEGATIVO')),
  motivo text NOT NULL CHECK(length(trim(motivo)) BETWEEN 1 AND 500),
  parametros jsonb NOT NULL,
  resultado jsonb NOT NULL
);
CREATE INDEX ajustes_inventario_producto_fecha_idx ON public.ajustes_inventario(producto_id,fecha DESC,id_ajuste DESC);
CREATE INDEX ajustes_inventario_lote_idx ON public.ajustes_inventario(lote_id);
CREATE INDEX ajustes_inventario_usuario_idx ON public.ajustes_inventario(usuario_id);
ALTER TABLE public.ajustes_inventario ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.ajustes_inventario FROM anon,authenticated;
GRANT SELECT ON public.ajustes_inventario TO authenticated;
CREATE POLICY ajustes_inventario_lectura ON public.ajustes_inventario FOR SELECT TO authenticated USING(public.fn_tiene_rol(ARRAY['ADMINISTRADOR','INVENTARIO']));

CREATE OR REPLACE FUNCTION tienda_privada.registrar_ajuste_inventario(
  p_solicitud_id uuid,p_producto_id integer,p_lote_id integer,p_tipo text,p_cantidad integer,p_existencia_esperada integer,p_motivo text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' SET timezone='America/Guatemala' AS $fn$
DECLARE
  v_usuario uuid:=auth.uid(); v_producto public.productos%ROWTYPE; v_lote public.lotes%ROWTYPE;
  v_anterior public.ajustes_inventario%ROWTYPE; v_params jsonb; v_resultado jsonb;
  v_stock integer; v_delta bigint; v_nuevo bigint; v_tipo text; v_tipo_id integer; v_mov integer; v_id bigint;
  v_hoy date:=(CURRENT_TIMESTAMP AT TIME ZONE 'America/Guatemala')::date;
BEGIN
  IF v_usuario IS NULL OR NOT public.fn_tiene_rol(ARRAY['ADMINISTRADOR','INVENTARIO']) THEN
    RAISE EXCEPTION 'No tienes permiso para ajustar inventario.' USING ERRCODE='42501';
  END IF;
  IF p_solicitud_id IS NULL OR p_producto_id IS NULL OR p_tipo IS NULL
     OR p_tipo NOT IN ('CONTEO','PERDIDA','VENCIMIENTO','AJUSTE_POSITIVO','AJUSTE_NEGATIVO')
     OR p_cantidad IS NULL OR p_cantidad<0 OR (p_tipo<>'CONTEO' AND p_cantidad=0)
     OR p_existencia_esperada IS NULL OR p_existencia_esperada<0
     OR p_motivo IS NULL OR length(trim(p_motivo)) NOT BETWEEN 1 AND 500 THEN
    RAISE EXCEPTION 'Revisa producto, cantidad, existencia vista y motivo.' USING ERRCODE='22023';
  END IF;
  v_params:=jsonb_build_object('producto',p_producto_id,'lote',p_lote_id,'tipo',p_tipo,'cantidad',p_cantidad,'esperada',p_existencia_esperada,'motivo',trim(p_motivo));
  PERFORM pg_advisory_xact_lock(hashtextextended('ajuste-inventario:'||p_solicitud_id::text,0));
  SELECT * INTO v_anterior FROM public.ajustes_inventario WHERE solicitud_id=p_solicitud_id;
  IF FOUND THEN
    IF v_anterior.usuario_id<>v_usuario OR v_anterior.parametros<>v_params THEN
      RAISE EXCEPTION 'La referencia ya corresponde a otro ajuste.' USING ERRCODE='22023';
    END IF;
    RETURN v_anterior.resultado||jsonb_build_object('repetida',true);
  END IF;
  SELECT * INTO v_producto FROM public.productos WHERE id_producto=p_producto_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Producto no encontrado.' USING ERRCODE='22023'; END IF;
  IF v_producto.controla_lotes THEN
    IF p_lote_id IS NULL THEN RAISE EXCEPTION 'Selecciona el lote físico que estás ajustando.' USING ERRCODE='22023'; END IF;
    SELECT l.* INTO v_lote FROM public.lotes l JOIN public.detalle_compras d ON d.id_detalle_compra=l.detalle_compra_id
      JOIN public.compras c ON c.id_compra=d.compra_id
      WHERE l.id_lote=p_lote_id AND d.producto_id=p_producto_id AND c.estado='REGISTRADA' FOR UPDATE OF l;
    IF NOT FOUND THEN RAISE EXCEPTION 'El lote no pertenece a este producto o su compra no está registrada.' USING ERRCODE='22023'; END IF;
    IF v_producto.existencia<>(SELECT coalesce(sum(public.fn_stock_lote(l.id_lote)),0) FROM public.lotes l JOIN public.detalle_compras d ON d.id_detalle_compra=l.detalle_compra_id WHERE d.producto_id=p_producto_id) THEN
      RAISE EXCEPTION 'La existencia del producto no coincide con la suma de sus lotes. Revisa el historial antes de ajustar.' USING ERRCODE='22023';
    END IF;
    v_stock:=public.fn_stock_lote(p_lote_id);
  ELSE
    IF p_lote_id IS NOT NULL THEN RAISE EXCEPTION 'Este producto no usa lotes.' USING ERRCODE='22023'; END IF;
    v_stock:=v_producto.existencia;
  END IF;
  IF v_stock<0 THEN RAISE EXCEPTION 'El lote tiene una existencia inconsistente.' USING ERRCODE='22023'; END IF;
  IF v_stock<>p_existencia_esperada THEN
    RAISE EXCEPTION 'La existencia cambió desde tu consulta: ahora es %. Actualiza, revisa el conteo y prepara otra confirmación.',v_stock USING ERRCODE='22023';
  END IF;
  IF p_tipo='VENCIMIENTO' AND (p_lote_id IS NULL OR v_lote.fecha_vencimiento IS NULL OR v_lote.fecha_vencimiento>=v_hoy) THEN
    RAISE EXCEPTION 'Vencimiento solo permite retirar unidades de un lote con fecha anterior a hoy.' USING ERRCODE='22023';
  END IF;
  v_delta:=CASE WHEN p_tipo='CONTEO' THEN p_cantidad::bigint-v_stock WHEN p_tipo='AJUSTE_POSITIVO' THEN p_cantidad::bigint ELSE -p_cantidad::bigint END;
  v_nuevo:=v_producto.existencia::bigint+v_delta;
  IF v_stock::bigint+v_delta<0 OR v_nuevo<0 OR v_nuevo>2147483647 THEN
    RAISE EXCEPTION 'La cantidad supera la existencia disponible o el máximo permitido.' USING ERRCODE='22023';
  END IF;
  IF v_delta<>0 THEN
    v_tipo:=CASE WHEN p_tipo='CONTEO' THEN CASE WHEN v_delta>0 THEN 'AJUSTE_POSITIVO' ELSE 'AJUSTE_NEGATIVO' END ELSE p_tipo END;
    SELECT id_tipo_movimiento INTO v_tipo_id FROM public.tipos_movimientos WHERE nombre=v_tipo AND factor=CASE WHEN v_delta>0 THEN 1 ELSE -1 END;
    IF NOT FOUND THEN RAISE EXCEPTION 'El catálogo de movimientos requiere revisión.' USING ERRCODE='22023'; END IF;
    INSERT INTO public.movimientos_inventario(producto_id,lote_id,tipo_movimiento_id,cantidad,usuario_id,observacion)
    VALUES(p_producto_id,p_lote_id,v_tipo_id,abs(v_delta)::integer,v_usuario,trim(p_motivo)) RETURNING id_movimiento_inventario INTO v_mov;
  END IF;
  v_resultado:=jsonb_build_object('producto_id',p_producto_id,'lote_id',p_lote_id,'tipo',p_tipo,
    'existencia_anterior',v_stock,'existencia_nueva',v_stock::bigint+v_delta,'variacion',v_delta,
    'producto_anterior',v_producto.existencia,'producto_nuevo',v_nuevo,'movimiento_id',v_mov,'repetida',false);
  INSERT INTO public.ajustes_inventario(solicitud_id,producto_id,lote_id,movimiento_id,usuario_id,tipo,motivo,parametros,resultado)
  VALUES(p_solicitud_id,p_producto_id,p_lote_id,v_mov,v_usuario,p_tipo,trim(p_motivo),v_params,v_resultado) RETURNING id_ajuste INTO v_id;
  v_resultado:=v_resultado||jsonb_build_object('id_ajuste',v_id);
  UPDATE public.ajustes_inventario SET resultado=v_resultado WHERE id_ajuste=v_id;
  RETURN v_resultado;
END;
$fn$;
REVOKE ALL ON FUNCTION tienda_privada.registrar_ajuste_inventario(uuid,integer,integer,text,integer,integer,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION tienda_privada.registrar_ajuste_inventario(uuid,integer,integer,text,integer,integer,text) TO authenticated;
CREATE OR REPLACE FUNCTION public.registrar_ajuste_inventario(p_solicitud_id uuid,p_producto_id integer,p_lote_id integer,p_tipo text,p_cantidad integer,p_existencia_esperada integer,p_motivo text)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $fn$
  SELECT tienda_privada.registrar_ajuste_inventario(p_solicitud_id,p_producto_id,p_lote_id,p_tipo,p_cantidad,p_existencia_esperada,p_motivo);
$fn$;
REVOKE ALL ON FUNCTION public.registrar_ajuste_inventario(uuid,integer,integer,text,integer,integer,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.registrar_ajuste_inventario(uuid,integer,integer,text,integer,integer,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.obtener_inventario_producto(p_producto_id integer,p_pagina_lotes integer DEFAULT 0)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $fn$
DECLARE v_resultado jsonb; v_hoy date:=(CURRENT_TIMESTAMP AT TIME ZONE 'America/Guatemala')::date;
BEGIN
  IF auth.uid() IS NULL OR NOT public.fn_tiene_rol(ARRAY['ADMINISTRADOR','INVENTARIO']) THEN
    RAISE EXCEPTION 'No tienes permiso para consultar ajustes de inventario.' USING ERRCODE='42501';
  END IF;
  IF p_pagina_lotes IS NULL OR p_pagina_lotes<0 OR p_pagina_lotes>1000000 THEN RAISE EXCEPTION 'Página inválida.' USING ERRCODE='22023'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.productos WHERE id_producto=p_producto_id) THEN RAISE EXCEPTION 'Producto no encontrado.' USING ERRCODE='22023'; END IF;
  WITH lotes_validos AS (
    SELECT l.id_lote,l.numero_lote,l.fecha_ingreso,l.fecha_vencimiento,public.fn_stock_lote(l.id_lote) AS existencia,
      coalesce(l.fecha_vencimiento<v_hoy,false) AS vencido
    FROM public.lotes l JOIN public.detalle_compras d ON d.id_detalle_compra=l.detalle_compra_id JOIN public.compras c ON c.id_compra=d.compra_id
    WHERE d.producto_id=p_producto_id AND c.estado='REGISTRADA'
  ), pagina AS (
    SELECT * FROM lotes_validos ORDER BY fecha_vencimiento ASC NULLS LAST,id_lote LIMIT 20 OFFSET p_pagina_lotes*20
  ), ajustes AS (
    SELECT id_ajuste,fecha,tipo,lote_id,motivo,resultado FROM public.ajustes_inventario WHERE producto_id=p_producto_id ORDER BY fecha DESC,id_ajuste DESC LIMIT 20
  ), movimientos AS (
    SELECT m.id_movimiento_inventario,m.fecha,t.nombre AS tipo,m.cantidad,t.factor,m.lote_id,m.observacion
    FROM public.movimientos_inventario m JOIN public.tipos_movimientos t ON t.id_tipo_movimiento=m.tipo_movimiento_id
    WHERE m.producto_id=p_producto_id ORDER BY m.fecha DESC,m.id_movimiento_inventario DESC LIMIT 30
  )
  SELECT jsonb_build_object('producto',(SELECT jsonb_build_object('id_producto',p.id_producto,'nombre',p.nombre,'codigo_barras',p.codigo_barras,'existencia',p.existencia,'controla_lotes',p.controla_lotes,'activo',p.activo) FROM public.productos p WHERE id_producto=p_producto_id),
    'total_lotes',(SELECT count(*) FROM lotes_validos),
    'suma_lotes',(SELECT coalesce(sum(public.fn_stock_lote(l.id_lote)),0) FROM public.lotes l JOIN public.detalle_compras d ON d.id_detalle_compra=l.detalle_compra_id WHERE d.producto_id=p_producto_id),
    'lotes',coalesce((SELECT jsonb_agg(to_jsonb(p) ORDER BY p.fecha_vencimiento ASC NULLS LAST,p.id_lote) FROM pagina p),'[]'::jsonb),
    'ajustes',coalesce((SELECT jsonb_agg(to_jsonb(a) ORDER BY a.fecha DESC,a.id_ajuste DESC) FROM ajustes a),'[]'::jsonb),
    'movimientos',coalesce((SELECT jsonb_agg(to_jsonb(m) ORDER BY m.fecha DESC,m.id_movimiento_inventario DESC) FROM movimientos m),'[]'::jsonb)) INTO v_resultado;
  RETURN v_resultado;
END;
$fn$;
REVOKE ALL ON FUNCTION public.obtener_inventario_producto(integer,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.obtener_inventario_producto(integer,integer) TO authenticated;
COMMIT;
