CREATE OR REPLACE FUNCTION fn_aplicar_movimiento_inventario()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_factor SMALLINT;
    v_existencia_actual INTEGER;
    v_nueva_existencia INTEGER;
BEGIN

    /* Obtener si el movimiento suma o resta */
    SELECT factor
    INTO v_factor
    FROM tipos_movimientos
    WHERE id_tipo_movimiento = NEW.tipo_movimiento_id;


    /* Obtener y bloquear momentáneamente
       el producto que estamos modificando */
    SELECT existencia
    INTO v_existencia_actual
    FROM productos
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
    UPDATE productos
    SET existencia = v_nueva_existencia
    WHERE id_producto = NEW.producto_id;


    RETURN NEW;
END;
$$;


CREATE OR REPLACE FUNCTION fn_validar_movimiento_inventario()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
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
        FROM lotes l
        JOIN detalle_compras dc
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
        FROM detalle_compras
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
        FROM detalle_ventas
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
$$;

CREATE OR REPLACE FUNCTION fn_recalcular_ultimo_costo(
    p_producto_id INTEGER
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_ultimo_costo NUMERIC(12,2);
BEGIN

    SELECT dc.costo_unitario
    INTO v_ultimo_costo
    FROM detalle_compras dc
    JOIN compras c
        ON c.id_compra = dc.compra_id
    WHERE dc.producto_id = p_producto_id
      AND c.estado = 'REGISTRADA'
    ORDER BY
        c.fecha DESC,
        dc.id_detalle_compra DESC
    LIMIT 1;


    UPDATE productos
    SET ultimo_costo = v_ultimo_costo
    WHERE id_producto = p_producto_id;

END;
$$;

CREATE OR REPLACE FUNCTION fn_actualizar_ultimo_costo_detalle()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN

    IF TG_OP = 'INSERT' THEN

        PERFORM fn_recalcular_ultimo_costo(
            NEW.producto_id
        );


    ELSIF TG_OP = 'UPDATE' THEN

        /* Recalcular producto nuevo */
        PERFORM fn_recalcular_ultimo_costo(
            NEW.producto_id
        );

        /*
           Si cambiaron el producto del detalle,
           recalcular también el producto anterior.
        */
        IF OLD.producto_id <> NEW.producto_id THEN

            PERFORM fn_recalcular_ultimo_costo(
                OLD.producto_id
            );

        END IF;


    ELSIF TG_OP = 'DELETE' THEN

        PERFORM fn_recalcular_ultimo_costo(
            OLD.producto_id
        );

    END IF;


    RETURN NULL;
END;
$$;


CREATE OR REPLACE FUNCTION fn_recalcular_ultimo_costo(
    p_producto_id INTEGER
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_ultimo_costo NUMERIC(12,2);
BEGIN

    SELECT dc.costo_unitario
    INTO v_ultimo_costo
    FROM detalle_compras dc

    JOIN compras c
        ON c.id_compra = dc.compra_id

    WHERE dc.producto_id = p_producto_id
      AND c.estado = 'REGISTRADA'

    ORDER BY
        c.fecha DESC,
        dc.id_detalle_compra DESC

    LIMIT 1;


    UPDATE productos
    SET ultimo_costo = v_ultimo_costo
    WHERE id_producto = p_producto_id;

END;
$$;


CREATE OR REPLACE FUNCTION fn_actualizar_ultimo_costo_detalle()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN

    IF TG_OP = 'INSERT' THEN

        PERFORM fn_recalcular_ultimo_costo(
            NEW.producto_id
        );


    ELSIF TG_OP = 'UPDATE' THEN

        PERFORM fn_recalcular_ultimo_costo(
            NEW.producto_id
        );

        IF OLD.producto_id <> NEW.producto_id THEN

            PERFORM fn_recalcular_ultimo_costo(
                OLD.producto_id
            );

        END IF;


    ELSIF TG_OP = 'DELETE' THEN

        PERFORM fn_recalcular_ultimo_costo(
            OLD.producto_id
        );

    END IF;


    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION fn_recalcular_costos_por_estado_compra()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_producto_id INTEGER;
BEGIN

    IF OLD.estado IS DISTINCT FROM NEW.estado THEN

        FOR v_producto_id IN

            SELECT DISTINCT producto_id
            FROM detalle_compras
            WHERE compra_id = NEW.id_compra

        LOOP

            PERFORM fn_recalcular_ultimo_costo(
                v_producto_id
            );

        END LOOP;

    END IF;


    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION fn_recalcular_cuenta_por_cobrar(
    p_cuenta_id INTEGER
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
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
    FROM cuentas_por_cobrar
    WHERE id_cuenta_por_cobrar = p_cuenta_id;


    SELECT COALESCE(SUM(monto), 0)
    INTO v_total_pagado
    FROM pagos_cuentas_por_cobrar
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


    UPDATE cuentas_por_cobrar
    SET
        saldo_pendiente = v_saldo,
        estado = v_estado
    WHERE id_cuenta_por_cobrar = p_cuenta_id;

END;
$$;

CREATE OR REPLACE FUNCTION fn_validar_pago_cuenta_por_cobrar()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
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
    FROM cuentas_por_cobrar
    WHERE id_cuenta_por_cobrar = NEW.cuenta_por_cobrar_id
    FOR UPDATE;


    /*
       Si estamos actualizando un pago,
       excluimos el pago actual del cálculo.
    */
    SELECT COALESCE(SUM(monto), 0)
    INTO v_total_pagado
    FROM pagos_cuentas_por_cobrar
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
$$;

CREATE OR REPLACE FUNCTION fn_actualizar_cuenta_por_cobrar_pago()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN

    IF TG_OP = 'INSERT' THEN

        PERFORM fn_recalcular_cuenta_por_cobrar(
            NEW.cuenta_por_cobrar_id
        );


    ELSIF TG_OP = 'UPDATE' THEN

        PERFORM fn_recalcular_cuenta_por_cobrar(
            NEW.cuenta_por_cobrar_id
        );

        IF OLD.cuenta_por_cobrar_id
           <> NEW.cuenta_por_cobrar_id THEN

            PERFORM fn_recalcular_cuenta_por_cobrar(
                OLD.cuenta_por_cobrar_id
            );

        END IF;


    ELSIF TG_OP = 'DELETE' THEN

        PERFORM fn_recalcular_cuenta_por_cobrar(
            OLD.cuenta_por_cobrar_id
        );

    END IF;


    RETURN NULL;
END;
$$;


CREATE OR REPLACE FUNCTION fn_recalcular_cuenta_por_pagar(
    p_cuenta_id INTEGER
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
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
    FROM cuentas_por_pagar
    WHERE id_cuenta_por_pagar = p_cuenta_id;


    SELECT COALESCE(SUM(monto), 0)
    INTO v_total_pagado
    FROM pagos_cuentas_por_pagar
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


    UPDATE cuentas_por_pagar
    SET
        saldo_pendiente = v_saldo,
        estado = v_estado
    WHERE id_cuenta_por_pagar = p_cuenta_id;

END;
$$;

CREATE OR REPLACE FUNCTION fn_validar_pago_cuenta_por_pagar()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_monto_original NUMERIC(12,2);
    v_total_pagado NUMERIC(12,2);
    v_total_con_nuevo_pago NUMERIC(12,2);
BEGIN

    SELECT monto_original
    INTO v_monto_original
    FROM cuentas_por_pagar
    WHERE id_cuenta_por_pagar = NEW.cuenta_por_pagar_id
    FOR UPDATE;


    SELECT COALESCE(SUM(monto), 0)
    INTO v_total_pagado
    FROM pagos_cuentas_por_pagar
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
$$;

CREATE OR REPLACE FUNCTION fn_actualizar_cuenta_por_pagar_pago()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN

    IF TG_OP = 'INSERT' THEN

        PERFORM fn_recalcular_cuenta_por_pagar(
            NEW.cuenta_por_pagar_id
        );


    ELSIF TG_OP = 'UPDATE' THEN

        PERFORM fn_recalcular_cuenta_por_pagar(
            NEW.cuenta_por_pagar_id
        );

        IF OLD.cuenta_por_pagar_id
           <> NEW.cuenta_por_pagar_id THEN

            PERFORM fn_recalcular_cuenta_por_pagar(
                OLD.cuenta_por_pagar_id
            );

        END IF;


    ELSIF TG_OP = 'DELETE' THEN

        PERFORM fn_recalcular_cuenta_por_pagar(
            OLD.cuenta_por_pagar_id
        );

    END IF;


    RETURN NULL;
END;
$$;


CREATE OR REPLACE FUNCTION fn_validar_cuenta_por_cobrar()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
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
    FROM ventas v
    JOIN formas_pago fp
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
        FROM pagos_cuentas_por_cobrar
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
    FROM clientes
    WHERE id_cliente = v_cliente_id
    FOR UPDATE;


    SELECT COALESCE(SUM(cpc.saldo_pendiente), 0)
    INTO v_deuda_actual
    FROM cuentas_por_cobrar cpc

    JOIN ventas v
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
$$;

CREATE OR REPLACE FUNCTION fn_validar_cuenta_por_pagar()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
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
    FROM compras c

    JOIN formas_pago fp
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
        FROM pagos_cuentas_por_pagar
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
$$;


CREATE OR REPLACE FUNCTION fn_validar_forma_pago_abono()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_forma_pago VARCHAR(150);
BEGIN

    SELECT nombre
    INTO v_forma_pago
    FROM formas_pago
    WHERE id_forma_pago = NEW.forma_pago_id;


    IF v_forma_pago = 'CREDITO' THEN

        RAISE EXCEPTION
            'CREDITO no puede utilizarse como forma de pago de un abono';

    END IF;


    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION fn_tiene_rol(
    p_roles TEXT[]
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM usuarios u
        JOIN roles r
            ON r.id_rol = u.rol_id
        WHERE u.id_usuario = auth.uid()
          AND u.activo = TRUE
          AND r.nombre = ANY(p_roles)
    );
$$;