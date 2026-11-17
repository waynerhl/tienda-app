import { costoCentavos } from "./compraValidation";
import type { AbonoPayload, Cliente, FormaAbono } from "../types/cobro";

export function montoCentavos(texto: string): number {
  try {
    return costoCentavos(texto);
  } catch {
    throw new Error("Escribe un monto válido con hasta dos decimales.");
  }
}
export function prepararCliente(
  nombre: string,
  telefono: string,
  direccion: string,
  limite: string,
): Omit<Cliente, "id_cliente"> {
  const n = nombre.trim(),
    t = telefono.trim(),
    d = direccion.trim();
  if (!n || n.length > 150)
    throw new Error("Escribe un nombre de hasta 150 caracteres.");
  if (t.length > 20) throw new Error("El teléfono admite hasta 20 caracteres.");
  if (d.length > 250)
    throw new Error("La dirección admite hasta 250 caracteres.");
  return {
    nombre: n,
    telefono: t || null,
    direccion: d || null,
    limite_credito: limite.trim() ? montoCentavos(limite) / 100 : null,
  };
}
export function prepararAbono(
  cuenta: number,
  monto: string,
  saldo: number,
  forma: FormaAbono | undefined,
  solicitud: string,
): AbonoPayload {
  if (!Number.isSafeInteger(cuenta) || cuenta < 1)
    throw new Error("Selecciona una cuenta.");
  if (!forma || forma.nombre === "CREDITO")
    throw new Error("Selecciona una forma de pago distinta de crédito.");
  const centavos = montoCentavos(monto);
  if (!centavos) throw new Error("El abono debe ser mayor que cero.");
  if (centavos > Math.round(Number(saldo) * 100))
    throw new Error(
      "El abono supera el saldo mostrado. Actualiza si hubo otros pagos.",
    );
  return {
    p_solicitud_id: solicitud,
    p_cuenta_id: cuenta,
    p_forma_pago_id: forma.id_forma_pago,
    p_monto: centavos / 100,
  };
}
export function recuperarAbono(clave: string): {
  pendiente: AbonoPayload | null;
  error: string;
} {
  try {
    const texto = localStorage.getItem(clave);
    if (!texto) return { pendiente: null, error: "" };
    const p = JSON.parse(texto) as AbonoPayload;
    if (
      !p ||
      typeof p.p_solicitud_id !== "string" ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
        p.p_solicitud_id,
      ) ||
      !Number.isSafeInteger(p.p_cuenta_id) ||
      p.p_cuenta_id < 1 ||
      !Number.isSafeInteger(p.p_forma_pago_id) ||
      p.p_forma_pago_id < 1 ||
      typeof p.p_monto !== "number" ||
      !Number.isFinite(p.p_monto) ||
      p.p_monto <= 0 ||
      p.p_monto > 9999999999.99 ||
      Math.abs(p.p_monto * 100 - Math.round(p.p_monto * 100)) > 0.001
    )
      throw new Error();
    return { pendiente: p, error: "" };
  } catch {
    return {
      pendiente: null,
      error:
        "No se pudo recuperar el abono pendiente. Revisa el historial antes de registrar otro desde este dispositivo.",
    };
  }
}
