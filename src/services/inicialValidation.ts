import { cantidadEntera, costoCentavos, hoyGuatemala } from "./compraValidation";
export type PartidaInicialForm = { numero_lote: string; fecha_vencimiento: string; cantidad: string; costo: string };
export type PartidaInicial = { numero_lote: string | null; fecha_vencimiento: string | null; cantidad: number; costo_unitario: string };
export type InicialPayload = { p_solicitud_id: string; p_producto_id: number; p_partidas: PartidaInicial[]; p_motivo: string };
export type InicialResultado = { id_inicial: number; producto_id: number; cantidad: number; valor_inicial: number; partidas: (PartidaInicial & { lote_id: number | null })[]; repetida: boolean };
export type ProductoInicial = { id_producto: number; nombre: string; codigo_barras: string | null; existencia: number; controla_lotes: boolean; activo: boolean; disponible_inicial: boolean; inicial: InicialResultado | null };
export const nuevaPartida = (): PartidaInicialForm => ({ numero_lote: "", fecha_vencimiento: "", cantidad: "", costo: "" });
export function prepararInicial(producto: ProductoInicial, filas: PartidaInicialForm[], motivo: string, uuid: string, hoy = hoyGuatemala()): InicialPayload {
  if (!producto.disponible_inicial || !producto.activo || producto.existencia !== 0) throw new Error("Este producto ya tiene existencias o historial, o está inactivo.");
  if (!filas.length || filas.length > 100 || (!producto.controla_lotes && filas.length !== 1)) throw new Error("Revisa la cantidad de partidas: hasta 100 lotes o una partida sin lotes.");
  const detalle = motivo.trim(); if (!detalle || detalle.length > 500) throw new Error("Escribe un motivo de hasta 500 caracteres.");
  let total = 0; let valor = 0; const vistos = new Set<string>();
  const partidas = filas.map(f => {
    const cantidad = cantidadEntera(f.cantidad); const centavos = costoCentavos(f.costo);
    total += cantidad; valor += cantidad * centavos;
    if (total > 2147483647 || !Number.isSafeInteger(valor)) throw new Error("El total de unidades o el valor inicial supera el máximo permitido.");
    const numero = producto.controla_lotes ? f.numero_lote.trim() : null;
    const fecha = producto.controla_lotes ? f.fecha_vencimiento || null : null;
    if (producto.controla_lotes) {
      if (!numero || numero.length > 50) throw new Error("Identifica cada lote con 1 a 50 caracteres.");
      if (fecha && (!/^\d{4}-\d{2}-\d{2}$/.test(fecha) || !Number.isFinite(Date.parse(fecha)) || new Date(fecha).toISOString().slice(0,10) !== fecha || fecha < hoy)) throw new Error("Revisa los vencimientos. Aparta las unidades ya vencidas.");
      const clave = JSON.stringify([numero, fecha]); if (vistos.has(clave)) throw new Error("Reúne las cantidades del lote y vencimiento repetidos en una sola partida."); vistos.add(clave);
    }
    return { numero_lote: numero, fecha_vencimiento: fecha, cantidad, costo_unitario: (centavos / 100).toFixed(2) };
  });
  return { p_solicitud_id: uuid, p_producto_id: producto.id_producto, p_partidas: partidas, p_motivo: detalle };
}
export function recuperarInicial(clave: string): { pendiente: InicialPayload | null; error: string } {
  try {
    const raw = localStorage.getItem(clave); if (!raw) return { pendiente: null, error: "" };
    const p = JSON.parse(raw) as InicialPayload;
    if (!p || !/^[\da-f]{8}(-[\da-f]{4}){3}-[\da-f]{12}$/i.test(p.p_solicitud_id) || !Number.isSafeInteger(p.p_producto_id) || p.p_producto_id < 1 || !Array.isArray(p.p_partidas) || !p.p_partidas.length || p.p_partidas.length > 100 || typeof p.p_motivo !== "string" || !p.p_motivo.trim() || p.p_motivo.length > 500) throw new Error();
    let total = 0;
    for (const f of p.p_partidas) {
      if (!f || !Number.isInteger(f.cantidad) || f.cantidad < 1 || f.cantidad > 2147483647 || typeof f.costo_unitario !== "string" || !/^\d{1,10}\.\d{2}$/.test(f.costo_unitario) || Number(f.costo_unitario) > 9999999999.99 || (f.numero_lote !== null && (typeof f.numero_lote !== "string" || !f.numero_lote.trim() || f.numero_lote.length > 50)) || (f.fecha_vencimiento !== null && (typeof f.fecha_vencimiento !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(f.fecha_vencimiento)))) throw new Error();
      total += f.cantidad;
    }
    if (total > 2147483647) throw new Error();
    return { pendiente: p, error: "" };
  } catch { return { pendiente: null, error: "No pudimos recuperar la confirmación inicial pendiente. Conserva los datos del navegador y revisa el historial antes de volver a cargar." }; }
}
