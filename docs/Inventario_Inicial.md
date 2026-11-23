# Inventario inicial con y sin lotes

Esta opción incorpora mercadería que ya estaba en la tienda al comenzar a usar la app. No registra compras, pagos, cuentas por pagar ni caja. Tampoco representa una venta ni una ganancia.

## Antes de cargar

1. Instala los parches previos, hasta Rotación de productos, y después este parche.
2. En Productos crea el artículo con nombre, código de barras completo, precio de venta y mínimo. Activa Control por lotes si aplica.
3. El producto debe estar activo, con existencia cero y sin compras, ventas, movimientos ni una carga inicial previa. No hagas un ajuste para darle existencias antes de usar esta opción.
4. Cuenta las unidades aptas para vender. Aparta las que ya están vencidas.
5. Separa los grupos por número de lote y vencimiento y verifica el costo **por unidad**.

Un producto que ya tiene historial se trabaja mediante Compras o ajustes de Inventario según el hecho real. No borres movimientos para repetir una carga inicial. La incorporación de existencias preexistentes sin lotes consistentes requiere una revisión específica; este módulo no las reclasifica automáticamente.

## Ejemplo y pasos

Entra como administrador a **Inventario inicial**, busca el producto y pulsa **Preparar inicial**.

| Referencia del lote | Cantidad | Costo por unidad | Vencimiento |
| --- | --- | --- | --- |
| INICIAL-01 | 5 | Q2.00 | La fecha real del empaque |
| INICIAL-02 | 7 | Q3.00 | La fecha real del segundo grupo |

Pulsa Añadir otro lote para registrar ambos en una sola operación. Si el empaque tiene un lote de fabricación, utiliza ese número. Si no lo tiene, usa una referencia interna como INICIAL-01. No inventes una fecha de vencimiento. Déjala vacía solo cuando no aplique.

Revisa el motivo, pulsa **Revisar inventario inicial**, comprueba todos los datos y finalmente **Confirmar inventario inicial**. En este ejemplo se registran 12 unidades con un valor de Q31.00. No sale dinero de caja. El producto sin control por lotes usa una única partida con cantidad y costo unitario.

La fecha de ingreso es el día actual de Guatemala, cuando registras el saldo inicial; no pretende reconstruir la fecha de la compra antigua. Se admiten vencimientos de hoy en adelante, según la regla de venta existente. La carga debe incluir **todos** los lotes del producto: no se admite otra carga inicial después.

## Comprobación posterior

- Productos muestra la nueva existencia total.
- Inventario permite consultar los lotes, identificados como Inventario inicial, y corregir sus cantidades mediante ajustes auditados.
- Ventas consume primero el lote con vencimiento más cercano (FEFO), junto con los lotes de compras posteriores.
- Resumen incluye las alertas de vencimiento.
- Lista de compras y Rotación reconocen el disponible de los lotes iniciales.
- El costo de cada lote se conserva en los movimientos de venta y participa en Costos y utilidad. Una compra posterior no reescribe esos costos históricos.

La referencia `ultimo_costo` del producto se inicializa con el promedio ponderado de las partidas, redondeado a dos decimales, para presupuestos y referencias posteriores. Esto no sustituye el costo propio de cada lote vendido. Sin lotes se usa el costo unitario declarado como último costo conocido. No se interpreta un costo vacío como cero; Q0.00 debe ser un costo conocido y explícito.

## Reintentos y límites

Antes de enviar se conserva una referencia UUID por usuario en el navegador. Si la respuesta se pierde, pulsa **Reintentar confirmación** con la misma referencia. Una carga ya registrada devuelve el comprobante original y no vuelve a sumar existencias. No borres el almacenamiento del navegador mientras haya una confirmación pendiente.

La base bloquea el producto durante la carga, vuelve a verificar que no tenga historial y permite solo una entrada inicial por producto. Cada confirmación admite 1–100 partidas, cantidades enteras positivas y costos de hasta dos decimales. Un lote y vencimiento repetidos deben reunirse en una misma partida. El costo, origen, número y vencimiento del lote inicial quedan como historial; revisa esos datos antes de confirmar. Las cantidades sí pueden corregirse con ajustes posteriores.

## Implementación y verificación

`database/21_inventario_inicial.sql` crea un registro propio para el saldo inicial y permite que el lote tenga como origen una compra **o** una entrada inicial, nunca ambos. La vista `lotes_contexto` usa `security_invoker=true`; no evita RLS. Las funciones de ventas, validación de movimientos, ajustes, inventario, alertas, lista de compras y rotación reconocen ambos orígenes. Se amplía el catálogo de costo de venta con LOTE_INICIAL.

Solo el administrador puede preparar y confirmar la carga. El registro de auditoría no admite escritura directa desde la app; las escrituras pasan por una función privada con autorización y wrapper público invoker. Los roles de Inventario mantienen sus consultas y ajustes de los lotes ya creados.

Verificaciones: compilación y lint; pruebas de validación y recuperación del navegador; `tests/inicial_rollback.sql` con creación de varios lotes, FEFO, mezcla con compras posteriores, costo histórico, ajustes, reportes, reintentos, rechazo de entradas inválidas y comprobación de ausencia de compras/deudas/caja durante la carga. Los datos de prueba se revierten. También se ejecutan las pruebas existentes de compras, inventario, costos, lista y rotación.
