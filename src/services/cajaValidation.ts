import { montoCentavos } from "./cobroValidation";
import { hoyGuatemala } from "./compraValidation";
export const tiposCaja = [
  "APERTURA",
  "AJUSTE_FONDO",
  "GASTO",
  "RETIRO_PERSONAL",
  "APORTE",
  "CIERRE",
  "REAPERTURA",
] as const;
export type TipoCaja = (typeof tiposCaja)[number];
export type CajaPayload = {
  p_solicitud_id: string;
  p_fecha: string;
  p_tipo: TipoCaja;
  p_monto: number | null;
  p_concepto: string;
};
export function prepararCaja(
  fecha: string,
  tipo: TipoCaja,
  monto: string,
  concepto: string,
  solicitud: string,
  hoy = hoyGuatemala(),
): CajaPayload {
  if (
    !/^\d{4}-\d{2}-\d{2}$/.test(fecha) ||
    !Number.isFinite(Date.parse(fecha)) ||
    new Date(fecha).toISOString().slice(0, 10) !== fecha ||
    fecha < "1900-01-01" ||
    fecha > hoy
  )
    throw new Error("Selecciona una fecha válida, hasta hoy.");
  if (!tiposCaja.includes(tipo))
    throw new Error("Selecciona una operación de caja.");
  const detalle = concepto.trim();
  if (detalle.length > 500)
    throw new Error("El concepto admite hasta 500 caracteres.");
  if (
    [
      "GASTO",
      "RETIRO_PERSONAL",
      "APORTE",
      "REAPERTURA",
      "AJUSTE_FONDO",
    ].includes(tipo) &&
    !detalle
  )
    throw new Error("Escribe el concepto o motivo.");
  const centavos = tipo === "REAPERTURA" ? null : montoCentavos(monto);
  if (["GASTO", "RETIRO_PERSONAL", "APORTE"].includes(tipo) && !centavos)
    throw new Error("El monto debe ser mayor que cero.");
  return {
    p_solicitud_id: solicitud,
    p_fecha: fecha,
    p_tipo: tipo,
    p_monto: centavos == null ? null : centavos / 100,
    p_concepto: detalle,
  };
}
export function recuperarCaja(clave: string): {
  pendiente: CajaPayload | null;
  error: string;
} {
  try {
    const texto = localStorage.getItem(clave);
    if (!texto) return { pendiente: null, error: "" };
    const p = JSON.parse(texto) as CajaPayload;
    if (
      !p ||
      typeof p.p_solicitud_id !== "string" ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
        p.p_solicitud_id,
      ) ||
      typeof p.p_fecha !== "string" ||
      typeof p.p_concepto !== "string" ||
      (p.p_tipo === "REAPERTURA"
        ? p.p_monto !== null
        : typeof p.p_monto !== "number" || !Number.isFinite(p.p_monto))
    )
      throw new Error();
    const validado = prepararCaja(
      p.p_fecha,
      p.p_tipo,
      p.p_monto == null ? "" : String(p.p_monto),
      p.p_concepto,
      p.p_solicitud_id,
    );
    return { pendiente: validado, error: "" };
  } catch {
    return {
      pendiente: null,
      error:
        "No pudimos recuperar la operación pendiente de caja. Revisa el historial antes de registrar otra desde este dispositivo.",
    };
  }
}
