# Proveedores y cuentas por pagar

Disponible para ADMINISTRADOR e INVENTARIO, según los permisos existentes.

## Instalar la actualización

Guarda el parche en Descargas y ejecuta desde la raíz del proyecto:

```bash
git apply --check ~/Descargas/Tienda_Proveedores_Pagos.patch
git apply ~/Descargas/Tienda_Proveedores_Pagos.patch
npm run build
npm run lint
```

El módulo de Supabase ya se aplicó en el proyecto de esta tienda. No necesitas
ejecutar SQL de nuevo ni instalar dependencias. Para una instalación nueva,
`database/13_pagos_proveedores.sql` se ejecuta después de 01–12.

## Uso diario

1. Abre **Proveedores y pagos** y crea o edita los datos de un proveedor.
2. En **Compras**, selecciona el proveedor y registra la compra con forma CREDITO.
3. Vuelve a **Proveedores y pagos → Ver cuentas**. Verás sus compras con saldo.
4. En la cuenta correspondiente pulsa **Abonar**, escribe el monto que ya entregaste
   y selecciona la forma de pago.
5. Confirma **Pago entregado** y comprueba el comprobante y el nuevo saldo.
6. **Ver pagos** muestra los últimos 20 pagos de esa cuenta.

Esta pantalla registra pagos realizados; no envía transferencias ni mueve dinero
por sí misma. Un abono reduce la deuda de una compra existente sin registrar otra
compra ni cambiar inventario. El resumen actualiza el importe por pagar.

Las listas muestran 20 registros por página; el saldo total incluye todas las
cuentas de compras registradas del proveedor. Los vencimientos usan el horario
de Guatemala. No se incluyen aún correcciones o anulaciones de abonos.

## Cuando se interrumpe la conexión

Usa **Reintentar confirmación** para verificar la misma operación. La solicitud
queda en el navegador y puede recuperarse después de recargar la página.
No registres otro abono por el mismo dinero desde otro dispositivo mientras
siga pendiente esta confirmación. Los pendientes de clientes y proveedores se
guardan por separado. No borres los datos del navegador mientras haya un pendiente.

## Verificación

```bash
npm run build
npm run lint
node --test tests/proveedorValidation.test.cjs tests/cobroValidation.test.cjs tests/compraValidation.test.cjs
```

`tests/pagos_proveedores_rollback.sql` prueba pago parcial, reintento, sobrepago,
liquidación, vencimiento y permisos en una transacción que revierte los registros.
Ejecuta el archivo completo como postgres en SQL Editor. Los saltos en secuencias
por las pruebas son normales.
