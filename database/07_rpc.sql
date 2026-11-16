CREATE OR REPLACE FUNCTION public.registrar_venta(
    p_cliente_id INTEGER,
    p_forma_pago_id INTEGER,
    p_items JSONB,
    p_fecha_limite DATE DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_usuario_id UUID;

    v_id_venta INTEGER;
    v_id_detalle INTEGER;

    v_forma_pago VARCHAR(150);

    v_tipo_venta_id INTEGER;

    v_item JSONB;

    v_producto_id INTEGER;
    v_cantidad INTEGER;

    v_precio NUMERIC(12,2);
    v_activo BOOLEAN;
    v_controla_lotes BOOLEAN;
    v_existencia INTEGER;

    v_total NUMERIC(12,2) := 0;

    v_cantidad_restante INTEGER;

    v_lote RECORD;
    v_tomar INTEGER;
BEGIN

    /* =====================================================
       USUARIO AUTENTICADO
       ===================================================== */

    v_usuario_id := auth.uid();


    IF v_usuario_id IS NULL THEN
        RAISE EXCEPTION
            'Usuario no autenticado';
    END IF;


    IF NOT public.fn_tiene_rol(
        ARRAY[
            'ADMINISTRADOR',
            'CAJERO'
        ]::TEXT[]
    ) THEN

        RAISE EXCEPTION
            'El usuario no tiene permiso para registrar ventas';

    END IF;


    /* =====================================================
       VALIDAR ITEMS
       ===================================================== */

    IF p_items IS NULL
       OR jsonb_typeof(p_items) <> 'array'
       OR jsonb_array_length(p_items) = 0 THEN

        RAISE EXCEPTION
            'La venta debe contener al menos un producto';

    END IF;


    /* No permitir el mismo producto dos veces */

    IF (
        SELECT COUNT(*)
        FROM jsonb_array_elements(p_items)
    ) <> (
        SELECT COUNT(
            DISTINCT (x->>'producto_id')::INTEGER
        )
        FROM jsonb_array_elements(p_items) x
    ) THEN

        RAISE EXCEPTION
            'Un producto no puede aparecer dos veces en la misma venta';

    END IF;


    /* =====================================================
       FORMA DE PAGO
       ===================================================== */

    SELECT nombre
    INTO v_forma_pago
    FROM public.formas_pago
    WHERE id_forma_pago = p_forma_pago_id;


    IF v_forma_pago IS NULL THEN
        RAISE EXCEPTION
            'Forma de pago inválida';
    END IF;


    IF v_forma_pago = 'CREDITO'
       AND p_cliente_id IS NULL THEN

        RAISE EXCEPTION
            'Una venta a crédito requiere un cliente';

    END IF;


    IF v_forma_pago <> 'CREDITO'
       AND p_fecha_limite IS NOT NULL THEN

        RAISE EXCEPTION
            'Solo una venta a crédito puede tener fecha límite';

    END IF;


    /* =====================================================
       TIPO DE MOVIMIENTO VENTA
       ===================================================== */

    SELECT id_tipo_movimiento
    INTO v_tipo_venta_id
    FROM public.tipos_movimientos
    WHERE nombre = 'VENTA';


    IF v_tipo_venta_id IS NULL THEN
        RAISE EXCEPTION
            'No existe el tipo de movimiento VENTA';
    END IF;


    /* =====================================================
       CREAR ENCABEZADO TEMPORAL
       ===================================================== */

    INSERT INTO public.ventas (
        cliente_id,
        usuario_id,
        forma_pago_id,
        total
    )
    VALUES (
        p_cliente_id,
        v_usuario_id,
        p_forma_pago_id,
        0
    )
    RETURNING id_venta
    INTO v_id_venta;


    /* =====================================================
       PROCESAR PRODUCTOS
       ===================================================== */

    FOR v_item IN

        SELECT *
        FROM jsonb_array_elements(p_items)

    LOOP

        v_producto_id :=
            (v_item->>'producto_id')::INTEGER;

        v_cantidad :=
            (v_item->>'cantidad')::INTEGER;


        IF v_cantidad IS NULL
           OR v_cantidad <= 0 THEN

            RAISE EXCEPTION
                'Cantidad inválida para producto %',
                v_producto_id;

        END IF;


        /*
           Bloquear producto.

           Esto evita que dos cajas vendan simultáneamente
           basándose en la misma existencia.
        */

        SELECT
            precio_venta,
            activo,
            controla_lotes,
            existencia

        INTO
            v_precio,
            v_activo,
            v_controla_lotes,
            v_existencia

        FROM public.productos

        WHERE id_producto = v_producto_id

        FOR UPDATE;


        IF NOT FOUND THEN
            RAISE EXCEPTION
                'Producto % no existe',
                v_producto_id;
        END IF;


        IF v_activo = FALSE THEN
            RAISE EXCEPTION
                'Producto % está inactivo',
                v_producto_id;
        END IF;


        IF v_cantidad > v_existencia THEN
            RAISE EXCEPTION
                'Stock insuficiente para producto %. Disponible: %, solicitado: %',
                v_producto_id,
                v_existencia,
                v_cantidad;
        END IF;


        /* =================================================
           CREAR DETALLE
           ================================================= */

        INSERT INTO public.detalle_ventas (
            venta_id,
            producto_id,
            cantidad,
            precio_unitario
        )
        VALUES (
            v_id_venta,
            v_producto_id,
            v_cantidad,
            v_precio
        )
        RETURNING id_detalle_venta
        INTO v_id_detalle;


        v_total :=
            v_total + (v_cantidad * v_precio);


        /* =================================================
           PRODUCTO CON CONTROL POR LOTES
           FEFO
           ================================================= */

        IF v_controla_lotes THEN

            v_cantidad_restante :=
                v_cantidad;


            /*
               FEFO:
               First Expired, First Out

               Se consume primero lo que vence antes.
            */

            FOR v_lote IN

                SELECT
                    l.id_lote,

                    public.fn_stock_lote(
                        l.id_lote
                    ) AS stock_lote

                FROM public.lotes l

                JOIN public.detalle_compras dc
                    ON dc.id_detalle_compra =
                       l.detalle_compra_id

                JOIN public.compras c
                    ON c.id_compra =
                       dc.compra_id

                WHERE dc.producto_id =
                      v_producto_id

                  AND c.estado =
                      'REGISTRADA'

                  AND public.fn_stock_lote(
                      l.id_lote
                  ) > 0

                ORDER BY
                    l.fecha_vencimiento
                        ASC NULLS LAST,
                    l.fecha_ingreso ASC,
                    l.id_lote ASC

            LOOP

                EXIT WHEN
                    v_cantidad_restante = 0;


                v_tomar :=
                    LEAST(
                        v_cantidad_restante,
                        v_lote.stock_lote
                    );


                INSERT INTO public.movimientos_inventario (
                    producto_id,
                    lote_id,
                    tipo_movimiento_id,
                    detalle_venta_id,
                    cantidad,
                    usuario_id,
                    observacion
                )
                VALUES (
                    v_producto_id,
                    v_lote.id_lote,
                    v_tipo_venta_id,
                    v_id_detalle,
                    v_tomar,
                    v_usuario_id,
                    'Venta'
                );


                v_cantidad_restante :=
                    v_cantidad_restante - v_tomar;

            END LOOP;


            IF v_cantidad_restante > 0 THEN

                RAISE EXCEPTION
                    'El producto % indica existencia suficiente, pero sus lotes no contienen suficiente stock',
                    v_producto_id;

            END IF;


        /* =================================================
           PRODUCTO SIN CONTROL POR LOTES
           ================================================= */

        ELSE

            INSERT INTO public.movimientos_inventario (
                producto_id,
                lote_id,
                tipo_movimiento_id,
                detalle_venta_id,
                cantidad,
                usuario_id,
                observacion
            )
            VALUES (
                v_producto_id,
                NULL,
                v_tipo_venta_id,
                v_id_detalle,
                v_cantidad,
                v_usuario_id,
                'Venta'
            );

        END IF;

    END LOOP;


    /* =====================================================
       TOTAL DEFINITIVO
       ===================================================== */

    UPDATE public.ventas
    SET total = v_total
    WHERE id_venta = v_id_venta;


    /* =====================================================
       CUENTA POR COBRAR
       ===================================================== */

    IF v_forma_pago = 'CREDITO' THEN

        INSERT INTO public.cuentas_por_cobrar (
            venta_id,
            monto_original,
            saldo_pendiente,
            fecha_limite
        )
        VALUES (
            v_id_venta,
            v_total,
            v_total,
            p_fecha_limite
        );

    END IF;


    /* =====================================================
       RESPUESTA PARA REACT
       ===================================================== */

    RETURN jsonb_build_object(
        'id_venta', v_id_venta,
        'total', v_total,
        'estado', 'REGISTRADA'
    );

END;
$$;

REVOKE ALL
ON FUNCTION public.registrar_venta(
    INTEGER,
    INTEGER,
    JSONB,
    DATE
)
FROM PUBLIC;


GRANT EXECUTE
ON FUNCTION public.registrar_venta(
    INTEGER,
    INTEGER,
    JSONB,
    DATE
)
TO authenticated;


CREATE OR REPLACE FUNCTION public.registrar_compra(
    p_proveedor_id INTEGER,
    p_forma_pago_id INTEGER,
    p_numero_documento VARCHAR,
    p_items JSONB,
    p_fecha_limite DATE DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_usuario_id UUID;

    v_id_compra INTEGER;
    v_id_detalle INTEGER;
    v_id_lote INTEGER;

    v_tipo_compra_id INTEGER;

    v_forma_pago VARCHAR(150);

    v_item JSONB;
    v_lote JSONB;

    v_producto_id INTEGER;
    v_cantidad INTEGER;
    v_costo_unitario NUMERIC(12,2);

    v_activo BOOLEAN;
    v_controla_lotes BOOLEAN;

    v_total NUMERIC(12,2) := 0;

    v_lotes_total INTEGER;
    v_cantidad_lote INTEGER;

    v_numero_lote VARCHAR(150);
    v_fecha_vencimiento DATE;

BEGIN

    /* =====================================================
       USUARIO AUTENTICADO
       ===================================================== */

    v_usuario_id := auth.uid();


    IF v_usuario_id IS NULL THEN
        RAISE EXCEPTION
            'Usuario no autenticado';
    END IF;


    IF NOT public.fn_tiene_rol(
        ARRAY[
            'ADMINISTRADOR',
            'INVENTARIO'
        ]::TEXT[]
    ) THEN

        RAISE EXCEPTION
            'El usuario no tiene permiso para registrar compras';

    END IF;


    /* =====================================================
       VALIDAR PROVEEDOR
       ===================================================== */

    IF NOT EXISTS (
        SELECT 1
        FROM public.proveedores
        WHERE id_proveedor = p_proveedor_id
    ) THEN

        RAISE EXCEPTION
            'Proveedor % no existe',
            p_proveedor_id;

    END IF;


    /* =====================================================
       VALIDAR ITEMS
       ===================================================== */

    IF p_items IS NULL
       OR jsonb_typeof(p_items) <> 'array'
       OR jsonb_array_length(p_items) = 0 THEN

        RAISE EXCEPTION
            'La compra debe contener al menos un producto';

    END IF;


    /*
       En esta V1 no permitiremos repetir
       el mismo producto dentro de una compra.
    */

    IF (
        SELECT COUNT(*)
        FROM jsonb_array_elements(p_items)
    ) <> (
        SELECT COUNT(
            DISTINCT (x->>'producto_id')::INTEGER
        )
        FROM jsonb_array_elements(p_items) x
    ) THEN

        RAISE EXCEPTION
            'Un producto no puede aparecer dos veces en la misma compra';

    END IF;


    /* =====================================================
       FORMA DE PAGO
       ===================================================== */

    SELECT nombre
    INTO v_forma_pago
    FROM public.formas_pago
    WHERE id_forma_pago = p_forma_pago_id;


    IF v_forma_pago IS NULL THEN
        RAISE EXCEPTION
            'Forma de pago inválida';
    END IF;


    IF v_forma_pago <> 'CREDITO'
       AND p_fecha_limite IS NOT NULL THEN

        RAISE EXCEPTION
            'Solo una compra a crédito puede tener fecha límite';

    END IF;


    /* =====================================================
       TIPO DE MOVIMIENTO COMPRA
       ===================================================== */

    SELECT id_tipo_movimiento
    INTO v_tipo_compra_id
    FROM public.tipos_movimientos
    WHERE nombre = 'COMPRA';


    IF v_tipo_compra_id IS NULL THEN

        RAISE EXCEPTION
            'No existe el tipo de movimiento COMPRA';

    END IF;


    /* =====================================================
       CREAR ENCABEZADO
       ===================================================== */

    INSERT INTO public.compras (
        proveedor_id,
        usuario_id,
        forma_pago_id,
        numero_documento,
        total
    )
    VALUES (
        p_proveedor_id,
        v_usuario_id,
        p_forma_pago_id,
        p_numero_documento,
        0
    )
    RETURNING id_compra
    INTO v_id_compra;


    /* =====================================================
       PROCESAR CADA PRODUCTO
       ===================================================== */

    FOR v_item IN

        SELECT *
        FROM jsonb_array_elements(p_items)

    LOOP

        v_producto_id :=
            (v_item->>'producto_id')::INTEGER;

        v_cantidad :=
            (v_item->>'cantidad')::INTEGER;

        v_costo_unitario :=
            (v_item->>'costo_unitario')::NUMERIC(12,2);


        /* =================================================
           VALIDACIONES DEL ITEM
           ================================================= */

        IF v_producto_id IS NULL THEN
            RAISE EXCEPTION
                'producto_id es obligatorio';
        END IF;


        IF v_cantidad IS NULL
           OR v_cantidad <= 0 THEN

            RAISE EXCEPTION
                'Cantidad inválida para producto %',
                v_producto_id;

        END IF;


        IF v_costo_unitario IS NULL
           OR v_costo_unitario < 0 THEN

            RAISE EXCEPTION
                'Costo unitario inválido para producto %',
                v_producto_id;

        END IF;


        /*
           Bloqueamos el producto mientras procesamos
           su entrada.
        */

        SELECT
            activo,
            controla_lotes

        INTO
            v_activo,
            v_controla_lotes

        FROM public.productos

        WHERE id_producto = v_producto_id

        FOR UPDATE;


        IF NOT FOUND THEN

            RAISE EXCEPTION
                'Producto % no existe',
                v_producto_id;

        END IF;


        IF v_activo = FALSE THEN

            RAISE EXCEPTION
                'Producto % está inactivo',
                v_producto_id;

        END IF;


        /* =================================================
           CREAR DETALLE DE COMPRA
           ================================================= */

        INSERT INTO public.detalle_compras (
            compra_id,
            producto_id,
            cantidad,
            costo_unitario
        )
        VALUES (
            v_id_compra,
            v_producto_id,
            v_cantidad,
            v_costo_unitario
        )
        RETURNING id_detalle_compra
        INTO v_id_detalle;


        /*
           El subtotal ya lo calcula PostgreSQL mediante
           GENERATED ALWAYS.

           Aquí acumulamos el total de la compra.
        */

        v_total :=
            v_total
            + (v_cantidad * v_costo_unitario);


        /* =================================================
           PRODUCTO CONTROLADO POR LOTES
           ================================================= */

        IF v_controla_lotes THEN

            IF NOT (v_item ? 'lotes')
               OR jsonb_typeof(v_item->'lotes') <> 'array'
               OR jsonb_array_length(v_item->'lotes') = 0 THEN

                RAISE EXCEPTION
                    'El producto % requiere información de lotes',
                    v_producto_id;

            END IF;


            /*
               Sumar cantidades declaradas en los lotes.
            */

            SELECT COALESCE(
                SUM(
                    (x->>'cantidad')::INTEGER
                ),
                0
            )
            INTO v_lotes_total

            FROM jsonb_array_elements(
                v_item->'lotes'
            ) x;


            IF v_lotes_total <> v_cantidad THEN

                RAISE EXCEPTION
                    'Las cantidades de los lotes del producto % suman %, pero la compra declara %',
                    v_producto_id,
                    v_lotes_total,
                    v_cantidad;

            END IF;


            /* =============================================
               CREAR CADA LOTE
               ============================================= */

            FOR v_lote IN

                SELECT *
                FROM jsonb_array_elements(
                    v_item->'lotes'
                )

            LOOP

                v_cantidad_lote :=
                    (v_lote->>'cantidad')::INTEGER;


                IF v_cantidad_lote IS NULL
                   OR v_cantidad_lote <= 0 THEN

                    RAISE EXCEPTION
                        'Cantidad de lote inválida para producto %',
                        v_producto_id;

                END IF;


                v_numero_lote :=
                    NULLIF(
                        v_lote->>'numero_lote',
                        ''
                    );


                v_fecha_vencimiento :=
                    NULLIF(
                        v_lote->>'fecha_vencimiento',
                        ''
                    )::DATE;


                /* Crear lote */

                INSERT INTO public.lotes (
                    detalle_compra_id,
                    numero_lote,
                    fecha_vencimiento
                )
                VALUES (
                    v_id_detalle,
                    v_numero_lote,
                    v_fecha_vencimiento
                )
                RETURNING id_lote
                INTO v_id_lote;


                /*
                   Registrar entrada al inventario.

                   Nuestros triggers:
                   - validan producto/lote
                   - actualizan existencia
                   - impiden inconsistencias
                */

                INSERT INTO public.movimientos_inventario (
                    producto_id,
                    lote_id,
                    tipo_movimiento_id,
                    detalle_compra_id,
                    cantidad,
                    usuario_id,
                    observacion
                )
                VALUES (
                    v_producto_id,
                    v_id_lote,
                    v_tipo_compra_id,
                    v_id_detalle,
                    v_cantidad_lote,
                    v_usuario_id,
                    'Compra'
                );

            END LOOP;


        /* =================================================
           PRODUCTO SIN CONTROL POR LOTES
           ================================================= */

        ELSE

            /*
               Si el producto no maneja lotes, rechazamos
               lotes enviados accidentalmente.
            */

            IF (v_item ? 'lotes')
               AND jsonb_typeof(v_item->'lotes') = 'array'
               AND jsonb_array_length(v_item->'lotes') > 0 THEN

                RAISE EXCEPTION
                    'El producto % no utiliza control por lotes',
                    v_producto_id;

            END IF;


            INSERT INTO public.movimientos_inventario (
                producto_id,
                lote_id,
                tipo_movimiento_id,
                detalle_compra_id,
                cantidad,
                usuario_id,
                observacion
            )
            VALUES (
                v_producto_id,
                NULL,
                v_tipo_compra_id,
                v_id_detalle,
                v_cantidad,
                v_usuario_id,
                'Compra'
            );

        END IF;

    END LOOP;


    /* =====================================================
       TOTAL DEFINITIVO
       ===================================================== */

    UPDATE public.compras
    SET total = v_total
    WHERE id_compra = v_id_compra;


    /* =====================================================
       CUENTA POR PAGAR
       ===================================================== */

    IF v_forma_pago = 'CREDITO' THEN

        INSERT INTO public.cuentas_por_pagar (
            compra_id,
            monto_original,
            saldo_pendiente,
            fecha_limite
        )
        VALUES (
            v_id_compra,
            v_total,
            v_total,
            p_fecha_limite
        );

    END IF;


    /* =====================================================
       RESPUESTA
       ===================================================== */

    RETURN jsonb_build_object(
        'id_compra', v_id_compra,
        'total', v_total,
        'estado', 'REGISTRADA'
    );

END;
$$;

REVOKE ALL
ON FUNCTION public.registrar_compra(
    INTEGER,
    INTEGER,
    VARCHAR,
    JSONB,
    DATE
)
FROM PUBLIC;


GRANT EXECUTE
ON FUNCTION public.registrar_compra(
    INTEGER,
    INTEGER,
    VARCHAR,
    JSONB,
    DATE
)
TO authenticated;