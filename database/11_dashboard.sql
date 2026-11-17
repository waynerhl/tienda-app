-- Copia del resumen operativo ya aplicado en Supabase.
BEGIN;
CREATE OR REPLACE FUNCTION public.obtener_dashboard()
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE
 v_hoy date:=(CURRENT_TIMESTAMP AT TIME ZONE 'America/Guatemala')::date;
 v_resultado jsonb;
BEGIN
 IF auth.uid() IS NULL OR NOT public.fn_tiene_rol(ARRAY['ADMINISTRADOR']::text[]) THEN
  RAISE EXCEPTION 'El dashboard está disponible para el administrador activo' USING ERRCODE='42501';
 END IF;
 WITH detalles AS (
  SELECT venta_id,sum(subtotal) total_detalles,count(*) lineas FROM public.detalle_ventas GROUP BY venta_id
 ), revisadas AS (
  SELECT v.*,coalesce(d.total_detalles,0) total_detalles,
   (coalesce(d.lineas,0)>0 AND v.total=d.total_detalles) consistente
  FROM public.ventas v LEFT JOIN detalles d ON d.venta_id=v.id_venta WHERE v.estado='REGISTRADA'
 ), validas AS (
  SELECT * FROM revisadas WHERE consistente
 ), hoy AS (
  SELECT * FROM validas WHERE fecha>=(v_hoy::timestamp AT TIME ZONE 'America/Guatemala')
   AND fecha<((v_hoy+1)::timestamp AT TIME ZONE 'America/Guatemala')
 ), inventario AS (
  SELECT * FROM public.productos WHERE activo
 ), lotes_stock AS (
  SELECT l.id_lote,l.numero_lote,l.fecha_vencimiento,p.nombre producto,
   public.fn_stock_lote(l.id_lote) existencia
  FROM public.lotes l JOIN public.detalle_compras dc ON dc.id_detalle_compra=l.detalle_compra_id
  JOIN public.compras c ON c.id_compra=dc.compra_id
  JOIN public.productos p ON p.id_producto=dc.producto_id
  WHERE p.activo AND c.estado='REGISTRADA' AND l.fecha_vencimiento IS NOT NULL
 ), lotes AS (
  SELECT *,fecha_vencimiento-v_hoy dias FROM lotes_stock WHERE existencia>0
 ), dias AS (
  SELECT v_hoy-6+n dia FROM generate_series(0,6) AS serie(n)
 ), serie AS (
  SELECT d.dia,coalesce(sum(v.total),0) total,count(v.id_venta) transacciones
  FROM dias d LEFT JOIN validas v
   ON v.fecha>=(d.dia::timestamp AT TIME ZONE 'America/Guatemala')
    AND v.fecha<((d.dia+1)::timestamp AT TIME ZONE 'America/Guatemala')
  GROUP BY d.dia
 ), cobrar AS (
  SELECT c.* FROM public.cuentas_por_cobrar c JOIN public.ventas v ON v.id_venta=c.venta_id
  WHERE v.estado='REGISTRADA' AND c.saldo_pendiente>0
 ), pagar AS (
  SELECT c.* FROM public.cuentas_por_pagar c JOIN public.compras p ON p.id_compra=c.compra_id
  WHERE p.estado='REGISTRADA' AND c.saldo_pendiente>0
 )
 SELECT jsonb_build_object(
  'fecha',v_hoy,'actualizado',CURRENT_TIMESTAMP,
  'ventas_hoy',coalesce((SELECT sum(total) FROM hoy),0),
  'transacciones_hoy',(SELECT count(*) FROM hoy),
  'ticket_promedio',coalesce((SELECT avg(total) FROM hoy),0),
  'productos_activos',(SELECT count(*) FROM inventario),
  'agotados',(SELECT count(*) FROM inventario WHERE existencia=0),
  'bajo_minimo',(SELECT count(*) FROM inventario WHERE existencia>0 AND existencia<=existencia_minima),
  'lotes_proximos',(SELECT count(*) FROM lotes WHERE dias BETWEEN 0 AND 30),
  'lotes_vencidos',(SELECT count(*) FROM lotes WHERE dias<0),
  'por_cobrar',coalesce((SELECT sum(saldo_pendiente) FROM cobrar),0),
  'por_cobrar_vencido',coalesce((SELECT sum(saldo_pendiente) FROM cobrar WHERE fecha_limite<v_hoy),0),
  'por_pagar',coalesce((SELECT sum(saldo_pendiente) FROM pagar),0),
  'por_pagar_vencido',coalesce((SELECT sum(saldo_pendiente) FROM pagar WHERE fecha_limite<v_hoy),0),
  'ventas_inconsistentes',(SELECT count(*) FROM revisadas WHERE NOT consistente),
  'inconsistencias',coalesce((SELECT jsonb_agg(to_jsonb(x)) FROM (
   SELECT id_venta,total,total_detalles FROM revisadas WHERE NOT consistente ORDER BY id_venta LIMIT 20
  )x),'[]'::jsonb),
  'serie',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.dia) FROM serie x),'[]'::jsonb),
  'reponer',coalesce((SELECT jsonb_agg(to_jsonb(x)) FROM (
   SELECT id_producto,nombre,existencia,existencia_minima FROM inventario
   WHERE existencia<=existencia_minima ORDER BY existencia,nombre,id_producto LIMIT 20
  )x),'[]'::jsonb),
  'vencimientos',coalesce((SELECT jsonb_agg(to_jsonb(x)) FROM (
   SELECT id_lote,numero_lote,producto,fecha_vencimiento,existencia,dias FROM lotes
   WHERE dias<=30 ORDER BY fecha_vencimiento,id_lote LIMIT 20
  )x),'[]'::jsonb)
 ) INTO v_resultado;
 RETURN v_resultado;
END;
$function$;
REVOKE ALL ON FUNCTION public.obtener_dashboard() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.obtener_dashboard() TO authenticated;
COMMIT;
