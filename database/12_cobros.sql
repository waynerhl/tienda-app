-- Clientes y cuentas por cobrar. Aplicar una vez después de ventas y dashboard.
-- La escritura del abono es atómica; el navegador nunca calcula el saldo definitivo.
BEGIN;
ALTER TABLE public.pagos_cuentas_por_cobrar ADD COLUMN IF NOT EXISTS solicitud_id uuid;
CREATE UNIQUE INDEX IF NOT EXISTS pagos_cxc_solicitud_uidx
  ON public.pagos_cuentas_por_cobrar(solicitud_id) WHERE solicitud_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS pagos_cxc_cuenta_fecha_idx
  ON public.pagos_cuentas_por_cobrar(cuenta_por_cobrar_id, fecha DESC, id_pago_cuenta_por_cobrar DESC);

CREATE SCHEMA IF NOT EXISTS tienda_privada;
REVOKE ALL ON SCHEMA tienda_privada FROM PUBLIC, anon;
GRANT USAGE ON SCHEMA tienda_privada TO authenticated;

CREATE OR REPLACE FUNCTION tienda_privada.registrar_abono_cxc(
  p_solicitud_id uuid, p_cuenta_id integer, p_forma_pago_id integer, p_monto numeric
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
SET timezone = 'America/Guatemala' AS $fn$
DECLARE
  v_usuario uuid := auth.uid();
  v_anterior public.pagos_cuentas_por_cobrar%ROWTYPE;
  v_cuenta public.cuentas_por_cobrar%ROWTYPE;
  v_venta integer;
  v_cliente integer;
  v_pago integer;
  v_saldo numeric;
BEGIN
  IF v_usuario IS NULL OR NOT public.fn_tiene_rol(ARRAY['ADMINISTRADOR','CAJERO']) THEN
    RAISE EXCEPTION 'No tienes permiso para registrar abonos.' USING ERRCODE='42501';
  END IF;
  IF p_solicitud_id IS NULL OR p_cuenta_id IS NULL OR p_forma_pago_id IS NULL
     OR p_monto IS NULL OR p_monto <= 0 OR p_monto > 9999999999.99
     OR p_monto <> trunc(p_monto,2) THEN
    RAISE EXCEPTION 'Indica una cuenta, una forma de pago y un monto mayor que cero con hasta dos decimales.' USING ERRCODE='22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('abono-cxc:' || p_solicitud_id::text,0));
  SELECT * INTO v_anterior FROM public.pagos_cuentas_por_cobrar WHERE solicitud_id=p_solicitud_id;
  IF FOUND THEN
    IF v_anterior.usuario_id<>v_usuario OR v_anterior.cuenta_por_cobrar_id<>p_cuenta_id
       OR v_anterior.forma_pago_id<>p_forma_pago_id OR v_anterior.monto<>p_monto THEN
      RAISE EXCEPTION 'Esta referencia ya corresponde a otro abono.' USING ERRCODE='22023';
    END IF;
    SELECT saldo_pendiente INTO v_saldo FROM public.cuentas_por_cobrar WHERE id_cuenta_por_cobrar=p_cuenta_id;
    RETURN jsonb_build_object('id_pago',v_anterior.id_pago_cuenta_por_cobrar,'cuenta_id',p_cuenta_id,
      'monto',v_anterior.monto,'saldo_pendiente',v_saldo,'repetida',true);
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.formas_pago WHERE id_forma_pago=p_forma_pago_id AND nombre<>'CREDITO') THEN
    RAISE EXCEPTION 'Selecciona una forma de pago distinta de crédito.' USING ERRCODE='22023';
  END IF;
  SELECT v.id_venta,v.cliente_id INTO v_venta,v_cliente
  FROM public.ventas v JOIN public.cuentas_por_cobrar c ON c.venta_id=v.id_venta
  JOIN public.formas_pago fp ON fp.id_forma_pago=v.forma_pago_id
  WHERE c.id_cuenta_por_cobrar=p_cuenta_id AND v.estado='REGISTRADA' AND fp.nombre='CREDITO'
  FOR UPDATE OF v;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'La cuenta no existe o su venta ya no está registrada a crédito.' USING ERRCODE='22023';
  END IF;
  -- Serializa las operaciones de crédito del mismo cliente con los triggers existentes.
  PERFORM 1 FROM public.clientes WHERE id_cliente=v_cliente FOR UPDATE;
  SELECT * INTO STRICT v_cuenta FROM public.cuentas_por_cobrar WHERE id_cuenta_por_cobrar=p_cuenta_id FOR UPDATE;
  IF NOT EXISTS(SELECT 1 FROM public.detalle_ventas WHERE venta_id=v_venta)
     OR (SELECT coalesce(sum(subtotal),0) FROM public.detalle_ventas WHERE venta_id=v_venta)
        <> (SELECT total FROM public.ventas WHERE id_venta=v_venta)
     OR v_cuenta.monto_original<>(SELECT total FROM public.ventas WHERE id_venta=v_venta)
     OR v_cuenta.saldo_pendiente<>v_cuenta.monto_original-
        (SELECT coalesce(sum(monto),0) FROM public.pagos_cuentas_por_cobrar WHERE cuenta_por_cobrar_id=p_cuenta_id) THEN
    RAISE EXCEPTION 'La cuenta tiene registros inconsistentes. Revísala antes de cobrar.' USING ERRCODE='22023';
  END IF;
  IF p_monto>v_cuenta.saldo_pendiente THEN
    RAISE EXCEPTION 'El abono supera el saldo actual de Q %.',v_cuenta.saldo_pendiente USING ERRCODE='22023';
  END IF;
  INSERT INTO public.pagos_cuentas_por_cobrar(cuenta_por_cobrar_id,usuario_id,forma_pago_id,monto,solicitud_id)
  VALUES(p_cuenta_id,v_usuario,p_forma_pago_id,p_monto,p_solicitud_id)
  RETURNING id_pago_cuenta_por_cobrar INTO v_pago;
  -- Los triggers existentes validan y recalculan el saldo dentro de esta transacción.
  SELECT saldo_pendiente INTO v_saldo FROM public.cuentas_por_cobrar WHERE id_cuenta_por_cobrar=p_cuenta_id;
  RETURN jsonb_build_object('id_pago',v_pago,'cuenta_id',p_cuenta_id,'monto',p_monto,
    'saldo_pendiente',v_saldo,'repetida',false);
