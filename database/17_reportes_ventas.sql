BEGIN;
CREATE OR REPLACE FUNCTION public.obtener_reporte_ventas(p_desde date,p_hasta date)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $fn$
DECLARE v_resultado jsonb; v_inicio timestamptz; v_fin timestamptz; v_hoy date:=(CURRENT_TIMESTAMP AT TIME ZONE 'America/Guatemala')::date;
BEGIN
  IF auth.uid() IS NULL OR NOT public.fn_tiene_rol(ARRAY['ADMINISTRADOR']) THEN
    RAISE EXCEPTION 'Solo el administrador puede consultar reportes de la tienda.' USING ERRCODE='42501';
  END IF;
  IF p_desde IS NULL OR p_hasta IS NULL OR p_desde<'1900-01-01'::date OR p_desde>p_hasta OR p_hasta>v_hoy OR p_hasta-p_desde>365 THEN
    RAISE EXCEPTION 'Selecciona un período válido de hasta 366 días, sin fechas futuras.' USING ERRCODE='22023';
  END IF;
  v_inicio:=p_desde::timestamp AT TIME ZONE 'America/Guatemala';v_fin:=(p_hasta+1)::timestamp AT TIME ZONE 'America/Guatemala';
  WITH candidatas AS (
    SELECT id_venta,fecha,total,forma_pago_id FROM public.ventas WHERE estado='REGISTRADA' AND fecha>=v_inicio AND fecha<v_fin
  ), detalles AS (
    SELECT d.venta_id,count(*) AS lineas,sum(d.subtotal) AS importe,sum(d.cantidad) AS unidades
    FROM public.detalle_ventas d JOIN candidatas c ON c.id_venta=d.venta_id GROUP BY d.venta_id
  ), revisadas AS (
    SELECT c.*,coalesce(d.importe,0) AS total_detalles,coalesce(d.unidades,0) AS unidades,
      coalesce(d.lineas,0)>0 AND c.total=coalesce(d.importe,0) AS valida
    FROM candidatas c LEFT JOIN detalles d ON d.venta_id=c.id_venta
  ), validas AS (SELECT * FROM revisadas WHERE valida),
  venta_diaria AS (
    SELECT (fecha AT TIME ZONE 'America/Guatemala')::date AS dia,sum(total) AS total,count(*) AS transacciones,sum(unidades) AS unidades
    FROM validas GROUP BY (fecha AT TIME ZONE 'America/Guatemala')::date
  ), serie AS (
    SELECT p_desde+i AS dia,coalesce(v.total,0) AS total,coalesce(v.transacciones,0) AS transacciones,coalesce(v.unidades,0) AS unidades
    FROM generate_series(0,p_hasta-p_desde)i LEFT JOIN venta_diaria v ON v.dia=p_desde+i
  ), vendido AS (
    SELECT d.producto_id,sum(d.cantidad) AS unidades,sum(d.subtotal) AS importe
    FROM public.detalle_ventas d JOIN validas v ON v.id_venta=d.venta_id GROUP BY d.producto_id
  ), ranking AS (
    SELECT p.id_producto,p.nombre,p.codigo_barras,p.activo,p.existencia AS existencia_actual,p.existencia_minima,
      coalesce(v.unidades,0) AS unidades,coalesce(v.importe,0) AS importe
    FROM public.productos p LEFT JOIN vendido v ON v.producto_id=p.id_producto
  ), top_unidades AS (
    SELECT * FROM ranking WHERE unidades>0 ORDER BY unidades DESC,importe DESC,nombre,id_producto LIMIT 20
  ), top_importe AS (
    SELECT * FROM ranking WHERE unidades>0 ORDER BY importe DESC,unidades DESC,nombre,id_producto LIMIT 20
  ), menor_venta AS (
    SELECT * FROM ranking WHERE activo ORDER BY unidades,importe,nombre,id_producto LIMIT 20
  ), pago AS (
    SELECT f.nombre,count(*) AS transacciones,sum(v.total) AS total FROM validas v JOIN public.formas_pago f ON f.id_forma_pago=v.forma_pago_id GROUP BY f.nombre
  ), incidencias AS (
    SELECT id_venta,total,total_detalles FROM revisadas WHERE NOT valida ORDER BY fecha DESC,id_venta DESC LIMIT 20
  )
  SELECT jsonb_build_object('desde',p_desde,'hasta',p_hasta,'dias',p_hasta-p_desde+1,'actualizado',CURRENT_TIMESTAMP,
    'ventas',coalesce(sum(total),0),'transacciones',count(*),'ticket_promedio',CASE WHEN count(*)=0 THEN 0 ELSE round(sum(total)/count(*),2) END,
    'unidades',coalesce(sum(unidades),0),'productos_vendidos',(SELECT count(*) FROM vendido),
    'activos_sin_ventas',(SELECT count(*) FROM ranking WHERE activo AND unidades=0),
    'ventas_credito',coalesce((SELECT sum(total) FROM pago WHERE nombre='CREDITO'),0),
    'ventas_sin_credito',coalesce((SELECT sum(total) FROM pago WHERE nombre<>'CREDITO'),0),
    'serie',coalesce((SELECT jsonb_agg(to_jsonb(s) ORDER BY s.dia) FROM serie s),'[]'::jsonb),
    'top_unidades',coalesce((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.unidades DESC,t.importe DESC,t.nombre,t.id_producto) FROM top_unidades t),'[]'::jsonb),
    'top_importe',coalesce((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.importe DESC,t.unidades DESC,t.nombre,t.id_producto) FROM top_importe t),'[]'::jsonb),
    'menor_venta',coalesce((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.unidades,t.importe,t.nombre,t.id_producto) FROM menor_venta t),'[]'::jsonb),
    'por_pago',coalesce((SELECT jsonb_agg(to_jsonb(p) ORDER BY p.nombre) FROM pago p),'[]'::jsonb),
    'inconsistencias_total',(SELECT count(*) FROM revisadas WHERE NOT valida),
    'inconsistencias',coalesce((SELECT jsonb_agg(to_jsonb(i) ORDER BY i.id_venta DESC) FROM incidencias i),'[]'::jsonb)) INTO v_resultado FROM validas;
  RETURN v_resultado;
END;
$fn$;
REVOKE ALL ON FUNCTION public.obtener_reporte_ventas(date,date) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.obtener_reporte_ventas(date,date) TO authenticated;
COMMIT;
