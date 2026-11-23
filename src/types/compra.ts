export interface ProductoCompra {
  id_producto: number;
  nombre: string;
  codigo_barras: string | null;
  controla_lotes: boolean;
  activo: boolean;
  ultimo_costo: number | null;
}
export interface LoteCompraForm {
  key: string;
  cantidad: string;
  numero_lote: string;
  fecha_vencimiento: string;
}
export interface LineaCompraForm {
  producto: ProductoCompra;
  cantidad: string;
  costo_unitario: string;
  lotes: LoteCompraForm[];
}
export interface Proveedor {
  id_proveedor: number;
  nombre: string;
}
export interface FormaPago {
  id_forma_pago: number;
  nombre: string;
}
export interface CompraResumen {
  fondo_efectivo?: "CAJA" | "RESERVA";
  id_compra: number;
  proveedor_id: number;
  forma_pago_id: number;
  numero_documento: string | null;
  fecha: string;
  total: number;
  estado: string;
}
export interface CompraGuardada {
  fondo_efectivo?: "CAJA" | "RESERVA";
  id_compra: number;
  total: number;
  estado: string;
}
export interface CompraPayload {
  p_fondo?: "CAJA" | "RESERVA";
  p_proveedor_id: number;
  p_forma_pago_id: number;
  p_numero_documento: string;
  p_fecha_limite: string | null;
  p_items: {
    producto_id: number;
    cantidad: number;
    costo_unitario: number;
    lotes?: {
      cantidad: number;
      numero_lote: string | null;
      fecha_vencimiento: string | null;
    }[];
  }[];
}
