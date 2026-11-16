/* ============================================================
   TIENDA-APP
   ROW LEVEL SECURITY
   ============================================================ */


/* ============================================================
   ACTIVAR RLS
   ============================================================ */

ALTER TABLE categorias ENABLE ROW LEVEL SECURITY;
ALTER TABLE productos ENABLE ROW LEVEL SECURITY;
ALTER TABLE proveedores ENABLE ROW LEVEL SECURITY;
ALTER TABLE roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE formas_pago ENABLE ROW LEVEL SECURITY;
ALTER TABLE tipos_movimientos ENABLE ROW LEVEL SECURITY;
ALTER TABLE clientes ENABLE ROW LEVEL SECURITY;
ALTER TABLE usuarios ENABLE ROW LEVEL SECURITY;

ALTER TABLE compras ENABLE ROW LEVEL SECURITY;
ALTER TABLE detalle_compras ENABLE ROW LEVEL SECURITY;
ALTER TABLE lotes ENABLE ROW LEVEL SECURITY;

ALTER TABLE ventas ENABLE ROW LEVEL SECURITY;
ALTER TABLE detalle_ventas ENABLE ROW LEVEL SECURITY;

ALTER TABLE cuentas_por_cobrar ENABLE ROW LEVEL SECURITY;
ALTER TABLE pagos_cuentas_por_cobrar ENABLE ROW LEVEL SECURITY;

ALTER TABLE cuentas_por_pagar ENABLE ROW LEVEL SECURITY;
ALTER TABLE pagos_cuentas_por_pagar ENABLE ROW LEVEL SECURITY;

ALTER TABLE movimientos_inventario ENABLE ROW LEVEL SECURITY;


/* ============================================================
   2. ROLES
   ============================================================ */

/* Eliminar policies anteriores */

DROP POLICY IF EXISTS roles_select_authenticated
ON roles;

DROP POLICY IF EXISTS roles_insert_admin
ON roles;

DROP POLICY IF EXISTS roles_update_admin
ON roles;

DROP POLICY IF EXISTS roles_delete_admin
ON roles;


/* Todos los autenticados pueden consultar roles */

CREATE POLICY roles_select_authenticated
ON roles
FOR SELECT
TO authenticated
USING (TRUE);


/* Solamente administrador puede crear roles */

CREATE POLICY roles_insert_admin
ON roles
FOR INSERT
TO authenticated
WITH CHECK (
    public.fn_tiene_rol(
        ARRAY['ADMINISTRADOR']::TEXT[]
    )
);


/* Solamente administrador puede modificar roles */

CREATE POLICY roles_update_admin
ON roles
FOR UPDATE
TO authenticated
USING (
    public.fn_tiene_rol(
        ARRAY['ADMINISTRADOR']::TEXT[]
    )
)
WITH CHECK (
    public.fn_tiene_rol(
        ARRAY['ADMINISTRADOR']::TEXT[]
    )
);


/* Solamente administrador puede eliminar roles */

CREATE POLICY roles_delete_admin
ON roles
FOR DELETE
TO authenticated
USING (
    public.fn_tiene_rol(
        ARRAY['ADMINISTRADOR']::TEXT[]
    )
);


/* ============================================================
   3. FORMAS DE PAGO
   ============================================================ */

DROP POLICY IF EXISTS formas_pago_select_authenticated
ON formas_pago;

DROP POLICY IF EXISTS formas_pago_write_admin
ON formas_pago;


CREATE POLICY formas_pago_select_authenticated
ON formas_pago
FOR SELECT
TO authenticated
USING (TRUE);


CREATE POLICY formas_pago_write_admin
ON formas_pago
FOR ALL
TO authenticated
USING (
    public.fn_tiene_rol(
        ARRAY['ADMINISTRADOR']::TEXT[]
    )
)
WITH CHECK (
    public.fn_tiene_rol(
        ARRAY['ADMINISTRADOR']::TEXT[]
    )
);


/* ============================================================
   4. TIPOS DE MOVIMIENTO
   ============================================================ */

DROP POLICY IF EXISTS tipos_movimientos_select_authenticated
ON tipos_movimientos;

DROP POLICY IF EXISTS tipos_movimientos_write_admin
ON tipos_movimientos;


CREATE POLICY tipos_movimientos_select_authenticated
ON tipos_movimientos
FOR SELECT
TO authenticated
USING (TRUE);


