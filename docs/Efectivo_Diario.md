# Efectivo diario

La pestaña **Efectivo** está disponible para ADMINISTRADOR. Permite consultar por
fecha las entradas y salidas registradas en EFECTIVO, con horario de Guatemala.

| Origen | Efecto | Fecha usada |
| --- | --- | --- |
| Venta cobrada en efectivo | Entrada | Fecha de la venta |
| Abono de cliente en efectivo | Entrada | Fecha del abono |
| Compra pagada en efectivo | Salida | Fecha de la compra |
| Abono a proveedor en efectivo | Salida | Fecha del abono |

Crédito, tarjeta y transferencia no se suman como efectivo. Un abono no vuelve a
sumar el importe completo de la compra o venta. Cada día comprende desde las
00:00 inclusive hasta las 00:00 del día siguiente, en America/Guatemala.

La variación es entradas menos salidas registradas. No es ganancia ni saldo
disponible en caja. El módulo Caja incorpora fondo inicial, gastos, retiros,
aportes y arqueo.
Esta vista no crea pagos, modifica inventario ni cierra jornadas.

Los totales incluyen todas las páginas; cada página muestra hasta 20 movimientos.
Los documentos sin detalles o con totales inconsistentes, y los abonos asociados
a cuentas inconsistentes, se advierten y se excluyen del informe. Una operación
anulada no entra en los totales. No se borran registros al consultar el informe.

## Instalación

El parche se aplica sobre la actualización **Proveedores y pagos** ya instalada.
Guárdalo en Descargas y, desde la raíz del proyecto, ejecuta:

```bash
git apply --check ~/Descargas/Tienda_Efectivo_Diario.patch
git apply ~/Descargas/Tienda_Efectivo_Diario.patch
npm run build
```

Supabase ya fue actualizado. No necesitas ejecutar SQL adicional ni instalar
dependencias. En una instalación nueva, `database/14_flujo_efectivo.sql` se aplica
después de los scripts 01–13. La consulta respeta los permisos de las tablas y
comprueba el rol de administrador en el servidor.

## Verificación

`npm run build` y `npm run lint` comprueban el frontend.
`tests/efectivo_rollback.sql` prueba efectivo frente a otras formas de pago,
abonos de operaciones de otros días, límites horarios, paginación, documentos
inconsistentes y acceso. Ejecuta el archivo completo como postgres en SQL Editor.
Sus registros de prueba se revierten al terminar; las secuencias pueden dejar
saltos normales.
