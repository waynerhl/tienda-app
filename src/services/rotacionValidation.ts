import { validarPeriodo } from "./reporteValidation";

export type ProductoRotacion = {
  id_producto: number;
  nombre: string;
  codigo_barras: string | null;
  existencia: number;
  existencia_minima: number;
  unidades: number;
  importe: number;
  disponible: number;
  vencido: number;
  inconsistente: boolean;
  promedio_diario: number;
  cobertura_dias: number | null;
  sugerencia: number | null;
  bajo_minimo: boolean;
  estado: "REVISAR" | "SIN_VENTAS" | "REPONER" | "SUFICIENTE";
};

export function validarRotacion(desde: string, hasta: string, objetivo: string, hoy?: string): number {
  validarPeriodo(desde, hasta, hoy);
  if (!/^\d{1,2}$/.test(objetivo) || Number(objetivo) < 1 || Number(objetivo) > 90)
    throw new Error("El objetivo debe ser de 1 a 90 días enteros.");
  return Number(objetivo);
}

export function csvRotacion(productos: ProductoRotacion[], desde: string, hasta: string, objetivo: number, fechaStock: string): string {
  function texto(s: string) {
    const seguro = /^\s*[=+\-@]/.test(s) || /^[\t\r\n]/.test(s) ? "'" + s : s;
    return '"' + seguro.replaceAll('"', '""') + '"';
  }
  return "\ufeffdesde,hasta,objetivo_dias,fecha_stock,producto,codigo_barras,unidades_vendidas,importe_gtq,disponible_actual,vencido_actual,minimo_actual,promedio_diario,cobertura_dias,sugerencia_unidades,estado,bajo_minimo\r\n" +
    productos.map(p => [desde, hasta, objetivo, fechaStock, texto(p.nombre), texto(p.codigo_barras ?? ""),
      p.unidades, Number(p.importe).toFixed(2), p.disponible, p.vencido, p.existencia_minima,
      p.promedio_diario, p.cobertura_dias ?? "", p.sugerencia ?? "", p.estado, p.bajo_minimo ? "SI" : "NO"].join(",")).join("\r\n") + "\r\n";
}
