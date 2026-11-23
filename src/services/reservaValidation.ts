import { montoCentavos } from "./cobroValidation";
export const tiposReserva = ["INICIAL","APORTE","GASTO","RETIRO_PERSONAL","CAJA_A_RESERVA","RESERVA_A_CAJA"] as const;
export type TipoReserva = typeof tiposReserva[number];
export const nombresReserva: Record<TipoReserva,string> = { INICIAL:"Saldo inicial de Reserva",APORTE:"Aporte externo a Reserva",GASTO:"Gasto de la tienda desde Reserva",RETIRO_PERSONAL:"Retiro personal desde Reserva",CAJA_A_RESERVA:"Apartar dinero de Caja a Reserva",RESERVA_A_CAJA:"Regresar dinero de Reserva a Caja" };
export type ReservaPayload = { p_solicitud_id:string;p_tipo:TipoReserva;p_monto:number;p_concepto:string };
export function prepararReserva(tipo:TipoReserva,monto:string,concepto:string,uuid:string):ReservaPayload {
 if (!tiposReserva.includes(tipo)) throw new Error("Selecciona una operación válida.");
 const centavos=montoCentavos(monto); const detalle=concepto.trim();
 if ((tipo!=="INICIAL" && centavos===0) || !detalle || detalle.length>500) throw new Error("Indica un monto mayor que cero y un concepto de hasta 500 caracteres. El saldo inicial admite cero.");
 return {p_solicitud_id:uuid,p_tipo:tipo,p_monto:centavos/100,p_concepto:detalle};
}
export function recuperarReserva(clave:string):{pendiente:ReservaPayload|null;error:string} {
 try {
  const raw=localStorage.getItem(clave);if(!raw)return {pendiente:null,error:""};const p=JSON.parse(raw) as ReservaPayload;
  if(!p || !/^[\da-f]{8}(-[\da-f]{4}){3}-[\da-f]{12}$/i.test(p.p_solicitud_id) || typeof p.p_monto!=="number" || !Number.isFinite(p.p_monto) || typeof p.p_concepto!=="string")throw new Error();
  const validado=prepararReserva(p.p_tipo,String(p.p_monto),p.p_concepto,p.p_solicitud_id);
  if(validado.p_monto!==p.p_monto)throw new Error();return {pendiente:p,error:""};
 }catch{return {pendiente:null,error:"No pudimos recuperar la confirmación de Reserva. Conserva el historial del navegador y revisa los movimientos antes de registrar otra."};}
}
