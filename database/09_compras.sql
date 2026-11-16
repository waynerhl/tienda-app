-- Corrige referencias de los triggers llamados desde las RPC con search_path vacío.
-- Mantiene SECURITY INVOKER y los permisos actuales.

CREATE OR REPLACE FUNCTION public.fn_recalcular_ultimo_costo(p_producto_id integer)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE
    v_ultimo_costo NUMERIC(12,2);
BEGIN

    SELECT dc.costo_unitario
    INTO v_ultimo_costo
    FROM public.detalle_compras dc

    JOIN public.compras c
        ON c.id_compra = dc.compra_id

    WHERE dc.producto_id = p_producto_id
      AND c.estado = 'REGISTRADA'

    ORDER BY
        c.fecha DESC,
        dc.id_detalle_compra DESC

    LIMIT 1;


    UPDATE public.productos
    SET ultimo_costo = v_ultimo_costo
    WHERE id_producto = p_producto_id;

END;
$function$;


CREATE OR REPLACE FUNCTION public.fn_recalcular_cuenta_por_cobrar(p_cuenta_id integer)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE
    v_monto_original NUMERIC(12,2);
    v_total_pagado NUMERIC(12,2);
    v_saldo NUMERIC(12,2);
    v_fecha_limite DATE;
    v_estado VARCHAR(30);
BEGIN

    SELECT
        monto_original,
        fecha_limite
    INTO
        v_monto_original,
        v_fecha_limite
    FROM public.cuentas_por_cobrar
    WHERE id_cuenta_por_cobrar = p_cuenta_id;


    SELECT COALESCE(SUM(monto), 0)
    INTO v_total_pagado
    FROM public.pagos_cuentas_por_cobrar
    WHERE cuenta_por_cobrar_id = p_cuenta_id;


    v_saldo := v_monto_original - v_total_pagado;


    IF v_saldo = 0 THEN

        v_estado := 'PAGADA';

    ELSIF v_fecha_limite IS NOT NULL
          AND v_fecha_limite < CURRENT_DATE THEN

        v_estado := 'VENCIDA';

    ELSE

        v_estado := 'PENDIENTE';

    END IF;


    UPDATE public.cuentas_por_cobrar
    SET
        saldo_pendiente = v_saldo,
        estado = v_estado
    WHERE id_cuenta_por_cobrar = p_cuenta_id;

END;
$function$;


CREATE OR REPLACE FUNCTION public.fn_validar_cuenta_por_pagar()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE
    v_total_compra NUMERIC(12,2);
    v_estado_compra VARCHAR(30);
    v_forma_pago VARCHAR(150);

    v_total_pagado NUMERIC(12,2);
    v_nuevo_saldo NUMERIC(12,2);
BEGIN

    /* =====================================================
       Obtener información de la compra
       ===================================================== */

    SELECT
        c.total,
        c.estado,
        fp.nombre
    INTO
        v_total_compra,
        v_estado_compra,
        v_forma_pago
    FROM public.compras c

    JOIN public.formas_pago fp
        ON fp.id_forma_pago = c.forma_pago_id

    WHERE c.id_compra = NEW.compra_id

    FOR UPDATE OF c;


    /* =====================================================
       Compra válida
       ===================================================== */

    IF v_estado_compra <> 'REGISTRADA' THEN
        RAISE EXCEPTION
            'No se puede generar una cuenta por pagar para una compra %',
            v_estado_compra;
    END IF;


    /* =====================================================
       Debe ser una compra a crédito
       ===================================================== */

    IF v_forma_pago <> 'CREDITO' THEN
        RAISE EXCEPTION
            'La compra no fue registrada como compra a crédito';
    END IF;


    /* =====================================================
       El monto debe coincidir con la compra
       ===================================================== */

    IF NEW.monto_original <> v_total_compra THEN
        RAISE EXCEPTION
            'El monto de la cuenta (%) debe coincidir con el total de la compra (%)',
            NEW.monto_original,
            v_total_compra;
    END IF;


    /* =====================================================
       Determinar pagos existentes
       ===================================================== */

    IF TG_OP = 'UPDATE' THEN

        SELECT COALESCE(SUM(monto), 0)
        INTO v_total_pagado
        FROM public.pagos_cuentas_por_pagar
        WHERE cuenta_por_pagar_id =
            OLD.id_cuenta_por_pagar;

    ELSE

        v_total_pagado := 0;

    END IF;


    v_nuevo_saldo :=
        NEW.monto_original - v_total_pagado;


    IF v_nuevo_saldo < 0 THEN
        RAISE EXCEPTION
            'El nuevo monto de la deuda es menor que lo ya pagado';
    END IF;


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


