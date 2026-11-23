# Caja de atención y Reserva de la tienda

Requiere los parches anteriores, hasta Inventario inicial, y la migración `database/22_caja_reserva.sql` aplicada. No modifica inventario inicial ni registra aperturas, saldos iniciales o dinero real por sí sola.

## Preparación antes de abrir la primera jornada

1. Cuenta el dinero físico que ya tienes apartado. En **Reserva**, registra ese importe como saldo inicial e indica el concepto. No incluyas los Q400–Q500 que dejarás para atender y dar cambio.
2. Si todavía no tienes dinero apartado, inicia Reserva con Q0.00.
3. Abre **Caja** con el efectivo físico que efectivamente dejas para atender. El fondo de apertura no se toma automáticamente de Reserva: es el conteo del efectivo que ya está en el cajón.
4. Después de abrir, si mueves dinero entre el cajón y lo guardado, registra el traslado correspondiente en Reserva. No vuelvas a registrar como apertura o aporte el dinero que acabas de trasladar.

Si en otra jornada necesitas dinero de Reserva para dar cambio, abre Caja con lo que ya tiene el cajón (puede ser cero) y después registra el traslado desde Reserva. No incluyas ese mismo traslado también en el fondo de apertura.

El saldo inicial de Reserva se admite una sola vez. Un aporte posterior representa dinero externo; el dinero de Caja se registra como traslado. Ninguno de esos conceptos representa una venta ni una utilidad.

## Operaciones

| Hecho real | Registro |
| --- | --- |
| Apartar excedente del cajón | Reserva → Apartar dinero de Caja a Reserva |
| Regresar dinero para cambio | Reserva → Regresar dinero de Reserva a Caja |
| Comprar mercadería con lo apartado | Compras → Efectivo → Pagar efectivo desde Reserva |
| Pagar una deuda al proveedor con lo apartado | Proveedores y pagos → Efectivo → Pagar efectivo desde Reserva |
| Pagar luz o internet del negocio desde lo apartado | Reserva → Gasto de la tienda desde Reserva |
| Sacar para uso personal o gastos de casa | Reserva → Retiro personal desde Reserva |
| Agregar dinero propio externo a lo apartado | Reserva → Aporte externo a Reserva |
| Gastos o retiros que salen del cajón | Caja → Gasto de la tienda / Retiro personal |

Para un recibo de uso compartido, registra como gasto del negocio únicamente la parte que le corresponde. La parte personal es retiro personal. La app distingue las operaciones; no decide automáticamente la proporción.

No registres además una salida manual por una compra o abono ya pagados desde Reserva: ambos módulos descuentan automáticamente su pago una sola vez. Tarjeta, transferencia y crédito no usan el fondo de efectivo. Una compra a crédito no reduce Reserva hasta que se registra un abono efectivamente pagado en efectivo desde ese fondo.

## Ejemplo

Con Q1,300 en Caja y Reserva inicialmente en cero, apartar Q800 deja Caja en Q500 y Reserva en Q800: el total sigue siendo Q1,300. Comprar Q450 desde Reserva deja Q350; retirar Q100 para ti deja Q250; pagar Q150 de internet de la tienda deja Q100. Caja permanece en Q500. El saldo de Reserva no equivale a ganancia.

La app no aparta automáticamente el excedente ni obliga a un fondo fijo: tú decides si dejas Q400, Q500 u otro importe y registras los traslados reales.

## Saldos, historial y cierre

Reserva conserva el saldo entre jornadas. No se reinicia cuando cierras Caja ni se vuelve a registrar al día siguiente. Su historial acumulado tiene páginas de 20 movimientos, con comprobantes, procedencia, importe y saldo posterior.

La pantalla muestra el saldo esperado de Caja de hoy cuando está abierta; si ya está cerrada muestra su último conteo físico. Sin apertura de hoy, el total de ambos fondos queda pendiente, pues no se supone que el cajón esté vacío.

El saldo esperado de Caja suma fondo inicial, ventas y cobros en efectivo, aportes y traslados recibidos; resta compras y pagos desde CAJA, gastos y retiros del cajón y traslados enviados. El cierre conserva los totales de traslados en su comprobante. Efectivo del día muestra solamente operaciones automáticas desde/hacia CAJA y remite a Reserva para sus pagos.

Los traslados requieren la Caja de hoy abierta, sin inconsistencias y saldo suficiente en el fondo de origen. Los pagos/gastos/retiros desde Reserva requieren saldo suficiente y pueden registrarse aun si Caja está cerrada, porque no alteran ese cajón. Los movimientos nuevos de Reserva usan la fecha actual de Guatemala; no permiten trasladar retroactivamente dinero de un cierre antiguo. Los registros anteriores conservan CAJA como origen y no se reclasifican automáticamente.

Los pagos históricos de Reserva no se sobrescriben ni se eliminan. Este módulo aún no incluye una operación de reversión de esos pagos; revisa fondo, monto y concepto antes de confirmar. Las reglas anteriores de Caja que advierten un saldo esperado negativo para operaciones ordinarias se conservan; el control estricto de saldo se aplica a Reserva y a los traslados.

## Confirmaciones y seguridad

Los movimientos manuales de Reserva se revisan antes de enviar. El navegador conserva la referencia por usuario. Si la respuesta es incierta, **Reintentar confirmación** usa la misma referencia: devuelve el comprobante original si ya fue registrado, sin mover dinero otra vez. No borres el almacenamiento del navegador si hay una confirmación pendiente.

Los pagos a proveedores conservan monto, cuenta, forma de pago, UUID y fondo en su pendiente. Un reintento que cambie el fondo es rechazado. Las compras mantienen su referencia única por proveedor: si la respuesta fue incierta, revisa el historial y conserva la referencia.

Solo el administrador opera y consulta Reserva. Los usuarios de Inventario conservan compras y pagos desde Caja; la opción Reserva exige administrador también en la base. No hay escritura directa del saldo o libro desde la app. Las funciones privadas validan el origen, actualizan saldo y libro en la misma transacción y serializan las operaciones que comparten efectivo y cierres. Un pago sin fondos revierte también cualquier compra, deuda o cambio de inventario que lo acompañe.

## Verificación

- Compilación y lint.
- Validación de montos, saldo inicial cero, recuperación de pendientes y origen del pago.
- Prueba SQL de jornada en `tests/reserva_rollback.sql`: traslados, compras, abonos, reintentos, pago sin fondos, cierre, pagos desde Reserva después del cierre y conciliación del libro. Solo se ejecuta en una base con Reserva sin inicializar y Caja de hoy aún no abierta; todos los datos se revierten.
- Pruebas anteriores de Caja, Efectivo, compras, abonos de clientes/proveedores, costos e inventario inicial.
- Pruebas de interfaz con doble clic, pérdida de respuesta, recarga y reintento exacto, y conservación del fondo elegido al pagar a un proveedor.
