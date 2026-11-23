export type ItemLista = {
  id_producto: number;
  nombre: string;
  codigo_barras: string | null;
  activo: boolean;
  existencia: number;
  existencia_minima: number;
  disponible: number;
  vencido: number;
  inconsistente: boolean;
  costo_estimado: number | null;
  version_lista: number;
  en_lista: boolean;
  cantidad_lista: number | null;
  nota_lista: string;
  cantidad_sugerida?: number | null;
  cantidad?: number;
  nota?: string;
  version?: number;
};
export type ListaPayload = {
  p_solicitud_id: string;
  p_producto_id: number;
  p_version_esperada: number;
  p_accion: "GUARDAR" | "QUITAR";
  p_cantidad: number | null;
  p_nota: string;
};
export function prepararPartida(
  item: ItemLista,
  cantidad: string,
  nota: string,
  solicitud: string,
): ListaPayload {
  if (!item.activo) throw new Error("El producto está inactivo.");
  if (
    !/^\d+$/.test(cantidad.trim()) ||
    !Number.isSafeInteger(Number(cantidad)) ||
    Number(cantidad) < 1 ||
    Number(cantidad) > 2147483647
  )
    throw new Error("Indica una cantidad entera mayor que cero.");
  if (nota.trim().length > 500)
    throw new Error("La nota admite hasta 500 caracteres.");
  return {
    p_solicitud_id: solicitud,
    p_producto_id: item.id_producto,
    p_version_esperada: item.version ?? item.version_lista,
    p_accion: "GUARDAR",
    p_cantidad: Number(cantidad),
    p_nota: nota.trim(),
  };
}
export function recuperarPartida(clave: string): {
  pendiente: ListaPayload | null;
  error: string;
} {
  try {
    const s = localStorage.getItem(clave);
    if (!s) return { pendiente: null, error: "" };
    const p = JSON.parse(s) as ListaPayload;
    if (
      !p ||
      typeof p.p_solicitud_id !== "string" ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
        p.p_solicitud_id,
      ) ||
      !Number.isSafeInteger(p.p_producto_id) ||
      p.p_producto_id < 1 ||
      !Number.isSafeInteger(p.p_version_esperada) ||
      p.p_version_esperada < 0 ||
      p.p_version_esperada > 2147483647 ||
      !["GUARDAR", "QUITAR"].includes(p.p_accion) ||
      typeof p.p_nota !== "string" ||
      p.p_nota.length > 500 ||
      (p.p_accion === "QUITAR"
        ? p.p_cantidad !== null
        : !Number.isSafeInteger(p.p_cantidad) ||
          Number(p.p_cantidad) < 1 ||
          Number(p.p_cantidad) > 2147483647)
    )
      throw new Error();
    return { pendiente: p, error: "" };
  } catch {
    return {
      pendiente: null,
      error:
        "No pudimos recuperar la confirmación pendiente. Actualiza y revisa la lista antes de registrar otra operación desde este dispositivo.",
    };
  }
}
function celda(s: string): string {
  const seguro = /^\s*[=+\-@]/.test(s) || /^[\t\r\n]/.test(s) ? "'" + s : s;
  return '"' + seguro.replaceAll('"', '""') + '"';
}
export function csvListaCompras(lista: ItemLista[]): string {
  return (
    "\ufeffproducto,codigo_barras,cantidad,nota,costo_estimado_gtq,subtotal_estimado_gtq\r\n" +
    lista
      .map((i) =>
        [
          celda(i.nombre),
          celda(i.codigo_barras ?? ""),
          String(i.cantidad),
          celda(i.nota ?? ""),
          i.costo_estimado == null ? "" : Number(i.costo_estimado).toFixed(2),
          i.costo_estimado == null
            ? ""
            : (Number(i.cantidad) * Number(i.costo_estimado)).toFixed(2),
        ].join(","),
      )
      .join("\r\n") +
    "\r\n"
  );
}
