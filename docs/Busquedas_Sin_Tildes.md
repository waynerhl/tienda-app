# Búsquedas sin tildes

Aplicar después de Presentaciones de venta. La migración 24 ya está aplicada en Supabase.

Productos, Ventas, Compras, Inventario, Inicial, Lista de compras, Rotación, Clientes y Proveedores permiten buscar nombres con o sin tildes y sin distinguir mayúsculas. Por ejemplo: Cajón/Cajon y Café/Cafe. La ñ sigue siendo una letra distinta; ü/u se consideran equivalentes.

Los nombres originales se conservan. Los códigos de barras conservan la búsqueda exacta, incluidos los ceros iniciales.

La columna calculada de búsqueda se actualiza automáticamente al crear o editar productos. No hay cambios en costos, precios, existencias, Caja o Reserva.

Verificación: npm run build, npm run lint, node --test tests/busquedas.test.cjs y tests/busquedas_rollback.sql (como postgres, completo). Las filas de prueba se revierten; no se crean compras ni ventas.