CREATE POLICY tipos_movimientos_write_admin
ON tipos_movimientos
FOR ALL
TO authenticated
USING (
    public.fn_tiene_rol(
        ARRAY['ADMINISTRADOR']::TEXT[]
    )
)
WITH CHECK (
    public.fn_tiene_rol(
        ARRAY['ADMINISTRADOR']::TEXT[]
    )
);


/* ============================================================
   5. CATEGORÍAS
   ============================================================ */

DROP POLICY IF EXISTS categorias_select_authenticated
ON categorias;

DROP POLICY IF EXISTS categorias_write_admin_inventario
ON categorias;

DROP POLICY IF EXISTS categorias_insert_admin_inventario
ON categorias;

DROP POLICY IF EXISTS categorias_update_admin_inventario
ON categorias;

DROP POLICY IF EXISTS categorias_delete_admin
ON categorias;


CREATE POLICY categorias_select_authenticated
ON categorias
FOR SELECT
TO authenticated
USING (TRUE);


CREATE POLICY categorias_insert_admin_inventario
ON categorias
FOR INSERT
TO authenticated
WITH CHECK (
    public.fn_tiene_rol(
        ARRAY[
            'ADMINISTRADOR',
            'INVENTARIO'
        ]::TEXT[]
    )
);


CREATE POLICY categorias_update_admin_inventario
ON categorias
FOR UPDATE
TO authenticated
USING (
    public.fn_tiene_rol(
        ARRAY[
            'ADMINISTRADOR',
            'INVENTARIO'
        ]::TEXT[]
    )
)
WITH CHECK (
    public.fn_tiene_rol(
        ARRAY[
            'ADMINISTRADOR',
            'INVENTARIO'
        ]::TEXT[]
    )
);


CREATE POLICY categorias_delete_admin
ON categorias
FOR DELETE
TO authenticated
USING (
    public.fn_tiene_rol(
        ARRAY['ADMINISTRADOR']::TEXT[]
    )
);


/* ============================================================
   6. PRODUCTOS
   ============================================================ */

DROP POLICY IF EXISTS productos_select_authenticated
ON productos;

DROP POLICY IF EXISTS productos_insert_admin_inventario
ON productos;

DROP POLICY IF EXISTS productos_update_admin_inventario
ON productos;

DROP POLICY IF EXISTS productos_delete_admin
ON productos;


CREATE POLICY productos_select_authenticated
ON productos
FOR SELECT
TO authenticated
USING (TRUE);


CREATE POLICY productos_insert_admin_inventario
ON productos
FOR INSERT
TO authenticated
WITH CHECK (
    public.fn_tiene_rol(
        ARRAY[
            'ADMINISTRADOR',
            'INVENTARIO'
        ]::TEXT[]
    )
);


CREATE POLICY productos_update_admin_inventario
ON productos
FOR UPDATE
TO authenticated
USING (
    public.fn_tiene_rol(
        ARRAY[
            'ADMINISTRADOR',
            'INVENTARIO'
        ]::TEXT[]
    )
)
WITH CHECK (
    public.fn_tiene_rol(
        ARRAY[
            'ADMINISTRADOR',
            'INVENTARIO'
        ]::TEXT[]
    )
);


CREATE POLICY productos_delete_admin
ON productos
FOR DELETE
TO authenticated
USING (
    public.fn_tiene_rol(
        ARRAY['ADMINISTRADOR']::TEXT[]
    )
);


/* ============================================================
   7. PROVEEDORES
   ============================================================ */

DROP POLICY IF EXISTS proveedores_select_admin_inventario
ON proveedores;

DROP POLICY IF EXISTS proveedores_write_admin_inventario
ON proveedores;

DROP POLICY IF EXISTS proveedores_insert_admin_inventario
ON proveedores;

DROP POLICY IF EXISTS proveedores_update_admin_inventario
ON proveedores;

DROP POLICY IF EXISTS proveedores_delete_admin
ON proveedores;


CREATE POLICY proveedores_select_admin_inventario
ON proveedores
FOR SELECT
TO authenticated
USING (
    public.fn_tiene_rol(
        ARRAY[
            'ADMINISTRADOR',
            'INVENTARIO'
        ]::TEXT[]
    )
);


