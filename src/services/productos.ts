import { supabase } from "../lib/supabase";
import type { Producto, ProductoFormValues } from "../types/producto";
import { mensajeErrorProducto, validarProducto } from "./productoValidation";

export const productoColumns =
  "id_producto,categoria_id,nombre,codigo_barras,precio_venta,existencia,existencia_minima,activo,controla_lotes";

export async function guardarProducto(
  values: ProductoFormValues,
  id?: number,
): Promise<Producto> {
  if (!supabase)
    throw new Error("La conexión con Supabase no está configurada.");
  const payload = validarProducto(values);
  // Solo se envían campos editables. Existencia y costo se administran en inventario.
  const { controla_lotes, ...editable } = payload;
  const query =
    id === undefined
      ? supabase.from("productos").insert({ ...editable, controla_lotes })
      : supabase.from("productos").update(editable).eq("id_producto", id);
  const { data, error } = await query.select(productoColumns).single();
  if (error) throw new Error(mensajeErrorProducto(error));
  if (!data)
    throw new Error(
      "No se pudo confirmar el producto guardado. Actualiza el catálogo.",
    );
  return data as Producto;
}
