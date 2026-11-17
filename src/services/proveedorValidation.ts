import type { Proveedor } from "../types/pagoProveedor";
export function prepararProveedor(
  nombre: string,
  telefono: string,
  direccion: string,
  correo: string,
): Omit<Proveedor, "id_proveedor"> {
  const n = nombre.trim(),
    t = telefono.trim(),
    d = direccion.trim(),
    c = correo.trim();
  if (!n || n.length > 150)
    throw new Error("Escribe un nombre de hasta 150 caracteres.");
  if (t.length > 20) throw new Error("El teléfono admite hasta 20 caracteres.");
  if (d.length > 250)
    throw new Error("La dirección admite hasta 250 caracteres.");
  if (c && (c.length > 150 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(c)))
    throw new Error("Escribe un correo válido de hasta 150 caracteres.");
  return {
    nombre: n,
    telefono: t || null,
    direccion: d || null,
    correo: c || null,
  };
}