CREATE POLICY proveedores_insert_admin_inventario
ON proveedores
FOR INSERT
TO authenticated
WITH CHECK (
    public.fn_tiene_rol(
        ARRAY[
            'ADMINISTRADOR',
            'INVENTARIO'
        ]::TEXT[]
    )
);


CREATE POLICY proveedores_update_admin_inventario
ON proveedores
FOR UPDATE
TO authenticated
USING (
    public.fn_tiene_rol(
        ARRAY[
            'ADMINISTRADOR',
            'INVENTARIO'
        ]::TEXT[]
    )
)
WITH CHECK (
    public.fn_tiene_rol(
        ARRAY[
            'ADMINISTRADOR',
            'INVENTARIO'
        ]::TEXT[]
    )
);


CREATE POLICY proveedores_delete_admin
ON proveedores
FOR DELETE
TO authenticated
USING (
    public.fn_tiene_rol(
        ARRAY['ADMINISTRADOR']::TEXT[]
    )
);


/* ============================================================
   8. CLIENTES
   ============================================================ */

DROP POLICY IF EXISTS clientes_select_admin_cajero
ON clientes;

DROP POLICY IF EXISTS clientes_insert_admin_cajero
ON clientes;

DROP POLICY IF EXISTS clientes_update_admin_cajero
ON clientes;

DROP POLICY IF EXISTS clientes_delete_admin
ON clientes;


CREATE POLICY clientes_select_admin_cajero
ON clientes
FOR SELECT
TO authenticated
USING (
    public.fn_tiene_rol(
        ARRAY[
            'ADMINISTRADOR',
            'CAJERO'
        ]::TEXT[]
    )
);


CREATE POLICY clientes_insert_admin_cajero
ON clientes
FOR INSERT
TO authenticated
WITH CHECK (
    public.fn_tiene_rol(
        ARRAY[
            'ADMINISTRADOR',
            'CAJERO'
        ]::TEXT[]
    )
);


CREATE POLICY clientes_update_admin_cajero
ON clientes
FOR UPDATE
TO authenticated
USING (
    public.fn_tiene_rol(
        ARRAY[
            'ADMINISTRADOR',
            'CAJERO'
        ]::TEXT[]
    )
)
WITH CHECK (
    public.fn_tiene_rol(
        ARRAY[
            'ADMINISTRADOR',
            'CAJERO'
        ]::TEXT[]
    )
);


CREATE POLICY clientes_delete_admin
ON clientes
FOR DELETE
TO authenticated
USING (
    public.fn_tiene_rol(
        ARRAY['ADMINISTRADOR']::TEXT[]
    )
);


/* ============================================================
   9. USUARIOS
   ============================================================ */

DROP POLICY IF EXISTS usuarios_select_own
ON usuarios;

DROP POLICY IF EXISTS usuarios_select_admin
ON usuarios;

DROP POLICY IF EXISTS usuarios_insert_admin
ON usuarios;

DROP POLICY IF EXISTS usuarios_update_admin
ON usuarios;

DROP POLICY IF EXISTS usuarios_delete_admin
ON usuarios;


/* Cada usuario puede consultar su propio perfil */

CREATE POLICY usuarios_select_own
ON usuarios
FOR SELECT
TO authenticated
USING (
    id_usuario = (SELECT auth.uid())
);


/* Administrador puede consultar todos */

CREATE POLICY usuarios_select_admin
ON usuarios
FOR SELECT
TO authenticated
USING (
    public.fn_tiene_rol(
        ARRAY['ADMINISTRADOR']::TEXT[]
    )
);


CREATE POLICY usuarios_insert_admin
ON usuarios
FOR INSERT
TO authenticated
WITH CHECK (
    public.fn_tiene_rol(
        ARRAY['ADMINISTRADOR']::TEXT[]
    )
);


CREATE POLICY usuarios_update_admin
ON usuarios
FOR UPDATE
TO authenticated
USING (
    public.fn_tiene_rol(
        ARRAY['ADMINISTRADOR']::TEXT[]
    )
)
WITH CHECK (
    public.fn_tiene_rol(
        ARRAY['ADMINISTRADOR']::TEXT[]
    )
);


CREATE POLICY usuarios_delete_admin
ON usuarios
FOR DELETE
TO authenticated
USING (
    public.fn_tiene_rol(
        ARRAY['ADMINISTRADOR']::TEXT[]
    )
);


