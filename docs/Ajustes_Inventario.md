# Ajustes de inventario

Disponible para ADMINISTRADOR e INVENTARIO. Permite consultar productos activos e
inactivos, sus lotes, los últimos 20 ajustes manuales y los últimos 30 movimientos.

## Instalación

Sobre la actualización Control de caja ya instalada, guarda el parche en Descargas
y ejecuta desde la raíz del proyecto:

```bash
git apply --check ~/Descargas/Tienda_Ajustes_Inventario.patch
git apply ~/Descargas/Tienda_Ajustes_Inventario.patch
npm run build
```

Supabase ya está actualizado. No necesitas ejecutar SQL adicional ni instalar
dependencias. En instalaciones nuevas aplica `database/16_ajustes_inventario.sql`
después de los scripts 01–15.

## Cómo usarlo

1. En **Inventario**, busca el producto por nombre o código de barras exacto.
2. Pulsa **Ver inventario**. Si usa lotes, selecciona el lote físico correspondiente.
   Hay páginas de 20 lotes e incluye los agotados para poder registrar correcciones.
3. Selecciona la operación, indica la cantidad y escribe el motivo.
4. Revisa las existencias antes/después y confirma.
5. Comprueba el comprobante y el historial. El catálogo y resumen se actualizan.

| Operación | Cantidad que debes escribir | Efecto |
| --- | --- | --- |
| Conteo físico | Total de unidades que contaste; puede ser cero | Ajusta por la diferencia |
| Pérdida o daño | Unidades perdidas o dañadas | Resta |
| Retirar producto vencido | Unidades retiradas físicamente del lote vencido | Resta |
| Corrección de entrada | Unidades que faltaba registrar | Suma |
| Corrección de salida | Unidades que faltaba descontar | Resta |

Ejemplo: si figuran 10 unidades y cuentas 8, escribe **8** en Conteo físico.
El sistema registra una salida de 2 unidades. Si coinciden las existencias,
guarda el conteo sin crear un movimiento de stock.

En productos con lotes, el conteo se hace por lote; no sobrescribe todo el producto.
Vencimiento solo admite fechas anteriores a hoy en horario de Guatemala: un lote
que vence hoy aún no se considera vencido. No se descuentan unidades por el mero
paso del tiempo: registra la baja cuando retires físicamente el producto.

Las compras y ventas se registran en sus módulos. Este ajuste no cambia el último
costo ni crea compras, ventas, deudas o movimientos de caja. Una entrada por
corrección no sustituye el registro de una compra ni crea lotes nuevos.

## Existencias cambiadas y reintentos

Si hubo una venta u otra operación después de consultar, el servidor rechaza el
ajuste. Actualiza el inventario, revisa el conteo y prepara una confirmación nueva.
Así un conteo antiguo no sobrescribe ventas recientes.

Si se interrumpe la conexión, usa **Reintentar confirmación**. Se conserva la
misma solicitud y no se aplica dos veces. No borres los datos del navegador ni
registres otro ajuste por el mismo hecho desde otro dispositivo mientras haya
una confirmación pendiente.

Los ajustes no se borran ni editan desde la aplicación. Para corregir un error,
registra otro ajuste con un motivo que explique la corrección. Si la existencia
de un producto no coincide con la suma de sus lotes, se bloquean los ajustes de
ese producto hasta revisar la inconsistencia.

## Verificación

```bash
npm run build
npm run lint
node --test tests/inventarioValidation.test.cjs
```

`tests/inventario_rollback.sql` prueba conteos, reintentos, stock desactualizado,
cantidades insuficientes, lotes, vencimientos, costos, paginación y acceso.
Ejecuta el archivo completo como postgres en SQL Editor. Los fixtures y ajustes
se revierten al terminar; los saltos de secuencia son normales.
