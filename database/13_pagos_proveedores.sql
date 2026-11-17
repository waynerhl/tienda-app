-- Proveedores y cuentas por pagar. Aplicar después de 12_cobros.sql.
-- La escritura del abono es atómica; el navegador nunca calcula el saldo definitivo.
BEGIN;
ALTER TABLE public.pagos_cuentas_por_pagar ADD COLUMN IF NOT EXISTS solicitud_id uuid;
CREATE UNIQUE INDEX IF NOT EXISTS pagos_cxp_solicitud_uidx
  ON public.pagos_cuentas_por_pagar(solicitud_id) WHERE solicitud_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS pagos_cxp_cuenta_fecha_idx
  ON public.pagos_cuentas_por_pagar(cuenta_por_pagar_id, fecha DESC, id_pago_cuenta_por_pagar DESC);

CREATE SCHEMA IF NOT EXISTS tienda_privada;
REVOKE ALL ON SCHEMA tienda_privada FROM PUBLIC, anon;
GRANT USAGE ON SCHEMA tienda_privada TO authenticated;

CREATE OR REPLACE FUNCTION tienda_privada.registrar_abono_cxp(
  p_solicitud_id uuid, p_cuenta_id integer, p_forma_pago_id integer, p_monto numeric
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
SET timezone = 'America/Guatemala' AS $fn$
DECLARE
  v_usuario uuid := auth.uid();
  v_anterior public.pagos_cuentas_por_pagar%ROWTYPE;
  v_cuenta public.cuentas_por_pagar%ROWTYPE;
  v_compra integer;
  v_proveedor integer;
  v_pago integer;
  v_saldo numeric;
BEGIN
  IF v_usuario IS NULL OR NOT public.fn_tiene_rol(ARRAY['ADMINISTRADOR','INVENTARIO']) THEN
    RAISE EXCEPTION 'No tienes permiso para registrar abonos.' USING ERRCODE='42501';
  END IF;
  IF p_solicitud_id IS NULL OR p_cuenta_id IS NULL OR p_forma_pago_id IS NULL
     OR p_monto IS NULL OR p_monto <= 0 OR p_monto > 9999999999.99
     OR p_monto <> trunc(p_monto,2) THEN
    RAISE EXCEPTION 'Indica una cuenta, una forma de pago y un monto mayor que cero con hasta dos decimales.' USING ERRCODE='22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('abono-cxp:' || p_solicitud_id::text,0));
  SELECT * INTO v_anterior FROM public.pagos_cuentas_por_pagar WHERE solicitud_id=p_solicitud_id;
  IF FOUND THEN
    IF v_anterior.usuario_id<>v_usuario OR v_anterior.cuenta_por_pagar_id<>p_cuenta_id
       OR v_anterior.forma_pago_id<>p_forma_pago_id OR v_anterior.monto<>p_monto THEN
      RAISE EXCEPTION 'Esta referencia ya corresponde a otro abono.' USING ERRCODE='22023';
    END IF;
    SELECT saldo_pendiente INTO v_saldo FROM public.cuentas_por_pagar WHERE id_cuenta_por_pagar=p_cuenta_id;
    RETURN jsonb_build_object('id_pago',v_anterior.id_pago_cuenta_por_pagar,'cuenta_id',p_cuenta_id,
      'monto',v_anterior.monto,'saldo_pendiente',v_saldo,'repetida',true);
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.formas_pago WHERE id_forma_pago=p_forma_pago_id AND nombre<>'CREDITO') THEN
    RAISE EXCEPTION 'Selecciona una forma de pago distinta de crédito.' USING ERRCODE='22023';
  END IF;
  SELECT v.id_compra,v.proveedor_id INTO v_compra,v_proveedor
  FROM public.compras v JOIN public.cuentas_por_pagar c ON c.compra_id=v.id_compra
  JOIN public.formas_pago fp ON fp.id_forma_pago=v.forma_pago_id
  WHERE c.id_cuenta_por_pagar=p_cuenta_id AND v.estado='REGISTRADA' AND fp.nombre='CREDITO'
  FOR UPDATE OF v;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'La cuenta no existe o su compra ya no está registrada a crédito.' USING ERRCODE='22023';
  END IF;
  -- Serializa las operaciones de crédito del mismo proveedor con los triggers existentes.
  PERFORM 1 FROM public.proveedores WHERE id_proveedor=v_proveedor FOR UPDATE;
  SELECT * INTO STRICT v_cuenta FROM public.cuentas_por_pagar WHERE id_cuenta_por_pagar=p_cuenta_id FOR UPDATE;
  IF NOT EXISTS(SELECT 1 FROM public.detalle_compras WHERE compra_id=v_compra)
     OR (SELECT coalesce(sum(subtotal),0) FROM public.detalle_compras WHERE compra_id=v_compra)
        <> (SELECT total FROM public.compras WHERE id_compra=v_compra)
     OR v_cuenta.monto_original<>(SELECT total FROM public.compras WHERE id_compra=v_compra)
     OR v_cuenta.saldo_pendiente<>v_cuenta.monto_original-
        (SELECT coalesce(sum(monto),0) FROM public.pagos_cuentas_por_pagar WHERE cuenta_por_pagar_id=p_cuenta_id) THEN
    RAISE EXCEPTION 'La cuenta tiene registros inconsistentes. Revísala antes de pagar.' USING ERRCODE='22023';
  END IF;
  IF p_monto>v_cuenta.saldo_pendiente THEN
    RAISE EXCEPTION 'El abono supera el saldo actual de Q %.',v_cuenta.saldo_pendiente USING ERRCODE='22023';
  END IF;
  INSERT INTO public.pagos_cuentas_por_pagar(cuenta_por_pagar_id,usuario_id,forma_pago_id,monto,solicitud_id)
  VALUES(p_cuenta_id,v_usuario,p_forma_pago_id,p_monto,p_solicitud_id)
  RETURNING id_pago_cuenta_por_pagar INTO v_pago;
  -- Los triggers existentes validan y recalculan el saldo dentro de esta transacción.
  SELECT saldo_pendiente INTO v_saldo FROM public.cuentas_por_pagar WHERE id_cuenta_por_pagar=p_cuenta_id;
  RETURN jsonb_build_object('id_pago',v_pago,'cuenta_id',p_cuenta_id,'monto',p_monto,
    'saldo_pendiente',v_saldo,'repetida',false);