/* ============================================================
   10. COMPRAS
   ============================================================ */

DROP POLICY IF EXISTS compras_access_admin_inventario
ON compras;

DROP POLICY IF EXISTS compras_select_admin_inventario
ON compras;

DROP POLICY IF EXISTS compras_insert_admin_inventario
ON compras;

DROP POLICY IF EXISTS compras_update_admin_inventario
ON compras;

DROP POLICY IF EXISTS compras_delete_admin
ON compras;


CREATE POLICY compras_select_admin_inventario
ON compras
FOR SELECT
TO authenticated
USING (
    public.fn_tiene_rol(
        ARRAY[
            'ADMINISTRADOR',
            'INVENTARIO'
        ]::TEXT[]
    )
);


CREATE POLICY compras_insert_admin_inventario
ON compras
FOR INSERT
TO authenticated
WITH CHECK (
    public.fn_tiene_rol(
        ARRAY[
            'ADMINISTRADOR',
            'INVENTARIO'
        ]::TEXT[]
    )
    AND usuario_id = (SELECT auth.uid())
);


CREATE POLICY compras_update_admin_inventario
ON compras
FOR UPDATE
TO authenticated
USING (
    public.fn_tiene_rol(
        ARRAY[
            'ADMINISTRADOR',
            'INVENTARIO'
        ]::TEXT[]
    )
)
WITH CHECK (
    public.fn_tiene_rol(
        ARRAY[
            'ADMINISTRADOR',
            'INVENTARIO'
        ]::TEXT[]
    )
);


CREATE POLICY compras_delete_admin
ON compras
FOR DELETE
TO authenticated
USING (
    public.fn_tiene_rol(
        ARRAY['ADMINISTRADOR']::TEXT[]
    )
);


/* ============================================================
   11. DETALLE DE COMPRAS
   ============================================================ */

DROP POLICY IF EXISTS detalle_compras_access_admin_inventario
ON detalle_compras;

DROP POLICY IF EXISTS detalle_compras_select_admin_inventario
ON detalle_compras;

DROP POLICY IF EXISTS detalle_compras_insert_admin_inventario
ON detalle_compras;

DROP POLICY IF EXISTS detalle_compras_update_admin_inventario
ON detalle_compras;

DROP POLICY IF EXISTS detalle_compras_delete_admin
ON detalle_compras;


CREATE POLICY detalle_compras_select_admin_inventario
ON detalle_compras
FOR SELECT
TO authenticated
USING (
    public.fn_tiene_rol(
        ARRAY[
            'ADMINISTRADOR',
            'INVENTARIO'
        ]::TEXT[]
    )
);


CREATE POLICY detalle_compras_insert_admin_inventario
ON detalle_compras
FOR INSERT
TO authenticated
WITH CHECK (
    public.fn_tiene_rol(
        ARRAY[
            'ADMINISTRADOR',
            'INVENTARIO'
        ]::TEXT[]
    )
);


CREATE POLICY detalle_compras_update_admin_inventario
ON detalle_compras
FOR UPDATE
TO authenticated
USING (
    public.fn_tiene_rol(
        ARRAY[
            'ADMINISTRADOR',
            'INVENTARIO'
        ]::TEXT[]
    )
)
WITH CHECK (
    public.fn_tiene_rol(
        ARRAY[
            'ADMINISTRADOR',
            'INVENTARIO'
        ]::TEXT[]
    )
);


CREATE POLICY detalle_compras_delete_admin
ON detalle_compras
FOR DELETE
TO authenticated
USING (
    public.fn_tiene_rol(
        ARRAY['ADMINISTRADOR']::TEXT[]
    )
);


/* ============================================================
   12. LOTES
   ============================================================ */

DROP POLICY IF EXISTS lotes_select_authenticated
ON lotes;

DROP POLICY IF EXISTS lotes_write_admin_inventario
ON lotes;

DROP POLICY IF EXISTS lotes_insert_admin_inventario
ON lotes;

DROP POLICY IF EXISTS lotes_update_admin_inventario
ON lotes;

DROP POLICY IF EXISTS lotes_delete_admin
ON lotes;


CREATE POLICY lotes_select_authenticated
ON lotes
FOR SELECT
TO authenticated
USING (TRUE);


