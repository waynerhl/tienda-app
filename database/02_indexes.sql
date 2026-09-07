/* ============================================================
   TIENDA-APP
   ÍNDICES V1
   PostgreSQL / Supabase
   ============================================================ */


/* ============================================================
   PRODUCTOS
   ============================================================ */

/*
   Buscar productos por categoría será muy frecuente.
*/
CREATE INDEX IF NOT EXISTS idx_productos_categoria
ON productos(categoria_id);


/*
   Búsquedas por nombre.

   Este índice ayuda especialmente con búsquedas ordenadas
   o por igualdad. Más adelante podemos mejorar búsquedas
   parciales con trigramas.
*/
CREATE INDEX IF NOT EXISTS idx_productos_nombre
ON productos(nombre);


/* ============================================================
   COMPRAS
   ============================================================ */

CREATE INDEX IF NOT EXISTS idx_compras_proveedor
ON compras(proveedor_id);

CREATE INDEX IF NOT EXISTS idx_compras_usuario
ON compras(usuario_id);

CREATE INDEX IF NOT EXISTS idx_compras_forma_pago
ON compras(forma_pago_id);

CREATE INDEX IF NOT EXISTS idx_compras_fecha
ON compras(fecha);


/* ============================================================
   DETALLE DE COMPRAS
   ============================================================ */

CREATE INDEX IF NOT EXISTS idx_detalle_compras_compra
ON detalle_compras(compra_id);

CREATE INDEX IF NOT EXISTS idx_detalle_compras_producto
ON detalle_compras(producto_id);


/* ============================================================
   LOTES
   ============================================================ */

CREATE INDEX IF NOT EXISTS idx_lotes_detalle_compra
ON lotes(detalle_compra_id);


/*
   Muy útil para:
   "¿Qué productos vencen próximamente?"
   
   Solo indexamos lotes que realmente tienen vencimiento.
*/
CREATE INDEX IF NOT EXISTS idx_lotes_fecha_vencimiento
ON lotes(fecha_vencimiento)
WHERE fecha_vencimiento IS NOT NULL;


/* ============================================================
   VENTAS
   ============================================================ */

CREATE INDEX IF NOT EXISTS idx_ventas_cliente
ON ventas(cliente_id)
WHERE cliente_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_ventas_usuario
ON ventas(usuario_id);

CREATE INDEX IF NOT EXISTS idx_ventas_forma_pago
ON ventas(forma_pago_id);

CREATE INDEX IF NOT EXISTS idx_ventas_fecha
ON ventas(fecha);


/* ============================================================
   DETALLE DE VENTAS
   ============================================================ */

CREATE INDEX IF NOT EXISTS idx_detalle_ventas_venta
ON detalle_ventas(venta_id);

CREATE INDEX IF NOT EXISTS idx_detalle_ventas_producto
ON detalle_ventas(producto_id);


/* ============================================================
   CUENTAS POR COBRAR
   ============================================================ */

/*
   venta_id ya tiene UNIQUE, por lo tanto ya tiene índice.
*/


CREATE INDEX IF NOT EXISTS idx_cuentas_por_cobrar_estado
ON cuentas_por_cobrar(estado);


/*
   Útil para consultar créditos pendientes/vencidos.
*/
CREATE INDEX IF NOT EXISTS idx_cuentas_por_cobrar_fecha_limite
ON cuentas_por_cobrar(fecha_limite)
WHERE saldo_pendiente > 0;


/* ============================================================
   PAGOS CUENTAS POR COBRAR
   ============================================================ */

CREATE INDEX IF NOT EXISTS idx_pagos_cxc_cuenta
ON pagos_cuentas_por_cobrar(cuenta_por_cobrar_id);

CREATE INDEX IF NOT EXISTS idx_pagos_cxc_fecha
ON pagos_cuentas_por_cobrar(fecha);


/* ============================================================
   CUENTAS POR PAGAR
   ============================================================ */

/*
   compra_id ya tiene UNIQUE.
*/


CREATE INDEX IF NOT EXISTS idx_cuentas_por_pagar_estado
ON cuentas_por_pagar(estado);

CREATE INDEX IF NOT EXISTS idx_cuentas_por_pagar_fecha_limite
ON cuentas_por_pagar(fecha_limite)
WHERE saldo_pendiente > 0;


/* ============================================================
   PAGOS CUENTAS POR PAGAR
   ============================================================ */

CREATE INDEX IF NOT EXISTS idx_pagos_cxp_cuenta
ON pagos_cuentas_por_pagar(cuenta_por_pagar_id);

CREATE INDEX IF NOT EXISTS idx_pagos_cxp_fecha
ON pagos_cuentas_por_pagar(fecha);


/* ============================================================
   MOVIMIENTOS DE INVENTARIO
   ============================================================ */

/*
   Probablemente uno de los índices más utilizados.
*/
CREATE INDEX IF NOT EXISTS idx_movimientos_producto
ON movimientos_inventario(producto_id);


/*
   Para calcular existencia e historial de un lote.
*/
CREATE INDEX IF NOT EXISTS idx_movimientos_lote
ON movimientos_inventario(lote_id)
WHERE lote_id IS NOT NULL;


/*
   Para consultar movimientos por tipo.
*/
CREATE INDEX IF NOT EXISTS idx_movimientos_tipo
ON movimientos_inventario(tipo_movimiento_id);


/*
   Para auditoría: movimientos realizados por usuario.
*/
CREATE INDEX IF NOT EXISTS idx_movimientos_usuario
ON movimientos_inventario(usuario_id);


/*
   Para Kardex e historial cronológico.
*/
CREATE INDEX IF NOT EXISTS idx_movimientos_fecha
ON movimientos_inventario(fecha);


/*
   Especialmente útil para:

   "Muéstrame todos los movimientos de Coca Cola
    del más reciente al más antiguo."
*/
CREATE INDEX IF NOT EXISTS idx_movimientos_producto_fecha
ON movimientos_inventario(producto_id, fecha DESC);