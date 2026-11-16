/* ============================================================
   TIENDA-APP
   08_permissions.sql

   Permisos SQL finales para la aplicación.
   PostgreSQL / Supabase
   ============================================================ */

BEGIN;


/* ============================================================
   1. BLOQUEAR ACCESO ANÓNIMO A LAS TABLAS
   ============================================================ */

REVOKE ALL PRIVILEGES ON TABLE
    public.categorias,
    public.productos,
    public.proveedores,
    public.roles,
    public.formas_pago,
    public.tipos_movimientos,
    public.clientes,
    public.usuarios,
    public.compras,
    public.detalle_compras,
    public.lotes,
    public.ventas,
    public.detalle_ventas,
    public.cuentas_por_cobrar,
    public.pagos_cuentas_por_cobrar,
    public.cuentas_por_pagar,
    public.pagos_cuentas_por_pagar,
    public.movimientos_inventario
FROM anon;


/* ============================================================
   2. REINICIAR PRIVILEGIOS DE authenticated

   Primero quitamos permisos generales para después conceder
   solamente lo necesario.
   ============================================================ */

REVOKE ALL PRIVILEGES ON TABLE
    public.categorias,
    public.productos,
    public.proveedores,
    public.roles,
    public.formas_pago,
    public.tipos_movimientos,
    public.clientes,
    public.usuarios,
    public.compras,
    public.detalle_compras,
    public.lotes,
    public.ventas,
    public.detalle_ventas,
    public.cuentas_por_cobrar,
    public.pagos_cuentas_por_cobrar,
    public.cuentas_por_pagar,
    public.pagos_cuentas_por_pagar,
    public.movimientos_inventario
FROM authenticated;


/* ============================================================
   3. LECTURA

   Damos SELECT a authenticated.

   RLS seguirá decidiendo qué usuario realmente puede consultar
   cada tabla.
   ============================================================ */

GRANT SELECT ON TABLE
    public.categorias,
    public.productos,
    public.proveedores,
    public.roles,
    public.formas_pago,
    public.tipos_movimientos,
    public.clientes,
    public.usuarios,
    public.compras,
    public.detalle_compras,
    public.lotes,
    public.ventas,
    public.detalle_ventas,
    public.cuentas_por_cobrar,
    public.pagos_cuentas_por_cobrar,
    public.cuentas_por_pagar,
    public.pagos_cuentas_por_pagar,
    public.movimientos_inventario
TO authenticated;


/* ============================================================
   4. CATEGORÍAS

   Las policies RLS decidirán:
   ADMINISTRADOR / INVENTARIO.
   ============================================================ */

GRANT INSERT, UPDATE, DELETE
ON TABLE public.categorias
TO authenticated;


/* ============================================================
   5. PRODUCTOS

   IMPORTANTE:
   existencia y ultimo_costo NO se conceden.

   Esas columnas solamente deben cambiar mediante nuestra
   lógica interna.
   ============================================================ */

GRANT INSERT (
    categoria_id,
    codigo_barras,
    nombre,
    precio_venta,
    existencia_minima,
    imagen,
    activo,
    controla_lotes
)
ON public.productos
TO authenticated;


GRANT UPDATE (
    categoria_id,
    codigo_barras,
    nombre,
    precio_venta,
    existencia_minima,
    imagen,
    activo
)
ON public.productos
TO authenticated;


/*
   Tampoco permitimos cambiar controla_lotes libremente
   después de creado el producto.

   Cambiar esa propiedad cuando ya existen movimientos
   podría generar inconsistencias.
*/


GRANT DELETE
ON public.productos
TO authenticated;


/* ============================================================
   6. PROVEEDORES
   ============================================================ */

GRANT INSERT, UPDATE, DELETE
ON public.proveedores
TO authenticated;


/* ============================================================
   7. CLIENTES
   ============================================================ */

GRANT INSERT, UPDATE, DELETE
ON public.clientes
TO authenticated;


/* ============================================================
   8. USUARIOS

   Las RLS harán que solamente ADMINISTRADOR pueda administrar
   usuarios.
   ============================================================ */

GRANT INSERT, UPDATE, DELETE
ON public.usuarios
TO authenticated;


