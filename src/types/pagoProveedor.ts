export type Proveedor = {
  id_proveedor: number;
  nombre: string;
  telefono: string | null;
  correo: string | null;
  direccion: string | null;
};
export type ProveedorSaldo = Proveedor & { saldo: number; vencido: number };
export type ListaProveedores = { total: number; proveedores: ProveedorSaldo[] };
export type CuentaProveedor = {
  id_cuenta_por_pagar: number;
  compra_id: number;
  numero_documento: string | null;
  monto_original: number;
  saldo_pendiente: number;
  fecha_limite: string | null;
  fecha: string;
  estado: "PAGADA" | "PENDIENTE" | "VENCIDA";
};
export type EstadoProveedor = {
  proveedor: Proveedor;
  total: number;
  saldo: number;
  vencido: number;
  cuentas: CuentaProveedor[];
};
export type { FormaAbono } from "./cobro";
