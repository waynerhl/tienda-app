import type {
  CompraPayload,
  FormaPago,
  LineaCompraForm,
} from "../types/compra";

const MAX_CENTAVOS = 999999999999;
export function hoyGuatemala(): string {
  return new Intl.DateTimeFormat("sv-SE", {
    timeZone: "America/Guatemala",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date());
}
export function costoCentavos(value: string): number {
  const text = value.trim().replace(",", ".");
  if (!/^\d+(\.\d{1,2})?$/.test(text))
    throw new Error(
      "El costo debe ser positivo o cero y tener hasta dos decimales.",
    );
  const [whole, fraction = ""] = text.split(".");
  const cents = Number(whole) * 100 + Number(fraction.padEnd(2, "0"));
  if (!Number.isSafeInteger(cents) || cents > MAX_CENTAVOS)
    throw new Error("El costo supera el máximo permitido.");
  return cents;
}
export function cantidadEntera(value: string): number {
  if (!/^\d+$/.test(value.trim()))
    throw new Error(
      "Las cantidades deben ser números enteros mayores que cero.",
    );
  const n = Number(value);
  if (!Number.isSafeInteger(n) || n < 1 || n > 2147483647)
    throw new Error("Las cantidades deben estar entre 1 y 2147483647.");
  return n;
}
function validarFecha(value: string, today: string) {
  if (
    !/^\d{4}-\d{2}-\d{2}$/.test(value) ||
    !Number.isFinite(Date.parse(value)) ||
    new Date(value).toISOString().slice(0, 10) !== value ||
    value < today
  )
    throw new Error(
      "Revisa las fechas: deben ser válidas y no anteriores a hoy.",
    );
}
export function totalCompraCentavos(lines: LineaCompraForm[]): number {
  let total = 0;
  for (const line of lines) {
    const subtotal =
      cantidadEntera(line.cantidad) * costoCentavos(line.costo_unitario);
    if (
      !Number.isSafeInteger(subtotal) ||
      subtotal > MAX_CENTAVOS ||
      total + subtotal > MAX_CENTAVOS
    )
      throw new Error("El total de la compra supera el máximo permitido.");
    total += subtotal;
  }
  return total;
}
export function prepararCompra(
  proveedor: string,
  pago: FormaPago | undefined,
  documento: string,
  fecha: string,
  lines: LineaCompraForm[],
  today = hoyGuatemala(),
): CompraPayload {
  const proveedorId = Number(proveedor);
  if (!Number.isSafeInteger(proveedorId) || proveedorId < 1)
    throw new Error("Selecciona un proveedor.");
  if (!pago) throw new Error("Selecciona una forma de pago.");
  const reference = documento.trim();
  if (!reference || reference.length > 100)
    throw new Error(
      "Escribe un documento o referencia de hasta 100 caracteres.",
    );
  if (!lines.length)
    throw new Error("Agrega al menos un producto a la compra.");
  if (
    new Set(lines.map((line) => line.producto.id_producto)).size !==
    lines.length
  )
    throw new Error("Cada producto debe aparecer una sola vez.");
  const credit = pago.nombre === "CREDITO";
  if (credit && fecha) validarFecha(fecha, today);
  const total = totalCompraCentavos(lines);
  if (credit && total === 0)
    throw new Error("Una compra a crédito debe tener un total mayor que cero.");
  return {
    p_proveedor_id: proveedorId,
    p_forma_pago_id: pago.id_forma_pago,
    p_numero_documento: reference,
    p_fecha_limite: credit && fecha ? fecha : null,
    p_items: lines.map((line) => {
      if (!line.producto.activo)
        throw new Error("Hay un producto inactivo. Retíralo de la compra.");
      const quantity = cantidadEntera(line.cantidad);
      const item: CompraPayload["p_items"][number] = {
        producto_id: line.producto.id_producto,
        cantidad: quantity,
        costo_unitario: costoCentavos(line.costo_unitario) / 100,
      };
      if (line.producto.controla_lotes) {
        if (!line.lotes.length)
          throw new Error(`Agrega los lotes de ${line.producto.nombre}.`);
        let sum = 0;
        item.lotes = line.lotes.map((lote) => {
          const cantidad = cantidadEntera(lote.cantidad);
          sum += cantidad;
          if (lote.numero_lote.trim().length > 150)
            throw new Error("El número de lote admite hasta 150 caracteres.");
          if (lote.fecha_vencimiento)
            validarFecha(lote.fecha_vencimiento, today);
          return {
            cantidad,
            numero_lote: lote.numero_lote.trim() || null,
            fecha_vencimiento: lote.fecha_vencimiento || null,
          };
        });
        if (sum !== quantity)
          throw new Error(
            `Los lotes de ${line.producto.nombre} suman ${sum} unidades; deben sumar ${quantity}.`,
          );
      }
      return item;
    }),
  };
}
