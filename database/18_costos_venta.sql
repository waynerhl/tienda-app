-- Conserva costos al vender. Los movimientos anteriores permanecen sin costo.
BEGIN;
ALTER TABLE public.movimientos_inventario
  ADD COLUMN costo_unitario_venta numeric(12,2),
  ADD COLUMN origen_costo_venta text,
  ADD COLUMN costo_total_venta numeric(22,2) GENERATED ALWAYS AS (cantidad::numeric*costo_unitario_venta) STORED,
  ADD CONSTRAINT movimiento_costo_venta_valido CHECK(
    (costo_unitario_venta IS NULL AND origen_costo_venta IS NULL) OR
    (costo_unitario_venta IS NOT NULL AND costo_unitario_venta>=0 AND costo_unitario_venta<=9999999999.99 AND origen_costo_venta IS NOT NULL AND origen_costo_venta IN ('LOTE_COMPRA','ULTIMO_COSTO'))
  );
CREATE INDEX idx_movimientos_detalle_venta_costo ON public.movimientos_inventario(detalle_venta_id) WHERE detalle_venta_id IS NOT NULL;
CREATE OR REPLACE FUNCTION tienda_privada.capturar_costo_venta()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_costo numeric; v_tipo text;
BEGIN
  NEW.costo_unitario_venta:=NULL;NEW.origen_costo_venta:=NULL;
  SELECT nombre INTO v_tipo FROM public.tipos_movimientos WHERE id_tipo_movimiento=NEW.tipo_movimiento_id;
  IF v_tipo<>'VENTA' OR NEW.detalle_venta_id IS NULL THEN RETURN NEW; END IF;
  IF NEW.lote_id IS NOT NULL THEN
    SELECT d.costo_unitario INTO v_costo FROM public.lotes l
    JOIN public.detalle_compras d ON d.id_detalle_compra=l.detalle_compra_id
    JOIN public.compras c ON c.id_compra=d.compra_id
    WHERE l.id_lote=NEW.lote_id AND d.producto_id=NEW.producto_id AND c.estado='REGISTRADA';
    IF v_costo IS NOT NULL AND v_costo>=0 AND v_costo<=9999999999.99 THEN
      NEW.costo_unitario_venta:=v_costo;NEW.origen_costo_venta:='LOTE_COMPRA';
    END IF;
  ELSE
    SELECT ultimo_costo INTO v_costo FROM public.productos WHERE id_producto=NEW.producto_id FOR UPDATE;
    IF v_costo IS NOT NULL AND v_costo>=0 AND v_costo<=9999999999.99 THEN
      NEW.costo_unitario_venta:=v_costo;NEW.origen_costo_venta:='ULTIMO_COSTO';
    END IF;
  END IF;
  RETURN NEW;
END;
$fn$;
REVOKE ALL ON FUNCTION tienda_privada.capturar_costo_venta() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER trg_00_capturar_costo_venta BEFORE INSERT ON public.movimientos_inventario
FOR EACH ROW EXECUTE FUNCTION tienda_privada.capturar_costo_venta();