CREATE POLICY lotes_insert_admin_inventario
ON lotes
FOR INSERT
TO authenticated
WITH CHECK (
    public.fn_tiene_rol(
        ARRAY[
            'ADMINISTRADOR',
            'INVENTARIO'
        ]::TEXT[]
    )
);


CREATE POLICY lotes_update_admin_inventario
ON lotes
FOR UPDATE
TO authenticated
USING (
    public.fn_tiene_rol(
        ARRAY[
            'ADMINISTRADOR',
            'INVENTARIO'
        ]::TEXT[]
    )
)
WITH CHECK (
    public.fn_tiene_rol(
        ARRAY[
            'ADMINISTRADOR',
            'INVENTARIO'
        ]::TEXT[]
    )
);


CREATE POLICY lotes_delete_admin
ON lotes
FOR DELETE
TO authenticated
USING (
    public.fn_tiene_rol(
        ARRAY['ADMINISTRADOR']::TEXT[]
    )
);


/* ============================================================
   13. VENTAS
   ============================================================ */

DROP POLICY IF EXISTS ventas_access_admin_cajero
ON ventas;

DROP POLICY IF EXISTS ventas_select_admin_cajero
ON ventas;

DROP POLICY IF EXISTS ventas_insert_admin_cajero
ON ventas;

DROP POLICY IF EXISTS ventas_update_admin_cajero
ON ventas;

DROP POLICY IF EXISTS ventas_delete_admin
ON ventas;


CREATE POLICY ventas_select_admin_cajero
ON ventas
FOR SELECT
TO authenticated
USING (
    public.fn_tiene_rol(
        ARRAY[
            'ADMINISTRADOR',
            'CAJERO'
        ]::TEXT[]
    )
);


CREATE POLICY ventas_insert_admin_cajero
ON ventas
FOR INSERT
TO authenticated
WITH CHECK (
    public.fn_tiene_rol(
        ARRAY[
            'ADMINISTRADOR',
            'CAJERO'
        ]::TEXT[]
    )
    AND usuario_id = (SELECT auth.uid())
);


/*
   Administrador puede modificar cualquier venta.

   Cajero solamente ventas registradas bajo
   su propio usuario.
*/

CREATE POLICY ventas_update_admin_cajero
ON ventas
FOR UPDATE
TO authenticated
USING (
    public.fn_tiene_rol(
        ARRAY['ADMINISTRADOR']::TEXT[]
    )

    OR

    (
        public.fn_tiene_rol(
            ARRAY['CAJERO']::TEXT[]
        )
        AND usuario_id = (SELECT auth.uid())
    )
)
WITH CHECK (
    public.fn_tiene_rol(
        ARRAY['ADMINISTRADOR']::TEXT[]
    )

    OR

    (
        public.fn_tiene_rol(
            ARRAY['CAJERO']::TEXT[]
        )
        AND usuario_id = (SELECT auth.uid())
    )
);


CREATE POLICY ventas_delete_admin
ON ventas
FOR DELETE
TO authenticated
USING (
    public.fn_tiene_rol(
        ARRAY['ADMINISTRADOR']::TEXT[]
    )
);


/* ============================================================
   14. DETALLE DE VENTAS
   ============================================================ */

DROP POLICY IF EXISTS detalle_ventas_access_admin_cajero
ON detalle_ventas;

DROP POLICY IF EXISTS detalle_ventas_select_admin_cajero
ON detalle_ventas;

DROP POLICY IF EXISTS detalle_ventas_insert_admin_cajero
ON detalle_ventas;

DROP POLICY IF EXISTS detalle_ventas_update_admin_cajero
ON detalle_ventas;

DROP POLICY IF EXISTS detalle_ventas_delete_admin
ON detalle_ventas;


CREATE POLICY detalle_ventas_select_admin_cajero
ON detalle_ventas
FOR SELECT
TO authenticated
USING (
    public.fn_tiene_rol(
        ARRAY[
            'ADMINISTRADOR',
            'CAJERO'
        ]::TEXT[]
    )
);


CREATE POLICY detalle_ventas_insert_admin_cajero
ON detalle_ventas
FOR INSERT
TO authenticated
WITH CHECK (
    public.fn_tiene_rol(
        ARRAY['ADMINISTRADOR']::TEXT[]
    )

    OR

    (
        public.fn_tiene_rol(
            ARRAY['CAJERO']::TEXT[]
        )

        AND EXISTS (
            SELECT 1
            FROM public.ventas v

            WHERE v.id_venta = venta_id
              AND v.usuario_id =
                  (SELECT auth.uid())
        )
    )
);


