import { supabase } from "../lib/supabase";
import type { CompraGuardada, CompraPayload } from "../types/compra";

export async function registrarCompra(
  payload: CompraPayload,
): Promise<CompraGuardada> {
  if (!supabase) throw new Error("La conexión no está configurada.");
  const { data, error } = await supabase.rpc("registrar_compra_fondo", { ...payload, p_fondo: payload.p_fondo ?? "CAJA" });
  if (error) {
    if (error.code === "23505")
      throw new Error(
        "Ya existe una compra con esta referencia para el proveedor. Revisa el historial antes de continuar.",
      );
    if (error.code === "42501")
      throw new Error("Tu cuenta no tiene permiso para registrar compras.");
    if (error.code === "22023") throw new Error(error.message);
    if (error.code === "22003")
      throw new Error(
        "La cantidad, costo o total supera los límites permitidos.",
      );
    if (error.code === "23503")
      throw new Error(
        "Un proveedor o producto ya no está disponible. Actualiza los datos.",
      );
    if (error.code === "23514")
      throw new Error(
        "La compra no cumple las reglas de inventario. Revisa cantidades y fechas.",
      );
    throw new Error(
      "No pudimos confirmar el registro. Revisa el historial y conserva la misma referencia antes de reintentar.",
    );
  }
  if (
    !data ||
    !Number.isInteger(data.id_compra) ||
    !Number.isFinite(Number(data.total))
  )
    throw new Error(
      "La respuesta no confirmó la compra. Revisa el historial antes de reintentar.",
    );
  return data as CompraGuardada;
}
