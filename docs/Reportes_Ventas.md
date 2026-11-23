# Reportes de ventas por período

Disponible para ADMINISTRADOR. Resume ventas registradas de hasta 366 días,
con fechas inclusivas en horario de Guatemala.

## Instalación

Aplica después del parche Ajustes de inventario. Desde la raíz del proyecto:

```bash
git apply --check ~/Descargas/Tienda_Reportes_Ventas.patch
git apply ~/Descargas/Tienda_Reportes_Ventas.patch
npm run build
```

Supabase ya fue actualizado. No necesitas ejecutar SQL adicional ni instalar
dependencias. En una instalación nueva, `database/17_reportes_ventas.sql` se aplica
después de 01–16. La actualización no crea ventas ni modifica existencias.

## Consultar

1. Abre **Reportes**. Inicialmente consulta desde el primer día del mes hasta hoy.
2. Selecciona Desde y Hasta y pulsa **Consultar período**.
3. Revisa ventas, transacciones, ticket promedio y unidades vendidas.
4. Examina la gráfica. **Ver detalle diario** muestra los importes exactos,
   transacciones y unidades de todos los días, incluidos los días sin ventas.
5. Alterna el ranking entre cantidad e importe: cada opción consulta su propia
   clasificación completa de los primeros 20, sin ordenar solo el subconjunto anterior.
6. Revisa el catálogo activo con menor venta y la distribución por forma de pago.
7. **Descargar ventas diarias CSV** exporta todo el detalle diario del período,
   con fechas ISO, importes GTQ y decimales con punto.

## Interpretación

Las ventas incluyen EFECTIVO, TARJETA, TRANSFERENCIA y CREDITO. Los abonos no vuelven
a sumarse como ventas. El flujo de efectivo y el conteo físico se revisan en sus
módulos. El importe vendido no es utilidad: falta registrar costos históricos de
venta para calcular márgenes fiables; no se usa el costo actual para reescribir el pasado.

El ranking incluye productos vendidos que hoy estén inactivos. La sección de menor
venta usa el catálogo activo actual. Un producto incorporado después del período
puede aparecer sin ventas; revisa esa circunstancia antes de reducir compras.
Los nombres, existencias y mínimos de productos son los actuales, no una fotografía
del inventario al final del período. Las listas muestran los primeros 20 productos.

Se excluyen ventas anuladas y ventas sin detalles o cuyo encabezado no coincida
con sus detalles. Estas últimas aparecen como incidencias, sin borrar sus registros.
El ticket promedio divide el importe de ventas válidas entre sus transacciones;
las ventas válidas sin cargo conservan sus unidades y transacción, con importe cero.

## Verificación

```bash
npm run build
npm run lint
node --test tests/reporteValidation.test.cjs
```

`tests/reportes_rollback.sql` prueba sumas sin duplicar encabezados, rankings,
ventas a crédito, límites horarios, días vacíos, productos inactivos, documentos
inconsistentes y permisos. Ejecuta el archivo completo como postgres en SQL Editor.
Los fixtures se revierten al terminar. Los saltos de secuencia son normales.
