export interface Producto {
  paquete_nombre?: string | null;
  paquete_unidades?: number | null;
  paquete_precio?: number | null;
  paquete_predeterminado?: boolean;
  paquete_version?: number;
  id_producto: number;
  categoria_id: number;
  nombre: string;
  codigo_barras: string | null;
  precio_venta: number;
  existencia: number;
  existencia_minima: number;
  activo: boolean;
  controla_lotes: boolean;
}

export interface Categoria {
  id_categoria: number;
  nombre: string;
}

export interface ProductoFormValues {
  nombre: string;
  categoria_id: string;
  codigo_barras: string;
  precio_venta: string;
  existencia_minima: string;
  activo: boolean;
  controla_lotes: boolean;
}

export interface ProductoPayload {
  nombre: string;
  categoria_id: number;
  codigo_barras: string | null;
  precio_venta: number;
  existencia_minima: number;
  activo: boolean;
  controla_lotes: boolean;
}
