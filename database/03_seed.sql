/* ============================================================
   TIENDA-APP
   03_seed.sql

   Datos iniciales necesarios para el funcionamiento
   de la aplicación.
   PostgreSQL / Supabase
   ============================================================ */

BEGIN;


/* ============================================================
   1. ROLES
   ============================================================ */

INSERT INTO public.roles (nombre)
VALUES
    ('ADMINISTRADOR'),
    ('CAJERO'),
    ('INVENTARIO')
ON CONFLICT (nombre) DO NOTHING;


/* ============================================================
   2. FORMAS DE PAGO
   ============================================================ */

INSERT INTO public.formas_pago (nombre)
VALUES
    ('EFECTIVO'),
    ('TRANSFERENCIA'),
    ('TARJETA'),
    ('CREDITO')
ON CONFLICT (nombre) DO NOTHING;


/* ============================================================
   3. TIPOS DE MOVIMIENTO DE INVENTARIO

   factor:
    1  = entrada de inventario
   -1  = salida de inventario
   ============================================================ */

INSERT INTO public.tipos_movimientos (
    nombre,
    factor
)
VALUES
    ('COMPRA', 1),
    ('VENTA', -1),

    ('DEVOLUCION_CLIENTE', 1),
    ('DEVOLUCION_PROVEEDOR', -1),

    ('VENCIMIENTO', -1),
    ('PERDIDA', -1),

    ('AJUSTE_POSITIVO', 1),
    ('AJUSTE_NEGATIVO', -1)

ON CONFLICT (nombre)
DO UPDATE SET
    factor = EXCLUDED.factor;


/* ============================================================
   4. CATEGORÍAS INICIALES

   Estas sí pueden ampliarse posteriormente desde la
   aplicación por ADMINISTRADOR / INVENTARIO.
   ============================================================ */

INSERT INTO public.categorias (nombre)
VALUES
    ('BEBIDAS'),
    ('ALIMENTOS'),
    ('SNACKS'),
    ('LACTEOS'),
    ('PANADERIA'),
    ('ENLATADOS'),
    ('CONDIMENTOS'),
    ('LIMPIEZA'),
    ('HIGIENE PERSONAL'),
    ('CUIDADO DEL HOGAR'),
    ('OTROS')

ON CONFLICT (nombre) DO NOTHING;


COMMIT;