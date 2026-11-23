/** Coincide con public.normalizar_busqueda: ñ es una letra distinta. */
export function normalizarBusqueda(texto: string): string {
  const origen = "áéíóúüÁÉÍÓÚÜ";
  const destino = "aeiouuAEIOUU";
  return texto.normalize("NFC")
    .replace(/[áéíóúüÁÉÍÓÚÜ]/g, letra => destino[origen.indexOf(letra)])
    .toLowerCase();
}

export function patronBusquedaNombre(texto: string): string {
  return `%${normalizarBusqueda(texto).replace(/[\\%_]/g, "\\$&")}%`;
}
