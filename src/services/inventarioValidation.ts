import { hoyGuatemala } from "./compraValidation";
export type ProductoInv = {
  id_producto: number;
  nombre: string;
  codigo_barras: string | null;
  existencia: number;
  controla_lotes: boolean;
  activo: boolean;
};
export type LoteInv = {
  origen?: "LOTE_COMPRA" | "LOTE_INICIAL";
  id_lote: number;
  numero_lote: string | null;
  fecha_ingreso: string;
  fecha_vencimiento: string | null;
  existencia: number;
  vencido: boolean;
};
export const tiposAjuste = [
  "CONTEO",
  "PERDIDA",
  "VENCIMIENTO",
  "AJUSTE_POSITIVO",
  "AJUSTE_NEGATIVO",
] as const;
export type TipoAjuste = (typeof tiposAjuste)[number];
export type AjustePayload = {
  p_solicitud_id: string;
  p_producto_id: number;
  p_lote_id: number | null;
  p_tipo: TipoAjuste;
  p_cantidad: number;
  p_existencia_esperada: number;
  p_motivo: string;
};
export type AjusteResultado = {
  id_ajuste: number;
  producto_id: number;
  lote_id: number | null;
  tipo: TipoAjuste;
  existencia_anterior: number;
  existencia_nueva: number;
  variacion: number;
  producto_anterior: number;
  producto_nuevo: number;
  movimiento_id: number | null;
  repetida: boolean;
};
export const nombresAjuste: Record<TipoAjuste, string> = {
  CONTEO: "Conteo físico",
  PERDIDA: "Pérdida o daño",
  VENCIMIENTO: "Retirar producto vencido",
  AJUSTE_POSITIVO: "Corrección de entrada",
  AJUSTE_NEGATIVO: "Corrección de salida",
};
function entero(texto: string): number {
  if (!/^\d+$/.test(texto.trim()))
    throw new Error("La cantidad debe ser un número entero, sin decimales.");
  const n = Number(texto);
  if (!Number.isSafeInteger(n) || n < 0 || n > 2147483647)
    throw new Error("La cantidad está fuera del rango permitido.");
  return n;
}
export function prepararAjuste(
  producto: ProductoInv,
  lote: LoteInv | null,
  tipo: TipoAjuste,
  cantidad: string,
  motivo: string,
  solicitud: string,
  hoy = hoyGuatemala(),
): AjustePayload {
  if (!tiposAjuste.includes(tipo))
    throw new Error("Selecciona el tipo de ajuste.");
  if (producto.controla_lotes && !lote) throw new Error("Selecciona un lote.");
  if (!producto.controla_lotes && lote)
    throw new Error("Este producto no utiliza lotes.");
  const n = entero(cantidad);
  const antes = lote ? lote.existencia : producto.existencia;
  const detalle = motivo.trim();
  if (!detalle || detalle.length > 500)
    throw new Error("Escribe un motivo de hasta 500 caracteres.");
  if (tipo !== "CONTEO" && n === 0)
    throw new Error("La cantidad del movimiento debe ser mayor que cero.");
  if (
    tipo === "VENCIMIENTO" &&
    (!lote?.fecha_vencimiento || lote.fecha_vencimiento >= hoy)
  )
    throw new Error(
      "Solo se retiran por vencimiento lotes con fecha anterior a hoy.",
    );
  const delta =
    tipo === "CONTEO" ? n - antes : tipo === "AJUSTE_POSITIVO" ? n : -n;
  if (
    antes + delta < 0 ||
    producto.existencia + delta < 0 ||
    producto.existencia + delta > 2147483647
  )
    throw new Error(
      "La cantidad supera la existencia disponible o el máximo permitido.",
    );
  return {
    p_solicitud_id: solicitud,
    p_producto_id: producto.id_producto,
    p_lote_id: lote?.id_lote ?? null,
    p_tipo: tipo,
    p_cantidad: n,
    p_existencia_esperada: antes,
    p_motivo: detalle,
  };
}
export function recuperarAjuste(clave: string): {
  pendiente: AjustePayload | null;
  error: string;
} {
  try {
    const texto = localStorage.getItem(clave);
    if (!texto) return { pendiente: null, error: "" };
    const p = JSON.parse(texto) as AjustePayload;
    if (
      !p ||
      typeof p.p_solicitud_id !== "string" ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
        p.p_solicitud_id,
      ) ||
      !Number.isSafeInteger(p.p_producto_id) ||
      p.p_producto_id < 1 ||
      (p.p_lote_id !== null &&
        (!Number.isSafeInteger(p.p_lote_id) || p.p_lote_id < 1)) ||
      !tiposAjuste.includes(p.p_tipo) ||
      !Number.isSafeInteger(p.p_cantidad) ||
      p.p_cantidad < 0 ||
      p.p_cantidad > 2147483647 ||
      (p.p_tipo !== "CONTEO" && p.p_cantidad === 0) ||
      !Number.isSafeInteger(p.p_existencia_esperada) ||
      p.p_existencia_esperada < 0 ||
      p.p_existencia_esperada > 2147483647 ||
      typeof p.p_motivo !== "string" ||
      !p.p_motivo.trim() ||
      p.p_motivo.length > 500
    )
      throw new Error();
    return { pendiente: p, error: "" };
  } catch {
    return {
      pendiente: null,
      error:
        "No pudimos recuperar el ajuste pendiente. Revisa el historial antes de registrar otro desde este dispositivo.",
    };
  }
}
