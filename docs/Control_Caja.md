# Control diario de caja

Una caja compartida por fecha, en horario de Guatemala. Solo el administrador
puede abrir, registrar movimientos manuales, cerrar, corregir el fondo y reabrir.

## Instalación

Aplica sobre la actualización Efectivo diario que ya funciona:

```bash
git apply --check ~/Descargas/Tienda_Control_Caja.patch
git apply ~/Descargas/Tienda_Control_Caja.patch
npm run build
```

Supabase ya está actualizado. No necesitas ejecutar SQL ni instalar dependencias.
Para instalaciones nuevas, `database/15_control_caja.sql` se ejecuta después de 01–14.

## Al iniciar el día

1. Abre **Caja** y selecciona la fecha.
2. Registra el fondo que había **antes de la primera operación de ese día**.
3. Revisa el monto y confirma. Las ventas, compras y abonos previos de esa fecha
   se incluyen en el cálculo; no uses como fondo el dinero contado a mitad del día.
4. Si hubo un error de digitación, usa **Corregir fondo inicial**, indicando el motivo.

La aplicación mantiene el comportamiento anterior en fechas sin apertura: permite
ventas y pagos, pero Caja no muestra un saldo esperado hasta registrar el fondo.
No copia automáticamente el cierre de ayer como apertura de hoy.

## Durante el día

| Registro | Uso | Efecto en caja |
| --- | --- | --- |
| Gasto de la tienda | Bolsas, transporte u otros gastos pagados en efectivo | Resta |
| Retiro personal | Dinero retirado para uso personal | Resta, separado de gastos |
| Aporte de efectivo | Dinero físico añadido durante el día | Suma |
| Corrección de fondo | Corregir la cifra inicial, con motivo | Sustituye el fondo registrado |

Las compras y los pagos a proveedores ya entran automáticamente desde sus módulos.
No vuelvas a registrarlos como gastos de caja. Las ventas y cobros en efectivo
también se incluyen automáticamente. Tarjeta, crédito y transferencia no se suman.

**Esperado = fondo inicial + entradas automáticas − salidas automáticas + aportes − gastos − retiros.**

El saldo esperado no representa ganancia. Registra movimientos manuales que ya
ocurrieron; el sistema no envía transferencias ni entrega dinero por sí mismo.

## Cierre y arqueo

1. Cuenta el dinero físico y escribe el total en **Efectivo contado**.
2. Si contado y esperado difieren, escribe una observación.
3. Revisa y confirma. El servidor recalcula el esperado en ese momento.
4. Se guarda el conteo, esperado y diferencia: **contado − esperado**.
   Positivo es sobrante; negativo es faltante.
5. Desde ese momento se bloquean las operaciones en efectivo de esa fecha.
   También se bloquean cambios de documentos que afectarían sus cobros o pagos
   en efectivo. Las operaciones sin efectivo pueden continuar.

Si necesitas continuar o corregir, registra **Reapertura** con un motivo. El cierre
anterior permanece en el historial. Puedes operar y hacer otro cierre; ambos
conteos se conservan. El historial muestra los últimos 30 eventos de la fecha.
No se borran ni editan eventos desde la aplicación.

No se permite cerrar si Efectivo detecta documentos o cuentas inconsistentes.
El candado diario del servidor coordina el cierre con las escrituras en efectivo,
para que una operación concurrente termine antes del cierre o sea rechazada.

## Si se interrumpe la conexión

Usa **Reintentar confirmación**: se conserva la misma solicitud por usuario y
navegador y no se vuelve a aplicar una operación ya registrada. No borres los datos
del navegador ni registres otra operación por el mismo movimiento desde otro
dispositivo mientras una confirmación siga pendiente.

## Verificación

```bash
npm run build
npm run lint
node --test tests/cajaValidation.test.cjs
```

`tests/caja_rollback.sql` comprueba apertura, corrección, gastos, retiros, aportes,
diferencias, cierre, bloqueo de efectivo, reapertura, historial y acceso. Ejecuta
el archivo completo como postgres, únicamente si el día todavía no tiene apertura.
Revierte sus fixtures al terminar. Los saltos en secuencias por pruebas son normales.
