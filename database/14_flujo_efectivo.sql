-- Flujo de efectivo registrado. No es un arqueo ni un saldo disponible de caja.
BEGIN;
CREATE OR REPLACE FUNCTION public.obtener_flujo_efectivo(p_fecha date,p_pagina integer DEFAULT 0)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $fn$
DECLARE
  v_inicio timestamptz; v_fin timestamptz; v_resultado jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT public.fn_tiene_rol(ARRAY['ADMINISTRADOR']) THEN
    RAISE EXCEPTION 'Solo el administrador puede consultar el flujo completo de efectivo.' USING ERRCODE='42501';
  END IF;
  IF p_fecha IS NULL OR p_fecha<'1900-01-01'::date OR p_fecha>'2100-12-31'::date
     OR p_pagina IS NULL OR p_pagina<0 OR p_pagina>1000000 THEN
    RAISE EXCEPTION 'Revisa la fecha o la página seleccionada.' USING ERRCODE='22023';
  END IF;
  v_inicio:=p_fecha::timestamp AT TIME ZONE 'America/Guatemala';
  v_fin:=(p_fecha+1)::timestamp AT TIME ZONE 'America/Guatemala';
  WITH candidatos AS (
    SELECT 'VENTA'::text AS tipo,v.id_venta AS id,v.id_venta AS documento_id,v.fecha,
      coalesce(c.nombre,'Consumidor final')::text AS contraparte,
      ('Venta #'||v.id_venta)::text AS referencia,v.total AS entrada,0::numeric AS salida,
      true AS es_venta,true AS cuenta_consistente,v.total AS total_documento
    FROM public.ventas v JOIN public.formas_pago fp ON fp.id_forma_pago=v.forma_pago_id
    LEFT JOIN public.clientes c ON c.id_cliente=v.cliente_id
    WHERE v.estado='REGISTRADA' AND fp.nombre='EFECTIVO' AND v.fecha>=v_inicio AND v.fecha<v_fin
    UNION ALL
    SELECT 'COBRO_CLIENTE',p.id_pago_cuenta_por_cobrar,v.id_venta,p.fecha,coalesce(c.nombre,'Cliente'),
      'Abono #'||p.id_pago_cuenta_por_cobrar||' · Venta #'||v.id_venta,p.monto,0,true,
      fpv.nombre='CREDITO' AND cc.monto_original=v.total
        AND cc.saldo_pendiente=cc.monto_original-(SELECT coalesce(sum(pp.monto),0) FROM public.pagos_cuentas_por_cobrar pp WHERE pp.cuenta_por_cobrar_id=cc.id_cuenta_por_cobrar),
      v.total
    FROM public.pagos_cuentas_por_cobrar p JOIN public.formas_pago fp ON fp.id_forma_pago=p.forma_pago_id
    JOIN public.cuentas_por_cobrar cc ON cc.id_cuenta_por_cobrar=p.cuenta_por_cobrar_id
    JOIN public.ventas v ON v.id_venta=cc.venta_id JOIN public.formas_pago fpv ON fpv.id_forma_pago=v.forma_pago_id
    LEFT JOIN public.clientes c ON c.id_cliente=v.cliente_id
    WHERE v.estado='REGISTRADA' AND fp.nombre='EFECTIVO' AND p.monto>0 AND p.fecha>=v_inicio AND p.fecha<v_fin
    UNION ALL
    SELECT 'COMPRA',co.id_compra,co.id_compra,co.fecha,pr.nombre,
      'Compra #'||co.id_compra||coalesce(' · '||co.numero_documento,''),0,co.total,false,true,co.total
    FROM public.compras co JOIN public.formas_pago fp ON fp.id_forma_pago=co.forma_pago_id
    JOIN public.proveedores pr ON pr.id_proveedor=co.proveedor_id
    WHERE co.estado='REGISTRADA' AND fp.nombre='EFECTIVO' AND co.fecha>=v_inicio AND co.fecha<v_fin
    UNION ALL
    SELECT 'PAGO_PROVEEDOR',p.id_pago_cuenta_por_pagar,co.id_compra,p.fecha,pr.nombre,
      'Pago #'||p.id_pago_cuenta_por_pagar||' · Compra #'||co.id_compra,0,p.monto,false,
      fpc.nombre='CREDITO' AND cp.monto_original=co.total
        AND cp.saldo_pendiente=cp.monto_original-(SELECT coalesce(sum(pp.monto),0) FROM public.pagos_cuentas_por_pagar pp WHERE pp.cuenta_por_pagar_id=cp.id_cuenta_por_pagar),
      co.total
    FROM public.pagos_cuentas_por_pagar p JOIN public.formas_pago fp ON fp.id_forma_pago=p.forma_pago_id
    JOIN public.cuentas_por_pagar cp ON cp.id_cuenta_por_pagar=p.cuenta_por_pagar_id
    JOIN public.compras co ON co.id_compra=cp.compra_id JOIN public.formas_pago fpc ON fpc.id_forma_pago=co.forma_pago_id
    JOIN public.proveedores pr ON pr.id_proveedor=co.proveedor_id
    WHERE co.estado='REGISTRADA' AND fp.nombre='EFECTIVO' AND p.monto>0 AND p.fecha>=v_inicio AND p.fecha<v_fin
  ), comprobados AS (
    SELECT ca.*,ca.cuenta_consistente AND CASE WHEN ca.es_venta THEN
      EXISTS(SELECT 1 FROM public.detalle_ventas d WHERE d.venta_id=ca.documento_id)
      AND ca.total_documento=(SELECT coalesce(sum(d.subtotal),0) FROM public.detalle_ventas d WHERE d.venta_id=ca.documento_id)
      ELSE EXISTS(SELECT 1 FROM public.detalle_compras d WHERE d.compra_id=ca.documento_id)
      AND ca.total_documento=(SELECT coalesce(sum(d.subtotal),0) FROM public.detalle_compras d WHERE d.compra_id=ca.documento_id)
      END AS consistente
    FROM candidatos ca
  ), validos AS (
    SELECT tipo,id,fecha,contraparte,referencia,entrada,salida FROM comprobados WHERE consistente AND (entrada>0 OR salida>0)
  ), pagina AS (
    SELECT * FROM validos ORDER BY fecha DESC,tipo,id DESC LIMIT 20 OFFSET p_pagina*20
  ), problemas AS (
    SELECT tipo,id,referencia FROM comprobados WHERE NOT consistente ORDER BY fecha DESC,tipo,id DESC LIMIT 20
  )
  SELECT jsonb_build_object('fecha',p_fecha,'actualizado',CURRENT_TIMESTAMP,
    'entradas',coalesce(sum(entrada),0),'salidas',coalesce(sum(salida),0),
    'variacion',coalesce(sum(entrada-salida),0),'total_movimientos',count(*),
    'ventas_efectivo',coalesce(sum(entrada) FILTER(WHERE tipo='VENTA'),0),
    'cobros_clientes',coalesce(sum(entrada) FILTER(WHERE tipo='COBRO_CLIENTE'),0),
    'compras_efectivo',coalesce(sum(salida) FILTER(WHERE tipo='COMPRA'),0),
    'pagos_proveedores',coalesce(sum(salida) FILTER(WHERE tipo='PAGO_PROVEEDOR'),0),
    'movimientos',coalesce((SELECT jsonb_agg(to_jsonb(p) ORDER BY p.fecha DESC,p.tipo,p.id DESC) FROM pagina p),'[]'::jsonb),
    'inconsistencias_total',(SELECT count(*) FROM comprobados WHERE NOT consistente),
    'inconsistencias',coalesce((SELECT jsonb_agg(to_jsonb(p)) FROM problemas p),'[]'::jsonb)) INTO v_resultado FROM validos;
  RETURN v_resultado;
END;
$fn$;
REVOKE ALL ON FUNCTION public.obtener_flujo_efectivo(date,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.obtener_flujo_efectivo(date,integer) TO authenticated;
COMMIT;