CREATE OR REPLACE FUNCTION public.fn_aplicar_movimiento_inventario()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE
    v_factor SMALLINT;
    v_existencia_actual INTEGER;
    v_nueva_existencia INTEGER;
BEGIN

    /* Obtener si el movimiento suma o resta */
    SELECT factor
    INTO v_factor
    FROM public.tipos_movimientos
    WHERE id_tipo_movimiento = NEW.tipo_movimiento_id;


    /* Obtener y bloquear momentáneamente
       el producto que estamos modificando */
    SELECT existencia
    INTO v_existencia_actual
    FROM public.productos
    WHERE id_producto = NEW.producto_id
    FOR UPDATE;


    /* Calcular nueva existencia */
    v_nueva_existencia :=
        v_existencia_actual
        + (NEW.cantidad * v_factor);


    /* No permitir inventario negativo */
    IF v_nueva_existencia < 0 THEN

        RAISE EXCEPTION
            'Stock insuficiente. Producto %, existencia actual %, movimiento solicitado %',
            NEW.producto_id,
            v_existencia_actual,
            NEW.cantidad * v_factor;

    END IF;


    /* Actualizar stock */
    UPDATE public.productos
    SET existencia = v_nueva_existencia
    WHERE id_producto = NEW.producto_id;


    RETURN NEW;
END;
$function$;


CREATE OR REPLACE FUNCTION public.fn_validar_movimiento_inventario()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE
    v_producto_lote INTEGER;
    v_producto_compra INTEGER;
    v_producto_venta INTEGER;
BEGIN

    /* ============================================
       VALIDAR LOTE
       ============================================ */

    IF NEW.lote_id IS NOT NULL THEN

        SELECT dc.producto_id
        INTO v_producto_lote
        FROM public.lotes l
        JOIN public.detalle_compras dc
            ON dc.id_detalle_compra = l.detalle_compra_id
        WHERE l.id_lote = NEW.lote_id;

        IF v_producto_lote <> NEW.producto_id THEN
            RAISE EXCEPTION
                'El lote % no pertenece al producto %',
                NEW.lote_id,
                NEW.producto_id;
        END IF;

    END IF;


    /* ============================================
       VALIDAR DETALLE DE COMPRA
       ============================================ */

    IF NEW.detalle_compra_id IS NOT NULL THEN

        SELECT producto_id
        INTO v_producto_compra
        FROM public.detalle_compras
        WHERE id_detalle_compra = NEW.detalle_compra_id;

        IF v_producto_compra <> NEW.producto_id THEN
            RAISE EXCEPTION
                'El detalle de compra % no corresponde al producto %',
                NEW.detalle_compra_id,
                NEW.producto_id;
        END IF;

    END IF;


    /* ============================================
       VALIDAR DETALLE DE VENTA
       ============================================ */

    IF NEW.detalle_venta_id IS NOT NULL THEN

        SELECT producto_id
        INTO v_producto_venta
        FROM public.detalle_ventas
        WHERE id_detalle_venta = NEW.detalle_venta_id;

        IF v_producto_venta <> NEW.producto_id THEN
            RAISE EXCEPTION
                'El detalle de venta % no corresponde al producto %',
                NEW.detalle_venta_id,
                NEW.producto_id;
        END IF;

    END IF;


    RETURN NEW;
END;
$function$;


CREATE OR REPLACE FUNCTION public.fn_actualizar_ultimo_costo_detalle()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN

    IF TG_OP = 'INSERT' THEN

        PERFORM public.fn_recalcular_ultimo_costo(
            NEW.producto_id
        );


    ELSIF TG_OP = 'UPDATE' THEN

        PERFORM public.fn_recalcular_ultimo_costo(
            NEW.producto_id
        );

        IF OLD.producto_id <> NEW.producto_id THEN

            PERFORM public.fn_recalcular_ultimo_costo(
                OLD.producto_id
            );

        END IF;


    ELSIF TG_OP = 'DELETE' THEN

        PERFORM public.fn_recalcular_ultimo_costo(
            OLD.producto_id
        );

    END IF;


    RETURN NULL;
