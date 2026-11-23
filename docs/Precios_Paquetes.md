# Presentaciones: paquetes completos y unidades sueltas

Requiere los parches previos, hasta Caja y Reserva, y la migración `database/23_precios_paquetes.sql`. No crea productos ni configura precios reales automáticamente: cada presentación se define desde el catálogo.

## Configuración

En **Productos**, busca el artículo y pulsa **Presentación**. Activa Habilitar precio por paquete y completa nombre, unidades por paquete y precio total.

| Producto | Precio individual existente | Nombre | Unidades por paquete | Precio total del paquete |
| --- | --- | --- | --- | --- |
| Leche Lala | Q14.00 | Caja | 12 | Q145.00 |
| Huevos | Q1.50 | Cartón | 30 | Q38.00 |

El precio individual se sigue editando con Editar producto. El precio del paquete es el importe completo: no dividas Q145 entre 12 ni reemplaces Q14 por el promedio. El precio del paquete se aplica tal como se configura; revisa que represente la tarifa que deseas cobrar, especialmente si luego cambias el precio individual.

La opción **Al pulsar Agregar en Ventas, añadir un paquete completo** permite que los huevos se agreguen inicialmente por cartón. Sin marcarla, Agregar añade una unidad. Esta preferencia no cambia la unidad de inventario ni las fórmulas de cobro.

Cada producto admite una presentación adicional a la unidad en esta versión. Deshabilitarla hace que las ventas futuras cobren únicamente el precio individual. No modifica compras, cantidades, lotes, caja ni ventas anteriores. Administrador e Inventario pueden configurarla; Cajero puede utilizarla al vender.

## Venta

Después de configurar, entra a Ventas y pulsa **Actualizar datos**. Si el producto ya estaba en un carrito sin confirmar, quítalo y agrégalo nuevamente para incorporar su configuración actual. No descartes una confirmación incierta: primero reintenta esa misma referencia para comprobar si ya se registró.

- **Agregar** añade una unidad o un paquete completo, según la preferencia del producto. El resultado de búsqueda indica cuántas unidades añadirá.
- El botón adicional permite añadir el otro tamaño: +1 Caja (12) o +1 unidad, por ejemplo.
- **Cantidad total en unidades** siempre expresa la cantidad base. Para dos cartones son 60 huevos, no 2.
- El carrito muestra paquetes completos, unidades sueltas, importe de la línea, total y cambio si cobras en efectivo.
- La presentación es una regla de precio por cantidad; no lleva un inventario separado de cajas selladas. Entrega físicamente las unidades del lote correspondiente al orden de vencimiento del inventario.

| Venta | Desglose | Total |
| --- | --- | --- |
| 12 leches | 1 caja | Q145.00 |
| 13 leches | 1 caja + 1 unidad | Q159.00 |
| 25 leches | 2 cajas + 1 unidad | Q304.00 |
| 30 leches | 2 cajas + 6 unidades | Q374.00 |
| 29 huevos | 29 unidades individuales | Q43.50 |
| 30 huevos | 1 cartón | Q38.00 |
| 32 huevos | 1 cartón + 2 unidades | Q41.00 |

El cálculo se hace por producto dentro de cada venta; no reúne cantidades de clientes o ventas diferentes. Esta regla aplica precios especiales a paquetes completos, no un precio mayorista por unidad a todos los sobrantes. Por eso 29 huevos pueden costar más que un cartón de 30; así se ha definido la tarifa, no es un error de redondeo.

## Inventario, costos y dinero

Se mantiene un solo producto y una sola existencia por unidades. Vender 13 leches descuenta 13 unidades; vender dos cartones descuenta 60 huevos. En productos con lotes continúa el consumo FEFO y se conserva el costo real de las unidades de cada lote, de compra o de inventario inicial.

La base calcula el subtotal así:

`paquetes = cantidad / unidades_por_paquete` (división entera)

`sueltas = cantidad % unidades_por_paquete`

`subtotal = paquetes × precio_total_paquete + sueltas × precio_individual`

El precio individual y los datos del paquete se conservan en el detalle de la venta. El subtotal es generado por la base, sin prorratear el precio de la caja. Los detalles antiguos mantienen sus datos de presentación nulos y sus importes anteriores. Los reportes suman esos subtotales; los costos siguen multiplicándose por unidades físicas, no por cajas.

Una venta a crédito crea la deuda por el importe exacto cobrado. Una venta en efectivo entra a Caja por ese importe. Reserva, traslados y Compras mantienen sus reglas anteriores. Este cambio no incorpora presentaciones para ingresar compras: allí se mantienen cantidades y costos por unidad base.

## Cambios de precios y reintentos

Cada configuración tiene una versión. Al cobrar, Supabase verifica el precio individual esperado y la versión de la presentación. Si cambiaron, rechaza la venta sin modificar existencias ni dinero y pide actualizar y volver a agregar el producto. La app no envía un subtotal editable: lo calcula nuevamente la base.

Las confirmaciones conservan UUID, cantidades, precio esperado y versión en el navegador. Reintentar una venta ya registrada devuelve su comprobante y total original, aunque el catálogo haya cambiado después. No descuenta unidades otra vez. Una aplicación anterior que no conoce presentaciones no puede registrar una venta nueva de un producto con paquete activo; debe actualizarse primero.

## Verificación

- `npm run build` y `npm run lint`.
- `node --test tests/presentacionValidation.test.cjs`.
- `tests/presentaciones_rollback.sql`: leche y huevos en distintas cantidades, stock por unidades, FEFO, costos, conciliación de reportes, crédito, cambios de tarifa, desactivación, versiones y reintentos. Todos los datos de prueba se revierten.
- Pruebas existentes de costos, inventario inicial, efectivo, reportes y rotación.
- Prueba de interfaz: configuración de una caja, paquetes más sobrantes, cambio en efectivo, selección inicial por cartón y recuperación de una respuesta incierta con el mismo UUID.

La prueba existente de Caja que exige que no haya caja de hoy se omite cuando la tienda ya inició su jornada; no se modifica una apertura real para ejecutar pruebas.
