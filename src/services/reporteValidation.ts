import { hoyGuatemala } from "./compraValidation";
export function validarPeriodo(
  desde: string,
  hasta: string,
  hoy = hoyGuatemala(),
): void {
  for (const d of [desde, hasta])
    if (
      !/^\d{4}-\d{2}-\d{2}$/.test(d) ||
      !Number.isFinite(Date.parse(d)) ||
      new Date(d).toISOString().slice(0, 10) !== d
    )
      throw new Error("Selecciona fechas válidas.");
  if (desde < "1900-01-01" || desde > hasta || hasta > hoy)
    throw new Error(
      "La fecha inicial debe ser anterior o igual a la final, hasta hoy.",
    );
  if ((Date.parse(hasta) - Date.parse(desde)) / 86400000 > 365)
    throw new Error("Consulta hasta 366 días por período.");
}
export type DiaVentas = {
  dia: string;
  total: number;
  transacciones: number;
  unidades: number;
};
export function csvVentasDiarias(serie: DiaVentas[]): string {
  return (
    "\ufefffecha,total_gtq,transacciones,unidades\r\n" +
    serie
      .map(
        (d) =>
          `${d.dia},${Number(d.total).toFixed(2)},${d.transacciones},${d.unidades}`,
      )
      .join("\r\n") +
    "\r\n"
  );
}