END;
$fn$;
REVOKE ALL ON FUNCTION tienda_privada.registrar_abono_cxp(uuid,integer,integer,numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION tienda_privada.registrar_abono_cxp(uuid,integer,integer,numeric) TO authenticated;

CREATE OR REPLACE FUNCTION public.registrar_abono_cxp(
  p_solicitud_id uuid,p_cuenta_id integer,p_forma_pago_id integer,p_monto numeric
) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path = '' AS $fn$
  SELECT tienda_privada.registrar_abono_cxp(p_solicitud_id,p_cuenta_id,p_forma_pago_id,p_monto);
$fn$;
REVOKE ALL ON FUNCTION public.registrar_abono_cxp(uuid,integer,integer,numeric) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.registrar_abono_cxp(uuid,integer,integer,numeric) TO authenticated;

CREATE OR REPLACE FUNCTION public.listar_proveedores_pagos(p_busqueda text DEFAULT '',p_pagina integer DEFAULT 0)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $fn$
DECLARE v_resultado jsonb; v_hoy date := (CURRENT_TIMESTAMP AT TIME ZONE 'America/Guatemala')::date;
BEGIN
  IF auth.uid() IS NULL OR NOT public.fn_tiene_rol(ARRAY['ADMINISTRADOR','INVENTARIO']) THEN
    RAISE EXCEPTION 'No tienes permiso para consultar proveedores.' USING ERRCODE='42501';
  END IF;
  IF p_pagina IS NULL OR p_pagina<0 OR p_pagina>1000000 OR p_busqueda IS NULL OR length(p_busqueda)>150 THEN
    RAISE EXCEPTION 'Revisa la búsqueda o la página.' USING ERRCODE='22023';
  END IF;
  WITH encontrados AS (
    SELECT * FROM public.proveedores
    WHERE strpos(lower(nombre),lower(trim(p_busqueda)))>0
       OR strpos(coalesce(telefono,''),trim(p_busqueda))>0
  ), pagina AS (
    SELECT * FROM encontrados ORDER BY nombre,id_proveedor LIMIT 20 OFFSET p_pagina*20
  ), saldos AS (
    SELECT v.proveedor_id,sum(c.saldo_pendiente) AS saldo,
      coalesce(sum(c.saldo_pendiente) FILTER(WHERE c.fecha_limite<v_hoy),0) AS vencido
    FROM public.cuentas_por_pagar c JOIN public.compras v ON v.id_compra=c.compra_id
    WHERE v.estado='REGISTRADA' GROUP BY v.proveedor_id
  )
  SELECT jsonb_build_object('total',(SELECT count(*) FROM encontrados),'proveedores',
    coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.nombre,x.id_proveedor) FROM
      (SELECT p.*,coalesce(s.saldo,0) AS saldo,coalesce(s.vencido,0) AS vencido
       FROM pagina p LEFT JOIN saldos s ON s.proveedor_id=p.id_proveedor)x),'[]'::jsonb)) INTO v_resultado;
  RETURN v_resultado;