/* ============================================================
   9. CATÁLOGOS INTERNOS

   roles
   formas_pago
   tipos_movimientos

   Los dejamos como SOLO LECTURA desde la aplicación.

   Esto es intencional porque nuestra lógica depende de nombres
   como:

   ADMINISTRADOR
   CAJERO
   INVENTARIO

   CREDITO

   COMPRA
   VENTA

   Si alguien cambia esos nombres desde React podría romper
   funciones y RPC.
   ============================================================ */

/* No necesitamos GRANT adicional.
   Ya poseen SELECT mediante el bloque anterior. */


/* ============================================================
   10. COMPRAS

   NO permitimos INSERT/UPDATE/DELETE directo.

   Las nuevas compras deben pasar por:
   registrar_compra()
   ============================================================ */

/* SELECT ya está concedido. */


/* ============================================================
   11. DETALLE DE COMPRAS

   Solo lo modifica internamente registrar_compra().
   ============================================================ */

/* SELECT únicamente. */


/* ============================================================
   12. LOTES

   Los lotes de entrada se crean mediante registrar_compra().
   ============================================================ */

/* SELECT únicamente. */


/* ============================================================
   13. VENTAS

   Las nuevas ventas deben pasar por:
   registrar_venta()
   ============================================================ */

/* SELECT únicamente. */


/* ============================================================
   14. DETALLE DE VENTAS

   Lo administra registrar_venta().
   ============================================================ */

/* SELECT únicamente. */


/* ============================================================
   15. MOVIMIENTOS DE INVENTARIO

   MUY IMPORTANTE:

   React NO debe crear movimientos directamente.

   registrar_venta() y registrar_compra() se encargan de ellos.
   ============================================================ */

/* SELECT únicamente. */


/* ============================================================
   16. CUENTAS POR COBRAR

   saldo_pendiente
   estado
   monto_original

   son datos controlados por el sistema.

   Solamente dejamos modificar fecha_limite.
   ============================================================ */

GRANT UPDATE (
    fecha_limite
)
ON public.cuentas_por_cobrar
TO authenticated;


/* ============================================================
   17. PAGOS DE CUENTAS POR COBRAR

   Registrar un pago es una única operación y nuestros triggers
   ya validan:
   - monto positivo
   - no sobrepago
   - saldo
   - estado

   No permitimos cambiar id, fecha ni editar pagos existentes.
   ============================================================ */

GRANT INSERT (
    cuenta_por_cobrar_id,
    usuario_id,
    forma_pago_id,
    monto
)
ON public.pagos_cuentas_por_cobrar
TO authenticated;


/* ============================================================
   18. CUENTAS POR PAGAR
   ============================================================ */

GRANT UPDATE (
    fecha_limite
)
ON public.cuentas_por_pagar
TO authenticated;


/* ============================================================
   19. PAGOS DE CUENTAS POR PAGAR
   ============================================================ */

GRANT INSERT (
    cuenta_por_pagar_id,
    usuario_id,
    forma_pago_id,
    monto
)
ON public.pagos_cuentas_por_pagar
TO authenticated;


/* ============================================================
   20. SECUENCIAS

   Algunas operaciones permitidas utilizan columnas IDENTITY.
   ============================================================ */

GRANT USAGE, SELECT
ON ALL SEQUENCES IN SCHEMA public
TO authenticated;


/* ============================================================
   21. RPC registrar_venta
   ============================================================ */

REVOKE ALL
ON FUNCTION public.registrar_venta(
    INTEGER,
    INTEGER,
    JSONB,
    DATE
)
FROM PUBLIC;

REVOKE ALL
ON FUNCTION public.registrar_venta(
    INTEGER,
    INTEGER,
    JSONB,
    DATE
)
FROM anon;

GRANT EXECUTE
ON FUNCTION public.registrar_venta(
    INTEGER,
    INTEGER,
    JSONB,
    DATE
)
TO authenticated;


/* ============================================================
   22. RPC registrar_compra
   ============================================================ */

REVOKE ALL
ON FUNCTION public.registrar_compra(
    INTEGER,
    INTEGER,
    VARCHAR,
    JSONB,
    DATE
)
FROM PUBLIC;

REVOKE ALL
ON FUNCTION public.registrar_compra(
    INTEGER,
    INTEGER,
    VARCHAR,
    JSONB,
    DATE
)
FROM anon;

GRANT EXECUTE
ON FUNCTION public.registrar_compra(
    INTEGER,
    INTEGER,
    VARCHAR,
    JSONB,
    DATE
)
TO authenticated;


COMMIT;