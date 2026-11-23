# Rotación y cobertura de productos

Disponible en **Rotación** para el administrador. Requiere los módulos anteriores, incluido Carga de módulos, y `database/20_rotacion_productos.sql` aplicado en Supabase.

## Uso

1. Selecciona las fechas de ventas: hasta 366 días inclusivos, sin fechas futuras. Al entrar se consultan los últimos 30 días.
2. Indica cuántos días quieres cubrir con inventario (1–90, inicialmente 7).
3. Busca por parte del nombre o código de barras exacto y filtra por reposición, sin ventas o inventario por revisar.
4. Ordena por prioridad de reposición o por unidades vendidas, de mayor a menor o al contrario.
5. Revisa el promedio, cobertura y cantidad sugerida. Decide las cantidades y guárdalas manualmente en Lista de compras.

Los filtros se aplican al pulsar Consultar rotación. Anterior/Siguiente usan los filtros ya consultados. Actualizar rotación repite esa consulta. Los indicadores resumen todo el catálogo activo; la tabla aplica los filtros y muestra hasta 20 productos por página. Si el catálogo cambia y una página queda vacía, puedes retroceder.

## Qué se calcula

Solo se incluyen ventas REGISTRADA, con al menos un detalle y cuyo total coincide exactamente con la suma de sus detalles. Las ventas anuladas se excluyen. Se informa cuántos documentos incompletos o incongruentes se excluyeron del período. Se cuentan todos los métodos de pago, incluido crédito, y también unidades entregadas a precio cero.

Se usa el calendario de Guatemala: desde las 00:00 del primer día hasta antes de las 00:00 del día posterior al último. No se excluyen días sin ventas.

| Indicador | Cálculo |
| --- | --- |
| Promedio diario | Unidades vendidas / días naturales del período |
| Disponible actual | Existencia del producto sin lotes; para productos por lote, unidades en lotes de compras REGISTRADA que no han vencido hoy |
| Cobertura estimada | Disponible actual / promedio diario |
| Meta por ventas | Redondear hacia arriba (promedio diario × días objetivo) |
| Compra sugerida | Máximo entre 0 y (máximo de meta por ventas y mínimo actual + 1) − disponible actual |

Los cálculos de meta y prioridad usan los valores exactos; el redondeo del promedio en pantalla no modifica la cantidad sugerida. Ejemplo: 6 unidades vendidas en 3 días, 4 disponibles hoy, mínimo 5 y objetivo 7 días: promedio 2, cobertura 2 días, meta 14 y compra sugerida 10. Si el objetivo fuera 1 día, se busca superar el mínimo y se sugieren 2 unidades.

## Estados

- **Revisar inventario:** stock total y stock de lotes registrados no concilian, o existe un lote con stock negativo. No se calculan cobertura ni sugerencia.
- **Sin ventas:** no hubo unidades vendidas válidas en ese período. Cobertura y sugerencia quedan sin cálculo; se señala aparte si se alcanzó el mínimo.
- **Reponer:** hubo ventas y faltan unidades para la meta o para superar el mínimo.
- **Cobertura suficiente:** hubo ventas y ya se cubren ambas metas.

La prioridad muestra primero diferencias de inventario, después reposiciones (menor cobertura exacta primero), cobertura suficiente y finalmente productos sin ventas. Los empates se resuelven por nombre e ID para paginar sin ambigüedad. Solo se analiza el catálogo actualmente activo.

## Límites de interpretación

El promedio es una velocidad de venta observada, no el índice contable de rotación de inventario. No usa inventario promedio histórico ni costo de mercancía vendida. Las sugerencias no consideran plazos del proveedor, paquetes mínimos, estacionalidad, promociones ni períodos de agotamiento.

El stock y el mínimo son actuales aunque se consulten ventas antiguas. Un producto sin ventas puede ser nuevo, haber estado agotado o tener registros faltantes. No se etiqueta como invendible ni se interpreta como demanda cero.

Los lotes que vencen hoy siguen disponibles según las reglas de venta existentes. Los lotes ya vencidos se excluyen. Las unidades vigentes pueden vencer antes de completar el objetivo; revisa las alertas de vencimiento del Resumen.

La consulta no modifica compras, stock, caja ni Lista de compras. Las cantidades requieren revisión del administrador antes de planificar o comprar.

## CSV y permisos

**Exportar página CSV** descarga únicamente los productos de la página visible, con las fechas del período, el objetivo y la fecha del stock actual. Cambia de página para descargar las restantes. Los campos sin cálculo quedan vacíos. Importa los códigos de barras como texto para conservar sus ceros iniciales. Los textos se escapan y se neutralizan los que podrían interpretarse como fórmulas.

La función SQL es STABLE, SECURITY INVOKER, con esquema explícito y `search_path` vacío. Respeta RLS, exige un perfil administrador activo y no concede ejecución a anon. No se crean tablas ni permisos adicionales de escritura. Cada consulta y sus indicadores se obtienen en una sola instantánea; actualizar vuelve a leer los datos actuales.

## Verificación

- `npm run build` y `npm run lint`.
- `node --test tests/rotacionValidation.test.cjs`.
- `tests/rotacion_rollback.sql`, completo como postgres: prueba fórmulas, mínimos, redondeo, períodos, límites horarios, lotes vencidos, inventario incoherente, ventas gratuitas, documentos excluidos, catálogo activo, paginación y permisos. Los datos de prueba se revierten.
