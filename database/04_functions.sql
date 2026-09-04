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