END;
$fn$;
REVOKE ALL ON FUNCTION tienda_privada.registrar_abono_cxc(uuid,integer,integer,numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION tienda_privada.registrar_abono_cxc(uuid,integer,integer,numeric) TO authenticated;

CREATE OR REPLACE FUNCTION public.registrar_abono_cxc(
  p_solicitud_id uuid,p_cuenta_id integer,p_forma_pago_id integer,p_monto numeric
) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path = '' AS $fn$
  SELECT tienda_privada.registrar_abono_cxc(p_solicitud_id,p_cuenta_id,p_forma_pago_id,p_monto);
$fn$;
REVOKE ALL ON FUNCTION public.registrar_abono_cxc(uuid,integer,integer,numeric) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.registrar_abono_cxc(uuid,integer,integer,numeric) TO authenticated;

CREATE OR REPLACE FUNCTION public.listar_clientes_cobros(p_busqueda text DEFAULT '',p_pagina integer DEFAULT 0)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $fn$
DECLARE v_resultado jsonb; v_hoy date := (CURRENT_TIMESTAMP AT TIME ZONE 'America/Guatemala')::date;
BEGIN
  IF auth.uid() IS NULL OR NOT public.fn_tiene_rol(ARRAY['ADMINISTRADOR','CAJERO']) THEN
    RAISE EXCEPTION 'No tienes permiso para consultar clientes.' USING ERRCODE='42501';
  END IF;
  IF p_pagina IS NULL OR p_pagina<0 OR p_pagina>1000000 OR p_busqueda IS NULL OR length(p_busqueda)>150 THEN
    RAISE EXCEPTION 'Revisa la búsqueda o la página.' USING ERRCODE='22023';
  END IF;
  WITH encontrados AS (
    SELECT * FROM public.clientes
    WHERE strpos(lower(nombre),lower(trim(p_busqueda)))>0
       OR strpos(coalesce(telefono,''),trim(p_busqueda))>0
  ), pagina AS (
    SELECT * FROM encontrados ORDER BY nombre,id_cliente LIMIT 20 OFFSET p_pagina*20
  ), saldos AS (
    SELECT v.cliente_id,sum(c.saldo_pendiente) AS saldo,
      coalesce(sum(c.saldo_pendiente) FILTER(WHERE c.fecha_limite<v_hoy),0) AS vencido
    FROM public.cuentas_por_cobrar c JOIN public.ventas v ON v.id_venta=c.venta_id
    WHERE v.estado='REGISTRADA' GROUP BY v.cliente_id
  )
  SELECT jsonb_build_object('total',(SELECT count(*) FROM encontrados),'clientes',
    coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.nombre,x.id_cliente) FROM
      (SELECT p.*,coalesce(s.saldo,0) AS saldo,coalesce(s.vencido,0) AS vencido
       FROM pagina p LEFT JOIN saldos s ON s.cliente_id=p.id_cliente)x),'[]'::jsonb)) INTO v_resultado;
  RETURN v_resultado;