CREATE OR REPLACE FUNCTION public.obtener_reporte_costos(p_desde date,p_hasta date)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $fn$
DECLARE v_resultado jsonb;v_inicio timestamptz;v_fin timestamptz;v_hoy date:=(CURRENT_TIMESTAMP AT TIME ZONE 'America/Guatemala')::date;
BEGIN
  IF auth.uid() IS NULL OR NOT public.fn_tiene_rol(ARRAY['ADMINISTRADOR']) THEN
    RAISE EXCEPTION 'Solo el administrador puede consultar costos y utilidad.' USING ERRCODE='42501';
  END IF;
  IF p_desde IS NULL OR p_hasta IS NULL OR p_desde<'1900-01-01'::date OR p_desde>p_hasta OR p_hasta>v_hoy OR p_hasta-p_desde>365 THEN
    RAISE EXCEPTION 'Selecciona un período válido de hasta 366 días, sin fechas futuras.' USING ERRCODE='22023';
  END IF;
  v_inicio:=p_desde::timestamp AT TIME ZONE 'America/Guatemala';v_fin:=(p_hasta+1)::timestamp AT TIME ZONE 'America/Guatemala';
  WITH candidatas AS (
    SELECT id_venta,total FROM public.ventas WHERE estado='REGISTRADA' AND fecha>=v_inicio AND fecha<v_fin
  ), detalles AS (
    SELECT d.venta_id,count(*) AS lineas,sum(d.subtotal) AS importe FROM public.detalle_ventas d JOIN candidatas c ON c.id_venta=d.venta_id GROUP BY d.venta_id
  ), validas AS (
    SELECT c.id_venta FROM candidatas c JOIN detalles d ON d.venta_id=c.id_venta WHERE d.lineas>0 AND d.importe=c.total
  ), salidas AS (
    SELECT m.detalle_venta_id,sum(m.cantidad) AS unidades,count(*) AS movimientos,count(m.costo_unitario_venta) AS con_costo,
      sum(m.costo_total_venta) AS costo,bool_or(m.origen_costo_venta='ULTIMO_COSTO') AS usa_ultimo_costo
    FROM public.movimientos_inventario m JOIN public.tipos_movimientos t ON t.id_tipo_movimiento=m.tipo_movimiento_id
    JOIN public.detalle_ventas d ON d.id_detalle_venta=m.detalle_venta_id JOIN validas v ON v.id_venta=d.venta_id
    WHERE t.nombre='VENTA' AND t.factor=-1 GROUP BY m.detalle_venta_id
  ), lineas AS (
    SELECT d.id_detalle_venta,d.producto_id,d.cantidad,d.subtotal AS ingreso,s.costo,
      coalesce(s.unidades=d.cantidad AND s.movimientos=s.con_costo,false) AS completa,
      coalesce(s.usa_ultimo_costo,false) AS usa_ultimo_costo
    FROM public.detalle_ventas d JOIN validas v ON v.id_venta=d.venta_id LEFT JOIN salidas s ON s.detalle_venta_id=d.id_detalle_venta
  ), por_producto AS (
    SELECT p.id_producto,p.nombre,p.activo,
      coalesce(sum(l.ingreso) FILTER(WHERE l.completa),0) AS ventas_con_costo,
      coalesce(sum(l.costo) FILTER(WHERE l.completa),0) AS costo,
      coalesce(sum(l.ingreso-l.costo) FILTER(WHERE l.completa),0) AS utilidad_bruta,
      count(*) FILTER(WHERE l.completa) AS lineas_con_costo,count(*) FILTER(WHERE NOT l.completa) AS lineas_sin_costo
    FROM lineas l JOIN public.productos p ON p.id_producto=l.producto_id GROUP BY p.id_producto,p.nombre,p.activo
  ), mayores AS (
    SELECT * FROM por_producto WHERE lineas_con_costo>0 ORDER BY utilidad_bruta DESC,ventas_con_costo DESC,nombre,id_producto LIMIT 20
  ), menores AS (
    SELECT * FROM por_producto WHERE lineas_con_costo>0 ORDER BY utilidad_bruta,ventas_con_costo,nombre,id_producto LIMIT 20
  )
  SELECT jsonb_build_object('desde',p_desde,'hasta',p_hasta,
    'lineas_con_costo',count(*) FILTER(WHERE completa),'lineas_sin_costo',count(*) FILTER(WHERE NOT completa),
    'lineas_ultimo_costo',count(*) FILTER(WHERE completa AND usa_ultimo_costo),
    'ventas_con_costo',coalesce(sum(ingreso) FILTER(WHERE completa),0),
    'ventas_sin_costo',coalesce(sum(ingreso) FILTER(WHERE NOT completa),0),
    'costo_identificado',coalesce(sum(costo) FILTER(WHERE completa),0),
    'utilidad_bruta_estimada',coalesce(sum(ingreso-costo) FILTER(WHERE completa),0),
    'margen_bruto_estimado',CASE WHEN coalesce(sum(ingreso) FILTER(WHERE completa),0)>0 THEN round(100*sum(ingreso-costo) FILTER(WHERE completa)/sum(ingreso) FILTER(WHERE completa),2) ELSE NULL END,
    'mayores',coalesce((SELECT jsonb_agg(to_jsonb(p) ORDER BY p.utilidad_bruta DESC,p.ventas_con_costo DESC,p.nombre,p.id_producto) FROM mayores p),'[]'::jsonb),
    'menores',coalesce((SELECT jsonb_agg(to_jsonb(p) ORDER BY p.utilidad_bruta,p.ventas_con_costo,p.nombre,p.id_producto) FROM menores p),'[]'::jsonb)) INTO v_resultado FROM lineas;
  RETURN v_resultado;
END;
$fn$;
REVOKE ALL ON FUNCTION public.obtener_reporte_costos(date,date) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.obtener_reporte_costos(date,date) TO authenticated;
-- Ambos componentes del reporte comparten el snapshot de una sola consulta.
ALTER FUNCTION public.obtener_reporte_ventas(date,date) STABLE;
ALTER FUNCTION public.obtener_reporte_costos(date,date) STABLE;
CREATE OR REPLACE FUNCTION public.obtener_reporte_ventas_costos(p_desde date,p_hasta date)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $fn$
  SELECT public.obtener_reporte_ventas(p_desde,p_hasta)||jsonb_build_object('costos',public.obtener_reporte_costos(p_desde,p_hasta));
$fn$;
REVOKE ALL ON FUNCTION public.obtener_reporte_ventas_costos(date,date) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.obtener_reporte_ventas_costos(date,date) TO authenticated;
COMMIT;