CREATE POLICY detalle_ventas_update_admin_cajero
ON detalle_ventas
FOR UPDATE
TO authenticated
USING (
    public.fn_tiene_rol(
        ARRAY['ADMINISTRADOR']::TEXT[]
    )

    OR

    (
        public.fn_tiene_rol(
            ARRAY['CAJERO']::TEXT[]
        )

        AND EXISTS (
            SELECT 1
            FROM public.ventas v

            WHERE v.id_venta = venta_id
              AND v.usuario_id =
                  (SELECT auth.uid())
        )
    )
)
WITH CHECK (
    public.fn_tiene_rol(
        ARRAY['ADMINISTRADOR']::TEXT[]
    )

    OR

    (
        public.fn_tiene_rol(
            ARRAY['CAJERO']::TEXT[]
        )

        AND EXISTS (
            SELECT 1
            FROM public.ventas v

            WHERE v.id_venta = venta_id
              AND v.usuario_id =
                  (SELECT auth.uid())
        )
    )
);


CREATE POLICY detalle_ventas_delete_admin
ON detalle_ventas
FOR DELETE
TO authenticated
USING (
    public.fn_tiene_rol(
        ARRAY['ADMINISTRADOR']::TEXT[]
    )
);


/* ============================================================
   15. CUENTAS POR COBRAR
   ============================================================ */

DROP POLICY IF EXISTS cxc_access_admin_cajero
ON cuentas_por_cobrar;

DROP POLICY IF EXISTS cxc_select_admin_cajero
ON cuentas_por_cobrar;

DROP POLICY IF EXISTS cxc_insert_admin_cajero
ON cuentas_por_cobrar;

DROP POLICY IF EXISTS cxc_update_admin_cajero
ON cuentas_por_cobrar;

DROP POLICY IF EXISTS cxc_delete_admin
ON cuentas_por_cobrar;


CREATE POLICY cxc_select_admin_cajero
ON cuentas_por_cobrar
FOR SELECT
TO authenticated
USING (
    public.fn_tiene_rol(
        ARRAY[
            'ADMINISTRADOR',
            'CAJERO'
        ]::TEXT[]
    )
);


CREATE POLICY cxc_insert_admin_cajero
ON cuentas_por_cobrar
FOR INSERT
TO authenticated
WITH CHECK (
    public.fn_tiene_rol(
        ARRAY[
            'ADMINISTRADOR',
            'CAJERO'
        ]::TEXT[]
    )
);


CREATE POLICY cxc_update_admin_cajero
ON cuentas_por_cobrar
FOR UPDATE
TO authenticated
USING (
    public.fn_tiene_rol(
        ARRAY[
            'ADMINISTRADOR',
            'CAJERO'
        ]::TEXT[]
    )
)
WITH CHECK (
    public.fn_tiene_rol(
        ARRAY[
            'ADMINISTRADOR',
            'CAJERO'
        ]::TEXT[]
    )
);


CREATE POLICY cxc_delete_admin
ON cuentas_por_cobrar
FOR DELETE
TO authenticated
USING (
    public.fn_tiene_rol(
        ARRAY['ADMINISTRADOR']::TEXT[]
    )
);


/* ============================================================
   16. PAGOS DE CUENTAS POR COBRAR
   ============================================================ */

DROP POLICY IF EXISTS pagos_cxc_access_admin_cajero
ON pagos_cuentas_por_cobrar;

DROP POLICY IF EXISTS pagos_cxc_select_admin_cajero
ON pagos_cuentas_por_cobrar;

DROP POLICY IF EXISTS pagos_cxc_insert_admin_cajero
ON pagos_cuentas_por_cobrar;

DROP POLICY IF EXISTS pagos_cxc_update_admin
ON pagos_cuentas_por_cobrar;

DROP POLICY IF EXISTS pagos_cxc_delete_admin
ON pagos_cuentas_por_cobrar;


CREATE POLICY pagos_cxc_select_admin_cajero
ON pagos_cuentas_por_cobrar
FOR SELECT
TO authenticated
USING (
    public.fn_tiene_rol(
        ARRAY[
            'ADMINISTRADOR',
            'CAJERO'
        ]::TEXT[]
    )
);


