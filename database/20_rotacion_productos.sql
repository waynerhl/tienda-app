BEGIN;
-- Ventas históricas verificadas y stock actual, en una sola instantánea de lectura.
CREATE OR REPLACE FUNCTION public.obtener_rotacion_productos(
  p_desde date, p_hasta date, p_objetivo integer DEFAULT 7,
  p_busqueda text DEFAULT '', p_filtro text DEFAULT 'todos',
  p_orden text DEFAULT 'reponer', p_pagina integer DEFAULT 0
)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path='' AS $fn$
DECLARE
  v_hoy date := (CURRENT_TIMESTAMP AT TIME ZONE 'America/Guatemala')::date;
  v_dias integer; v_inicio timestamptz; v_fin timestamptz; v_resultado jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT public.fn_tiene_rol(ARRAY['ADMINISTRADOR']) THEN
    RAISE EXCEPTION 'Solo el administrador puede consultar la rotación.' USING ERRCODE='42501';
  END IF;
  IF p_desde IS NULL OR p_hasta IS NULL OR p_desde<'1900-01-01'::date OR p_desde>p_hasta OR p_hasta>v_hoy OR p_hasta-p_desde>365 THEN
    RAISE EXCEPTION 'Selecciona un período válido de hasta 366 días, sin fechas futuras.' USING ERRCODE='22023';
  END IF;
  IF p_objetivo IS NULL OR p_objetivo<1 OR p_objetivo>90 OR p_busqueda IS NULL OR length(p_busqueda)>150
    OR p_filtro IS NULL OR p_filtro NOT IN ('todos','reponer','sin_ventas','revisar')
    OR p_orden IS NULL OR p_orden NOT IN ('reponer','mas','menos')
    OR p_pagina IS NULL OR p_pagina<0 OR p_pagina>1000000 THEN
    RAISE EXCEPTION 'Revisa el objetivo, los filtros o la página.' USING ERRCODE='22023';
  END IF;
  v_dias:=p_hasta-p_desde+1;
  v_inicio:=p_desde::timestamp AT TIME ZONE 'America/Guatemala';
  v_fin:=(p_hasta+1)::timestamp AT TIME ZONE 'America/Guatemala';
  WITH candidatas AS (
    SELECT id_venta,total FROM public.ventas
    WHERE estado='REGISTRADA' AND fecha>=v_inicio AND fecha<v_fin
  ), revisadas AS (
    SELECT v.id_venta, count(d.id_detalle_venta)>0 AND v.total=coalesce(sum(d.subtotal),0) AS valida
    FROM candidatas v LEFT JOIN public.detalle_ventas d ON d.venta_id=v.id_venta GROUP BY v.id_venta,v.total
  ), vendido AS (
    SELECT d.producto_id,sum(d.cantidad) AS unidades,sum(d.subtotal) AS importe
    FROM public.detalle_ventas d JOIN revisadas v ON v.id_venta=d.venta_id AND v.valida GROUP BY d.producto_id
  ), lotes_stock AS MATERIALIZED (
    SELECT d.producto_id,c.estado,l.fecha_vencimiento,public.fn_stock_lote(l.id_lote) AS stock
    FROM public.lotes l JOIN public.detalle_compras d ON d.id_detalle_compra=l.detalle_compra_id
    JOIN public.compras c ON c.id_compra=d.compra_id
  ), stocks AS (
    SELECT producto_id,sum(stock) AS total,
      coalesce(sum(stock) FILTER(WHERE estado='REGISTRADA'),0) AS registrado,
      coalesce(sum(stock) FILTER(WHERE estado='REGISTRADA' AND (fecha_vencimiento IS NULL OR fecha_vencimiento>=v_hoy)),0) AS apto,
      coalesce(sum(stock) FILTER(WHERE estado='REGISTRADA' AND fecha_vencimiento<v_hoy),0) AS vencido,
      bool_or(stock<0) AS negativo
    FROM lotes_stock GROUP BY producto_id
  ), base AS (
    SELECT p.id_producto,p.nombre,p.codigo_barras,p.existencia,p.existencia_minima,
      coalesce(v.unidades,0) AS unidades,coalesce(v.importe,0) AS importe,
      CASE WHEN p.controla_lotes THEN coalesce(s.apto,0) ELSE p.existencia END AS disponible,
      CASE WHEN p.controla_lotes THEN coalesce(s.vencido,0) ELSE 0 END AS vencido,
      p.controla_lotes AND (coalesce(s.total,0)<>p.existencia OR coalesce(s.registrado,0)<>p.existencia OR coalesce(s.negativo,false)) AS inconsistente
    FROM public.productos p LEFT JOIN vendido v ON v.producto_id=p.id_producto LEFT JOIN stocks s ON s.producto_id=p.id_producto
    WHERE p.activo
  ), calculada AS (
    SELECT b.*,round(unidades::numeric/v_dias,4) AS promedio_diario,
      CASE WHEN unidades>0 AND NOT inconsistente THEN round(disponible::numeric*v_dias/unidades,2) END AS cobertura_dias,
      CASE WHEN unidades>0 AND NOT inconsistente THEN
        greatest(greatest(ceil(unidades::numeric*p_objetivo/v_dias),existencia_minima::numeric+1)-disponible,0)
      END AS sugerencia,
      NOT inconsistente AND disponible<=existencia_minima AS bajo_minimo
    FROM base b
  ), clasificada AS (
    SELECT c.*,CASE WHEN inconsistente THEN 'REVISAR' WHEN unidades=0 THEN 'SIN_VENTAS'
      WHEN sugerencia>0 THEN 'REPONER' ELSE 'SUFICIENTE' END AS estado
    FROM calculada c
  ), filtrada AS (
    SELECT * FROM clasificada WHERE (trim(p_busqueda)='' OR strpos(lower(nombre),lower(trim(p_busqueda)))>0 OR codigo_barras=trim(p_busqueda))
      AND (p_filtro='todos' OR p_filtro='reponer' AND estado='REPONER' OR p_filtro='sin_ventas' AND estado='SIN_VENTAS' OR p_filtro='revisar' AND estado='REVISAR')
  ), ordenada AS (
    SELECT f.*,row_number() OVER(ORDER BY
      CASE WHEN p_orden='reponer' THEN CASE estado WHEN 'REVISAR' THEN 0 WHEN 'REPONER' THEN 1 WHEN 'SIN_VENTAS' THEN 3 ELSE 2 END END,
      CASE WHEN p_orden='reponer' AND estado='REPONER' THEN disponible::numeric*v_dias/nullif(unidades,0) END ASC NULLS LAST,
      CASE WHEN p_orden='mas' THEN unidades END DESC,
      CASE WHEN p_orden='menos' THEN unidades END ASC,
      nombre,id_producto) AS posicion
    FROM filtrada f
  ), pagina AS (SELECT * FROM ordenada ORDER BY posicion LIMIT 20 OFFSET p_pagina*20)
  SELECT jsonb_build_object('desde',p_desde,'hasta',p_hasta,'dias',v_dias,'objetivo',p_objetivo,
    'fecha_stock',v_hoy,'actualizado',CURRENT_TIMESTAMP,'total',(SELECT count(*) FROM filtrada),
    'activos',(SELECT count(*) FROM clasificada),'con_ventas',(SELECT count(*) FROM clasificada WHERE unidades>0),
    'sin_ventas',(SELECT count(*) FROM clasificada WHERE unidades=0),'reponer',(SELECT count(*) FROM clasificada WHERE estado='REPONER'),
    'revisar',(SELECT count(*) FROM clasificada WHERE inconsistente),'bajo_minimo',(SELECT count(*) FROM clasificada WHERE bajo_minimo),
    'ventas_excluidas',(SELECT count(*) FROM revisadas WHERE NOT valida),
    'productos',coalesce((SELECT jsonb_agg(to_jsonb(p)-'posicion' ORDER BY p.posicion) FROM pagina p),'[]'::jsonb)) INTO v_resultado;
  RETURN v_resultado;
END;
$fn$;
REVOKE ALL ON FUNCTION public.obtener_rotacion_productos(date,date,integer,text,text,text,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.obtener_rotacion_productos(date,date,integer,text,text,text,integer) TO authenticated;
COMMIT;