END;
$function$;


CREATE OR REPLACE FUNCTION public.fn_recalcular_costos_por_estado_compra()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE
    v_producto_id INTEGER;
BEGIN

    IF OLD.estado IS DISTINCT FROM NEW.estado THEN

        FOR v_producto_id IN

            SELECT DISTINCT producto_id
            FROM public.detalle_compras
            WHERE compra_id = NEW.id_compra

        LOOP

            PERFORM public.fn_recalcular_ultimo_costo(
                v_producto_id
            );

        END LOOP;

    END IF;


    RETURN NEW;
END;
$function$;


CREATE OR REPLACE FUNCTION public.fn_validar_pago_cuenta_por_cobrar()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE
    v_monto_original NUMERIC(12,2);
    v_total_pagado NUMERIC(12,2);
    v_total_con_nuevo_pago NUMERIC(12,2);
BEGIN

    /*
       Bloqueamos la cuenta mientras procesamos
       el pago para evitar problemas de concurrencia.
    */
    SELECT monto_original
    INTO v_monto_original
    FROM public.cuentas_por_cobrar
    WHERE id_cuenta_por_cobrar = NEW.cuenta_por_cobrar_id
    FOR UPDATE;


    /*
       Si estamos actualizando un pago,
       excluimos el pago actual del cálculo.
    */
    SELECT COALESCE(SUM(monto), 0)
    INTO v_total_pagado
    FROM public.pagos_cuentas_por_cobrar
    WHERE cuenta_por_cobrar_id = NEW.cuenta_por_cobrar_id
      AND (
          TG_OP <> 'UPDATE'
          OR id_pago_cuenta_por_cobrar
             <> OLD.id_pago_cuenta_por_cobrar
      );


    v_total_con_nuevo_pago :=
        v_total_pagado + NEW.monto;


    IF v_total_con_nuevo_pago > v_monto_original THEN

        RAISE EXCEPTION
            'El pago excede el saldo de la cuenta. Monto original: %, ya pagado: %, nuevo pago: %',
            v_monto_original,
            v_total_pagado,
            NEW.monto;

    END IF;


    RETURN NEW;
END;
$function$;


CREATE OR REPLACE FUNCTION public.fn_actualizar_cuenta_por_cobrar_pago()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN

    IF TG_OP = 'INSERT' THEN

        PERFORM public.fn_recalcular_cuenta_por_cobrar(
            NEW.cuenta_por_cobrar_id
        );


    ELSIF TG_OP = 'UPDATE' THEN

        PERFORM public.fn_recalcular_cuenta_por_cobrar(
            NEW.cuenta_por_cobrar_id
        );

        IF OLD.cuenta_por_cobrar_id
           <> NEW.cuenta_por_cobrar_id THEN

            PERFORM public.fn_recalcular_cuenta_por_cobrar(
                OLD.cuenta_por_cobrar_id
            );

        END IF;


    ELSIF TG_OP = 'DELETE' THEN

        PERFORM public.fn_recalcular_cuenta_por_cobrar(
            OLD.cuenta_por_cobrar_id
        );

    END IF;


    RETURN NULL;
END;
$function$;


CREATE OR REPLACE FUNCTION public.fn_recalcular_cuenta_por_pagar(p_cuenta_id integer)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE
    v_monto_original NUMERIC(12,2);
    v_total_pagado NUMERIC(12,2);
    v_saldo NUMERIC(12,2);
    v_fecha_limite DATE;
    v_estado VARCHAR(30);