CREATE POLICY pagos_cxc_insert_admin_cajero
ON pagos_cuentas_por_cobrar
FOR INSERT
TO authenticated
WITH CHECK (
    public.fn_tiene_rol(
        ARRAY[
            'ADMINISTRADOR',
            'CAJERO'
        ]::TEXT[]
    )

    AND usuario_id = (SELECT auth.uid())
);


CREATE POLICY pagos_cxc_update_admin
ON pagos_cuentas_por_cobrar
FOR UPDATE
TO authenticated
USING (
    public.fn_tiene_rol(
        ARRAY['ADMINISTRADOR']::TEXT[]
    )
)
WITH CHECK (
    public.fn_tiene_rol(
        ARRAY['ADMINISTRADOR']::TEXT[]
    )
);


CREATE POLICY pagos_cxc_delete_admin
ON pagos_cuentas_por_cobrar
FOR DELETE
TO authenticated
USING (
    public.fn_tiene_rol(
        ARRAY['ADMINISTRADOR']::TEXT[]
    )
);


/* ============================================================
   17. CUENTAS POR PAGAR
   ============================================================ */

DROP POLICY IF EXISTS cxp_access_admin_inventario
ON cuentas_por_pagar;

DROP POLICY IF EXISTS cxp_select_admin_inventario
ON cuentas_por_pagar;

DROP POLICY IF EXISTS cxp_insert_admin_inventario
ON cuentas_por_pagar;

DROP POLICY IF EXISTS cxp_update_admin_inventario
ON cuentas_por_pagar;

DROP POLICY IF EXISTS cxp_delete_admin
ON cuentas_por_pagar;


CREATE POLICY cxp_select_admin_inventario
ON cuentas_por_pagar
FOR SELECT
TO authenticated
USING (
    public.fn_tiene_rol(
        ARRAY[
            'ADMINISTRADOR',
            'INVENTARIO'
        ]::TEXT[]
    )
);


CREATE POLICY cxp_insert_admin_inventario
ON cuentas_por_pagar
FOR INSERT
TO authenticated
WITH CHECK (
    public.fn_tiene_rol(
        ARRAY[
            'ADMINISTRADOR',
            'INVENTARIO'
        ]::TEXT[]
    )
);


CREATE POLICY cxp_update_admin_inventario
ON cuentas_por_pagar
FOR UPDATE
TO authenticated
USING (
    public.fn_tiene_rol(
        ARRAY[
            'ADMINISTRADOR',
            'INVENTARIO'
        ]::TEXT[]
    )
)
WITH CHECK (
    public.fn_tiene_rol(
        ARRAY[
            'ADMINISTRADOR',
            'INVENTARIO'
        ]::TEXT[]
    )
);


CREATE POLICY cxp_delete_admin
ON cuentas_por_pagar
FOR DELETE
TO authenticated
USING (
    public.fn_tiene_rol(
        ARRAY['ADMINISTRADOR']::TEXT[]
    )
);


/* ============================================================
   18. PAGOS DE CUENTAS POR PAGAR
   ============================================================ */

DROP POLICY IF EXISTS pagos_cxp_access_admin_inventario
ON pagos_cuentas_por_pagar;

DROP POLICY IF EXISTS pagos_cxp_select_admin_inventario
ON pagos_cuentas_por_pagar;

DROP POLICY IF EXISTS pagos_cxp_insert_admin_inventario
ON pagos_cuentas_por_pagar;

DROP POLICY IF EXISTS pagos_cxp_update_admin
ON pagos_cuentas_por_pagar;

DROP POLICY IF EXISTS pagos_cxp_delete_admin
ON pagos_cuentas_por_pagar;


CREATE POLICY pagos_cxp_select_admin_inventario
ON pagos_cuentas_por_pagar
FOR SELECT
TO authenticated
USING (
    public.fn_tiene_rol(
        ARRAY[
            'ADMINISTRADOR',
            'INVENTARIO'
        ]::TEXT[]
    )
);


CREATE POLICY pagos_cxp_insert_admin_inventario
ON pagos_cuentas_por_pagar
FOR INSERT
TO authenticated
WITH CHECK (
    public.fn_tiene_rol(
        ARRAY[
            'ADMINISTRADOR',
            'INVENTARIO'
        ]::TEXT[]
    )

    AND usuario_id = (SELECT auth.uid())
);


