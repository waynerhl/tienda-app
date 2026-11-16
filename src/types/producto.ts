export interface Producto {
  id_producto: number;
  nombre: string;
  codigo_barras: string | null;
  precio_venta: number;
  existencia: number;
  existencia_minima: number;
  activo: boolean;
}