BEGIN

    SELECT
        monto_original,
        fecha_limite
    INTO
        v_monto_original,
        v_fecha_limite
    FROM public.cuentas_por_pagar
    WHERE id_cuenta_por_pagar = p_cuenta_id;


    SELECT COALESCE(SUM(monto), 0)
    INTO v_total_pagado
    FROM public.pagos_cuentas_por_pagar
    WHERE cuenta_por_pagar_id = p_cuenta_id;


    v_saldo := v_monto_original - v_total_pagado;


    IF v_saldo = 0 THEN

        v_estado := 'PAGADA';

    ELSIF v_fecha_limite IS NOT NULL
          AND v_fecha_limite < CURRENT_DATE THEN

        v_estado := 'VENCIDA';

    ELSE

        v_estado := 'PENDIENTE';

    END IF;


    UPDATE public.cuentas_por_pagar
    SET
        saldo_pendiente = v_saldo,
        estado = v_estado
    WHERE id_cuenta_por_pagar = p_cuenta_id;

END;
$function$;


CREATE OR REPLACE FUNCTION public.fn_validar_pago_cuenta_por_pagar()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE
    v_monto_original NUMERIC(12,2);
    v_total_pagado NUMERIC(12,2);
    v_total_con_nuevo_pago NUMERIC(12,2);
BEGIN

    SELECT monto_original
    INTO v_monto_original
    FROM public.cuentas_por_pagar
    WHERE id_cuenta_por_pagar = NEW.cuenta_por_pagar_id
    FOR UPDATE;


    SELECT COALESCE(SUM(monto), 0)
    INTO v_total_pagado
    FROM public.pagos_cuentas_por_pagar
    WHERE cuenta_por_pagar_id = NEW.cuenta_por_pagar_id
      AND (
          TG_OP <> 'UPDATE'
          OR id_pago_cuenta_por_pagar
             <> OLD.id_pago_cuenta_por_pagar
      );


    v_total_con_nuevo_pago :=
        v_total_pagado + NEW.monto;


    IF v_total_con_nuevo_pago > v_monto_original THEN

        RAISE EXCEPTION
            'El pago excede el saldo de la cuenta por pagar. Monto original: %, ya pagado: %, nuevo pago: %',
            v_monto_original,
            v_total_pagado,
            NEW.monto;

    END IF;


    RETURN NEW;
END;
$function$;


CREATE OR REPLACE FUNCTION public.fn_actualizar_cuenta_por_pagar_pago()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN

    IF TG_OP = 'INSERT' THEN

        PERFORM public.fn_recalcular_cuenta_por_pagar(
            NEW.cuenta_por_pagar_id
        );


    ELSIF TG_OP = 'UPDATE' THEN

        PERFORM public.fn_recalcular_cuenta_por_pagar(
            NEW.cuenta_por_pagar_id
        );

        IF OLD.cuenta_por_pagar_id
           <> NEW.cuenta_por_pagar_id THEN

            PERFORM public.fn_recalcular_cuenta_por_pagar(
                OLD.cuenta_por_pagar_id
            );

        END IF;


    ELSIF TG_OP = 'DELETE' THEN

        PERFORM public.fn_recalcular_cuenta_por_pagar(
            OLD.cuenta_por_pagar_id
        );

    END IF;


    RETURN NULL;
END;
$function$;


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


    IF v_limite_credito IS NOT NULL
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


CREATE OR REPLACE FUNCTION public.fn_validar_forma_pago_abono()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE
    v_forma_pago VARCHAR(150);
BEGIN

    SELECT nombre
    INTO v_forma_pago
    FROM public.formas_pago
    WHERE id_forma_pago = NEW.forma_pago_id;


    IF v_forma_pago = 'CREDITO' THEN

        RAISE EXCEPTION
            'CREDITO no puede utilizarse como forma de pago de un abono';

    END IF;


    RETURN NEW;
END;
$function$;