CREATE POLICY pagos_cxp_update_admin
ON pagos_cuentas_por_pagar
FOR UPDATE
TO authenticated
USING (
    public.fn_tiene_rol(
        ARRAY['ADMINISTRADOR']::TEXT[]
    )
)
WITH CHECK (
    public.fn_tiene_rol(
        ARRAY['ADMINISTRADOR']::TEXT[]
    )
);


CREATE POLICY pagos_cxp_delete_admin
ON pagos_cuentas_por_pagar
FOR DELETE
TO authenticated
USING (
    public.fn_tiene_rol(
        ARRAY['ADMINISTRADOR']::TEXT[]
    )
);


/* ============================================================
   19. MOVIMIENTOS DE INVENTARIO
   ============================================================ */

DROP POLICY IF EXISTS movimientos_select_authenticated
ON movimientos_inventario;

DROP POLICY IF EXISTS movimientos_insert_authenticated_roles
ON movimientos_inventario;

DROP POLICY IF EXISTS movimientos_insert_roles
ON movimientos_inventario;

DROP POLICY IF EXISTS movimientos_update_admin
ON movimientos_inventario;

DROP POLICY IF EXISTS movimientos_delete_admin
ON movimientos_inventario;


/* Todos los usuarios autenticados pueden consultar Kardex */

CREATE POLICY movimientos_select_authenticated
ON movimientos_inventario
FOR SELECT
TO authenticated
USING (TRUE);


/*
   ADMINISTRADOR e INVENTARIO pueden generar
   movimientos de inventario.

   El usuario registrado en el movimiento debe
   ser el usuario autenticado.

   CAJERO solamente puede generar movimientos
   del tipo VENTA y relacionados con una venta
   registrada por él mismo.
*/

CREATE POLICY movimientos_insert_roles
ON movimientos_inventario
FOR INSERT
TO authenticated
WITH CHECK (

    (
        public.fn_tiene_rol(
            ARRAY[
                'ADMINISTRADOR',
                'INVENTARIO'
            ]::TEXT[]
        )

        AND usuario_id = (SELECT auth.uid())
    )

    OR

    (
        public.fn_tiene_rol(
            ARRAY['CAJERO']::TEXT[]
        )

        AND usuario_id = (SELECT auth.uid())

        AND detalle_venta_id IS NOT NULL

        AND detalle_compra_id IS NULL

        AND EXISTS (
            SELECT 1
            FROM public.tipos_movimientos tm

            WHERE tm.id_tipo_movimiento =
                  tipo_movimiento_id

              AND tm.nombre = 'VENTA'
        )

        AND EXISTS (
            SELECT 1

            FROM public.detalle_ventas dv

            JOIN public.ventas v
                ON v.id_venta = dv.venta_id

            WHERE dv.id_detalle_venta =
                  detalle_venta_id

              AND v.usuario_id =
                  (SELECT auth.uid())
        )
    )
);


/*
   Solo administrador puede modificar movimientos
   históricos.
*/

CREATE POLICY movimientos_update_admin
ON movimientos_inventario
FOR UPDATE
TO authenticated
USING (
    public.fn_tiene_rol(
        ARRAY['ADMINISTRADOR']::TEXT[]
    )
)
WITH CHECK (
    public.fn_tiene_rol(
        ARRAY['ADMINISTRADOR']::TEXT[]
    )
);


/*
   Solo administrador puede eliminar movimientos.
*/

CREATE POLICY movimientos_delete_admin
ON movimientos_inventario
FOR DELETE
TO authenticated
USING (
    public.fn_tiene_rol(
        ARRAY['ADMINISTRADOR']::TEXT[]
    )
);


COMMIT;

DROP POLICY IF EXISTS ventas_insert_admin_cajero
ON ventas;


DROP POLICY IF EXISTS detalle_ventas_insert_admin_cajero
ON detalle_ventas;


DROP POLICY IF EXISTS compras_insert_admin_inventario
ON compras;



DROP POLICY IF EXISTS detalle_compras_insert_admin_inventario
ON detalle_compras;

DROP POLICY IF EXISTS lotes_insert_admin_inventario
ON lotes;


DROP POLICY IF EXISTS movimientos_insert_roles
ON movimientos_inventario;

DROP POLICY IF EXISTS movimientos_insert_authenticated_roles
ON movimientos_inventario;