END;
$fn$;
REVOKE ALL ON FUNCTION public.listar_clientes_cobros(text,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.listar_clientes_cobros(text,integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.obtener_cobros_cliente(p_cliente_id integer,p_pagina integer DEFAULT 0)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $fn$
DECLARE v_resultado jsonb; v_hoy date := (CURRENT_TIMESTAMP AT TIME ZONE 'America/Guatemala')::date;
BEGIN
  IF auth.uid() IS NULL OR NOT public.fn_tiene_rol(ARRAY['ADMINISTRADOR','CAJERO']) THEN
    RAISE EXCEPTION 'No tienes permiso para consultar cuentas.' USING ERRCODE='42501';
  END IF;
  IF p_pagina IS NULL OR p_pagina<0 OR p_pagina>1000000 THEN
    RAISE EXCEPTION 'Página inválida.' USING ERRCODE='22023';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.clientes WHERE id_cliente=p_cliente_id) THEN
    RAISE EXCEPTION 'Cliente no encontrado.' USING ERRCODE='22023';
  END IF;
  WITH cuentas AS (
    SELECT c.id_cuenta_por_cobrar,c.venta_id,c.monto_original,c.saldo_pendiente,c.fecha_limite,v.fecha,
      CASE WHEN c.saldo_pendiente=0 THEN 'PAGADA' WHEN c.fecha_limite<v_hoy THEN 'VENCIDA' ELSE 'PENDIENTE' END AS estado
    FROM public.cuentas_por_cobrar c JOIN public.ventas v ON v.id_venta=c.venta_id
    WHERE v.cliente_id=p_cliente_id AND v.estado='REGISTRADA'
  ), pagina AS (
    SELECT * FROM cuentas ORDER BY (saldo_pendiente>0) DESC,fecha DESC,id_cuenta_por_cobrar DESC
    LIMIT 20 OFFSET p_pagina*20
  )
  SELECT jsonb_build_object('cliente',(SELECT to_jsonb(c) FROM public.clientes c WHERE id_cliente=p_cliente_id),
    'total',(SELECT count(*) FROM cuentas),
    'saldo',(SELECT coalesce(sum(saldo_pendiente),0) FROM cuentas),
    'vencido',(SELECT coalesce(sum(saldo_pendiente) FILTER(WHERE estado='VENCIDA'),0) FROM cuentas),
    'cuentas',coalesce((SELECT jsonb_agg(to_jsonb(p) ORDER BY (p.saldo_pendiente>0) DESC,p.fecha DESC,p.id_cuenta_por_cobrar DESC) FROM pagina p),'[]'::jsonb)) INTO v_resultado;
  RETURN v_resultado;
END;
$fn$;
REVOKE ALL ON FUNCTION public.obtener_cobros_cliente(integer,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.obtener_cobros_cliente(integer,integer) TO authenticated;
-- Un abono debe poder reducir una deuda aunque el límite se haya bajado después.
CREATE OR REPLACE FUNCTION public.fn_validar_cuenta_por_cobrar()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE
    v_cliente_id INTEGER;
    v_total_venta NUMERIC(12,2);
    v_estado_venta VARCHAR(30);
    v_forma_pago VARCHAR(150);

    v_limite_credito NUMERIC(12,2);
    v_deuda_actual NUMERIC(12,2);

    v_total_pagado NUMERIC(12,2);
    v_nuevo_saldo NUMERIC(12,2);
BEGIN

    /* =====================================================
       Obtener información de la venta
       ===================================================== */

    SELECT
        v.cliente_id,
        v.total,
        v.estado,
        fp.nombre
    INTO
        v_cliente_id,
        v_total_venta,
        v_estado_venta,
        v_forma_pago
    FROM public.ventas v
    JOIN public.formas_pago fp
        ON fp.id_forma_pago = v.forma_pago_id
    WHERE v.id_venta = NEW.venta_id
    FOR UPDATE OF v;


    /* =====================================================
       La venta debe tener cliente
       ===================================================== */

    IF v_cliente_id IS NULL THEN
        RAISE EXCEPTION
            'No se puede generar una cuenta por cobrar para una venta sin cliente';
    END IF;


    /* =====================================================
       La venta debe estar registrada
       ===================================================== */

    IF v_estado_venta <> 'REGISTRADA' THEN
        RAISE EXCEPTION
            'No se puede generar una cuenta por cobrar para una venta %',
            v_estado_venta;
    END IF;


    /* =====================================================
       Debe ser una venta a crédito
       ===================================================== */

    IF v_forma_pago <> 'CREDITO' THEN
        RAISE EXCEPTION
            'La venta no fue registrada como venta a crédito';
    END IF;


    /* =====================================================
       La deuda debe coincidir con el total de la venta
       ===================================================== */

    IF NEW.monto_original <> v_total_venta THEN
        RAISE EXCEPTION
            'El monto de la cuenta (%) debe coincidir con el total de la venta (%)',
            NEW.monto_original,
            v_total_venta;
    END IF;


    /* =====================================================
       Calcular pagos existentes

       Esto también permite modificar el monto posteriormente
       sin crear un saldo incoherente.
       ===================================================== */

    IF TG_OP = 'UPDATE' THEN

        SELECT COALESCE(SUM(monto), 0)
        INTO v_total_pagado
        FROM public.pagos_cuentas_por_cobrar
        WHERE cuenta_por_cobrar_id =
            OLD.id_cuenta_por_cobrar;

    ELSE

        v_total_pagado := 0;

    END IF;


    v_nuevo_saldo :=
        NEW.monto_original - v_total_pagado;


    IF v_nuevo_saldo < 0 THEN
        RAISE EXCEPTION
            'El nuevo monto de la deuda es menor que lo ya pagado';
    END IF;


    /* =====================================================
       Revisar límite de crédito
       ===================================================== */

    SELECT limite_credito
    INTO v_limite_credito
    FROM public.clientes
    WHERE id_cliente = v_cliente_id
    FOR UPDATE;


    SELECT COALESCE(SUM(cpc.saldo_pendiente), 0)
    INTO v_deuda_actual
    FROM public.cuentas_por_cobrar cpc

    JOIN public.ventas v
        ON v.id_venta = cpc.venta_id

    WHERE v.cliente_id = v_cliente_id

      AND (
          TG_OP = 'INSERT'
          OR cpc.id_cuenta_por_cobrar
             <> OLD.id_cuenta_por_cobrar
      );


    IF (TG_OP = 'INSERT' OR v_nuevo_saldo > OLD.saldo_pendiente)
       AND v_limite_credito IS NOT NULL
       AND v_deuda_actual + v_nuevo_saldo
           > v_limite_credito THEN

        RAISE EXCEPTION
            'Límite de crédito excedido. Límite: %, deuda actual: %, nueva deuda: %',
            v_limite_credito,
            v_deuda_actual,
            v_nuevo_saldo;

    END IF;


    /* =====================================================
       PostgreSQL determina saldo y estado inicial
       ===================================================== */

    NEW.saldo_pendiente := v_nuevo_saldo;


    IF v_nuevo_saldo = 0 THEN

        NEW.estado := 'PAGADA';

    ELSIF NEW.fecha_limite IS NOT NULL
          AND NEW.fecha_limite < CURRENT_DATE THEN

        NEW.estado := 'VENCIDA';

    ELSE

        NEW.estado := 'PENDIENTE';

    END IF;


    RETURN NEW;
END;
$function$;

COMMIT;
