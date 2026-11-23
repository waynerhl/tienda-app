# Costos conservados y utilidad bruta estimada

Esta actualización añade una sección a **Reportes**. Conserva costos en los
movimientos de venta nuevos y muestra qué parte de las ventas tiene costo completo.
Ventas y costos se calculan juntos para que correspondan al mismo momento.

## Instalación

Aplica después del parche Reportes de ventas:

```bash
git apply --check ~/Descargas/Tienda_Costos_Utilidad.patch
git apply ~/Descargas/Tienda_Costos_Utilidad.patch
npm run build
```

Supabase ya está actualizado. No necesitas SQL adicional ni dependencias nuevas.
En instalaciones nuevas, `database/18_costos_venta.sql` se aplica después de 01–17.
Las ventas normales siguen usando el mismo formulario.

## Métodos de costo

| Producto | Costo conservado al vender |
| --- | --- |
| Con lotes | Costo unitario de compra de cada lote consumido por FEFO |
| Sin lotes | Último costo conocido del producto en ese momento |
| Sin costo conocido | Se guarda como desconocido; no se sustituye por cero |

En productos sin lotes se trata de una estimación basada en el último costo,
no de una valoración FIFO o promedio ponderado. Para lotes, una venta que consume
varios lotes suma las cantidades al costo de compra de cada uno. Los vencidos
siguen excluidos de la venta según las reglas existentes.

Una compra posterior no modifica el costo conservado de una venta anterior.
No se rellenan ventas antiguas con el costo actual. Estas ventas pueden quedar
fuera de la estimación hasta disponer de evidencia histórica fiable.

## Lectura del reporte

Abre **Reportes**, selecciona el período y busca **Costos y utilidad bruta estimada**.

- Ventas con costo identificado: subtotal de las líneas completamente costeadas.
- Costo registrado: suma de costos conservados de esas líneas.
- Utilidad bruta estimada: ventas con costo menos costo registrado.
- Margen bruto estimado: utilidad bruta estimada ÷ ventas con costo × 100.

Una línea solo está completa si todas sus unidades vendidas tienen movimientos
de salida vinculados y costo identificado. No se usa un costo parcial de un lote
para atribuir utilidad a toda la línea. Las líneas sin costo se indican con su
importe vendido y quedan fuera de la utilidad. Si no hay ninguna línea con costo,
la pantalla muestra guiones en utilidad y margen.

El margen puede ser negativo. Si el importe vendido con costo es cero, no se
divide entre cero: se muestra un guion. Una venta sin cargo puede tener costo y
por tanto pérdida bruta.

Los rankings muestran hasta 20 productos por mayor o menor utilidad bruta estimada
sobre sus líneas con costo. La columna de líneas sin costo permite reconocer
productos con cobertura parcial. No equivalen automáticamente a rentabilidad neta.

Los gastos operativos, otras pérdidas y demás conceptos necesarios para utilidad
neta se analizan por separado. Los retiros personales se mantienen separados en
Caja. Este cambio no modifica existencias históricas, precios ni cierres de caja.

## Verificación

`npm run build` y `npm run lint` verifican el frontend.
`tests/costos_rollback.sql` prueba conservación del costo después de otra compra,
lotes FEFO de costos diferentes, costo desconocido, cobertura parcial, margen,
ventas sin cargo, pérdidas brutas y permisos. Ejecuta el archivo completo como
postgres en SQL Editor. Revierte sus fixtures al terminar; las secuencias pueden
dejar saltos normales.
