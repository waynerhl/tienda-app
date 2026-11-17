export type Cliente = {
  id_cliente: number;
  nombre: string;
  telefono: string | null;
  direccion: string | null;
  limite_credito: number | null;
};
export type ClienteSaldo = Cliente & { saldo: number; vencido: number };
export type ListaClientes = { total: number; clientes: ClienteSaldo[] };
export type Cuenta = {
  id_cuenta_por_cobrar: number;
  venta_id: number;
  monto_original: number;
  saldo_pendiente: number;
  fecha_limite: string | null;
  fecha: string;
  estado: "PAGADA" | "PENDIENTE" | "VENCIDA";
};
export type EstadoCliente = {
  cliente: Cliente;
  total: number;
  saldo: number;
  vencido: number;
  cuentas: Cuenta[];
};
export type AbonoPayload = {
  p_solicitud_id: string;
  p_cuenta_id: number;
  p_forma_pago_id: number;
  p_monto: number;
};
export type AbonoConfirmado = {
  id_pago: number;
  cuenta_id: number;
  monto: number;
  saldo_pendiente: number;
  repetida: boolean;
};
export type FormaAbono = { id_forma_pago: number; nombre: string };
