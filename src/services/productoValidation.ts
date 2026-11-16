import type { ProductoFormValues, ProductoPayload } from "../types/producto";

export function validarProducto(values: ProductoFormValues): ProductoPayload {
  const nombre = values.nombre.trim();
  const codigo = values.codigo_barras.trim();
  if (!nombre || nombre.length > 150)
    throw new Error("Escribe un nombre de 1 a 150 caracteres.");
  const categoria = Number(values.categoria_id);
  if (!Number.isSafeInteger(categoria) || categoria <= 0)
    throw new Error("Selecciona una categoría.");
  if (codigo.length > 50)
    throw new Error("El código de barras admite hasta 50 caracteres.");
  const precioTexto = values.precio_venta.trim().replace(",", ".");
  if (!/^\d+(\.\d{1,2})?$/.test(precioTexto))
    throw new Error(
      "Escribe un precio igual o mayor que cero, con hasta dos decimales.",
    );
  const precio = Number(precioTexto);
  if (!Number.isFinite(precio) || precio > 9999999999.99)
    throw new Error("El precio supera el máximo permitido.");
  const minimoTexto = values.existencia_minima.trim();
  const minimo = Number(minimoTexto);
  if (
    !/^\d+$/.test(minimoTexto) ||
    !Number.isSafeInteger(minimo) ||
    minimo > 2147483647
  )
    throw new Error(
      "La existencia mínima debe ser un número entero entre 0 y 2147483647.",
    );
  return {
    nombre,
    categoria_id: categoria,
    codigo_barras: codigo || null,
    precio_venta: precio,
    existencia_minima: minimo,
    activo: values.activo,
    controla_lotes: values.controla_lotes,
  };
}

export function mensajeErrorProducto(error: { code?: string }): string {
  if (error.code === "23505")
    return "Este código de barras ya pertenece a otro producto. Revisa el código o déjalo vacío.";
  if (error.code === "23503")
    return "La categoría seleccionada ya no está disponible. Cierra el formulario y vuelve a abrirlo.";
  if (error.code === "42501")
    return "Tu cuenta no tiene permiso para guardar este producto. Comprueba que tu perfil siga activo y autorizado.";
  if (error.code === "23514" || error.code === "22003")
    return "Revisa los valores: el precio y la existencia mínima deben estar dentro de los límites permitidos.";
  if (error.code === "PGRST116")
    return "No se pudo modificar el producto: puede haber sido eliminado o tu cuenta ya no tiene permiso.";
  return "No pudimos confirmar el guardado. Actualiza el catálogo antes de reintentar para comprobar si se registró.";
}