END;
$fn$;
REVOKE ALL ON FUNCTION public.listar_proveedores_pagos(text,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.listar_proveedores_pagos(text,integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.obtener_pagos_proveedor(p_proveedor_id integer,p_pagina integer DEFAULT 0)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $fn$
DECLARE v_resultado jsonb; v_hoy date := (CURRENT_TIMESTAMP AT TIME ZONE 'America/Guatemala')::date;
BEGIN
  IF auth.uid() IS NULL OR NOT public.fn_tiene_rol(ARRAY['ADMINISTRADOR','INVENTARIO']) THEN
    RAISE EXCEPTION 'No tienes permiso para consultar cuentas.' USING ERRCODE='42501';
  END IF;
  IF p_pagina IS NULL OR p_pagina<0 OR p_pagina>1000000 THEN
    RAISE EXCEPTION 'Página inválida.' USING ERRCODE='22023';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.proveedores WHERE id_proveedor=p_proveedor_id) THEN
    RAISE EXCEPTION 'Proveedor no encontrado.' USING ERRCODE='22023';
  END IF;
  WITH cuentas AS (
    SELECT c.id_cuenta_por_pagar,c.compra_id,c.monto_original,c.saldo_pendiente,c.fecha_limite,v.fecha,v.numero_documento,
      CASE WHEN c.saldo_pendiente=0 THEN 'PAGADA' WHEN c.fecha_limite<v_hoy THEN 'VENCIDA' ELSE 'PENDIENTE' END AS estado
    FROM public.cuentas_por_pagar c JOIN public.compras v ON v.id_compra=c.compra_id
    WHERE v.proveedor_id=p_proveedor_id AND v.estado='REGISTRADA'
  ), pagina AS (
    SELECT * FROM cuentas ORDER BY (saldo_pendiente>0) DESC,fecha DESC,id_cuenta_por_pagar DESC
    LIMIT 20 OFFSET p_pagina*20
  )
  SELECT jsonb_build_object('proveedor',(SELECT to_jsonb(c) FROM public.proveedores c WHERE id_proveedor=p_proveedor_id),
    'total',(SELECT count(*) FROM cuentas),
    'saldo',(SELECT coalesce(sum(saldo_pendiente),0) FROM cuentas),
    'vencido',(SELECT coalesce(sum(saldo_pendiente) FILTER(WHERE estado='VENCIDA'),0) FROM cuentas),
    'cuentas',coalesce((SELECT jsonb_agg(to_jsonb(p) ORDER BY (p.saldo_pendiente>0) DESC,p.fecha DESC,p.id_cuenta_por_pagar DESC) FROM pagina p),'[]'::jsonb)) INTO v_resultado;
  RETURN v_resultado;
END;
$fn$;
REVOKE ALL ON FUNCTION public.obtener_pagos_proveedor(integer,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.obtener_pagos_proveedor(integer,integer) TO authenticated;
COMMIT;