-- Una referencia por proveedor evita registrar dos veces la misma factura.
-- La fecha de ingreso se interpreta en la zona horaria de la tienda.
CREATE OR REPLACE FUNCTION public.registrar_compra(
  p_proveedor_id integer,
  p_forma_pago_id integer,
  p_numero_documento varchar,
  p_items jsonb,
  p_fecha_limite date DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET timezone = 'America/Guatemala'
AS $function$
DECLARE
  v_usuario uuid := auth.uid();
  v_documento varchar := nullif(btrim(p_numero_documento), '');
  v_pago text;
  v_tipo integer;
  v_compra integer;
  v_detalle integer;
  v_lote_id integer;
  v_item jsonb;
  v_lote jsonb;
  v_producto public.productos%ROWTYPE;
  v_cantidad integer;
  v_costo numeric(12,2);
  v_total numeric(12,2) := 0;
  v_suma_lotes bigint;
  v_cantidad_lote integer;
  v_fecha date;
BEGIN
  IF v_usuario IS NULL OR NOT public.fn_tiene_rol(ARRAY['ADMINISTRADOR','INVENTARIO']::text[]) THEN
    RAISE EXCEPTION 'No tienes permiso para registrar compras' USING ERRCODE = '42501';
  END IF;
  IF v_documento IS NULL OR length(v_documento) > 100 THEN
    RAISE EXCEPTION 'Indica un documento o referencia de hasta 100 caracteres' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.proveedores WHERE id_proveedor=p_proveedor_id) THEN
    RAISE EXCEPTION 'Selecciona un proveedor válido' USING ERRCODE = '22023';
  END IF;
  SELECT nombre INTO v_pago FROM public.formas_pago WHERE id_forma_pago=p_forma_pago_id;
  IF v_pago IS NULL THEN
    RAISE EXCEPTION 'Selecciona una forma de pago válida' USING ERRCODE = '22023';
  END IF;
  IF v_pago <> 'CREDITO' AND p_fecha_limite IS NOT NULL THEN
    RAISE EXCEPTION 'Solo una compra a crédito puede tener fecha límite' USING ERRCODE = '22023';
  END IF;
  IF p_fecha_limite < CURRENT_DATE THEN
    RAISE EXCEPTION 'La fecha límite no puede ser anterior a hoy' USING ERRCODE = '22023';
  END IF;
  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' THEN
    RAISE EXCEPTION 'La compra debe contener una lista de productos' USING ERRCODE = '22023';
  END IF;
  IF jsonb_array_length(p_items)=0 THEN
    RAISE EXCEPTION 'Agrega al menos un producto' USING ERRCODE = '22023';
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_items) x WHERE jsonb_typeof(x) <> 'object' OR x->>'producto_id' IS NULL) THEN
    RAISE EXCEPTION 'Cada línea debe indicar un producto' USING ERRCODE = '22023';
  END IF;
  IF (SELECT count(*) FROM jsonb_array_elements(p_items)) <>
     (SELECT count(DISTINCT (x->>'producto_id')::integer) FROM jsonb_array_elements(p_items) x) THEN
    RAISE EXCEPTION 'Un producto no puede aparecer dos veces en la misma compra' USING ERRCODE = '22023';
  END IF;
  SELECT id_tipo_movimiento INTO v_tipo FROM public.tipos_movimientos WHERE nombre='COMPRA' AND factor=1;
  IF v_tipo IS NULL THEN
    RAISE EXCEPTION 'Falta configurar el tipo de movimiento COMPRA';
  END IF;
  INSERT INTO public.compras(proveedor_id,usuario_id,forma_pago_id,numero_documento,total)
  VALUES(p_proveedor_id,v_usuario,p_forma_pago_id,v_documento,0) RETURNING id_compra INTO v_compra;

  -- Se bloquean en un orden estable para reducir interbloqueos entre compras.
  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) ORDER BY (value->>'producto_id')::integer LOOP
    IF (v_item->>'cantidad') IS NULL OR (v_item->>'cantidad') !~ '^[0-9]+$' THEN
      RAISE EXCEPTION 'La cantidad debe ser un entero positivo' USING ERRCODE = '22023';
    END IF;
    v_cantidad := (v_item->>'cantidad')::integer;
    IF v_cantidad <= 0 THEN
      RAISE EXCEPTION 'La cantidad debe ser mayor que cero' USING ERRCODE = '22023';
    END IF;
    IF (v_item->>'costo_unitario') IS NULL OR (v_item->>'costo_unitario') !~ '^[0-9]+(\.[0-9]{1,2})?$' THEN
      RAISE EXCEPTION 'El costo debe ser positivo o cero, con hasta dos decimales' USING ERRCODE = '22023';
    END IF;
    v_costo := (v_item->>'costo_unitario')::numeric(12,2);
    SELECT * INTO v_producto FROM public.productos WHERE id_producto=(v_item->>'producto_id')::integer FOR UPDATE;
    IF NOT FOUND OR NOT v_producto.activo THEN
      RAISE EXCEPTION 'El producto no existe o está inactivo' USING ERRCODE = '22023';
    END IF;
    INSERT INTO public.detalle_compras(compra_id,producto_id,cantidad,costo_unitario)
    VALUES(v_compra,v_producto.id_producto,v_cantidad,v_costo) RETURNING id_detalle_compra INTO v_detalle;
    v_total := v_total + v_cantidad*v_costo;

    IF v_producto.controla_lotes THEN
      IF v_item->'lotes' IS NULL OR jsonb_typeof(v_item->'lotes') <> 'array' THEN
        RAISE EXCEPTION 'Este producto requiere información de lotes' USING ERRCODE = '22023';
      END IF;
      IF jsonb_array_length(v_item->'lotes')=0 THEN
        RAISE EXCEPTION 'Agrega al menos un lote' USING ERRCODE = '22023';
      END IF;
      v_suma_lotes := 0;
      FOR v_lote IN SELECT value FROM jsonb_array_elements(v_item->'lotes') LOOP
        IF jsonb_typeof(v_lote) <> 'object' OR v_lote->>'cantidad' IS NULL OR (v_lote->>'cantidad') !~ '^[0-9]+$' THEN
          RAISE EXCEPTION 'Cada lote debe indicar una cantidad entera positiva' USING ERRCODE = '22023';
        END IF;
        v_cantidad_lote := (v_lote->>'cantidad')::integer;
        IF v_cantidad_lote <= 0 THEN
          RAISE EXCEPTION 'La cantidad del lote debe ser mayor que cero' USING ERRCODE = '22023';
        END IF;
        v_fecha := nullif(v_lote->>'fecha_vencimiento','')::date;
        IF v_fecha < CURRENT_DATE THEN
          RAISE EXCEPTION 'No se permite ingresar un lote ya vencido' USING ERRCODE = '22023';
        END IF;
        INSERT INTO public.lotes(detalle_compra_id,numero_lote,fecha_vencimiento)
        VALUES(v_detalle,nullif(btrim(v_lote->>'numero_lote'),''),v_fecha) RETURNING id_lote INTO v_lote_id;
        INSERT INTO public.movimientos_inventario(producto_id,lote_id,tipo_movimiento_id,detalle_compra_id,cantidad,usuario_id,observacion)
        VALUES(v_producto.id_producto,v_lote_id,v_tipo,v_detalle,v_cantidad_lote,v_usuario,'Compra');
        v_suma_lotes := v_suma_lotes + v_cantidad_lote;
      END LOOP;
      IF v_suma_lotes <> v_cantidad THEN
        RAISE EXCEPTION 'La suma de los lotes debe coincidir con la cantidad comprada' USING ERRCODE = '22023';
      END IF;
    ELSE
      IF v_item ? 'lotes' AND v_item->'lotes' <> '[]'::jsonb THEN
        RAISE EXCEPTION 'Este producto no utiliza lotes' USING ERRCODE = '22023';
      END IF;
      INSERT INTO public.movimientos_inventario(producto_id,tipo_movimiento_id,detalle_compra_id,cantidad,usuario_id,observacion)
      VALUES(v_producto.id_producto,v_tipo,v_detalle,v_cantidad,v_usuario,'Compra');
    END IF;
  END LOOP;
  UPDATE public.compras SET total=v_total WHERE id_compra=v_compra;
  IF v_pago='CREDITO' THEN
    IF v_total=0 THEN
      RAISE EXCEPTION 'Una compra a crédito debe tener un total mayor que cero' USING ERRCODE = '22023';
    END IF;
    INSERT INTO public.cuentas_por_pagar(compra_id,monto_original,saldo_pendiente,fecha_limite)
    VALUES(v_compra,v_total,v_total,p_fecha_limite);
  END IF;
  RETURN jsonb_build_object('id_compra',v_compra,'total',v_total,'estado','REGISTRADA');
END;
$function$;

-- Se conserva el acceso de las cuentas autorizadas; el anónimo no puede ejecutar.
REVOKE ALL ON FUNCTION public.registrar_compra(integer,integer,varchar,jsonb,date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.registrar_compra(integer,integer,varchar,jsonb,date) TO authenticated;
