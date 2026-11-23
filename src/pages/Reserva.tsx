import { useEffect,useRef,useState } from "react";
import type { FormEvent } from "react";
import { supabase } from "../lib/supabase";
import { hoyGuatemala } from "../services/compraValidation";
import { prepararReserva,recuperarReserva,nombresReserva } from "../services/reservaValidation";
import type { TipoReserva,ReservaPayload } from "../services/reservaValidation";
import "./Efectivo.css";
import "./Inventario.css";
type Movimiento = {id_evento:number;fecha:string;tipo:TipoReserva|"COMPRA"|"PAGO_PROVEEDOR";monto:number;reserva_delta:number;caja_delta:number;fecha_caja:string|null;saldo_posterior:number;compra_id:number|null;pago_id:number|null;concepto:string};
type Datos = {saldo:number;inicializada:boolean;saldo_libro:number;total:number;fecha:string;movimientos:Movimiento[]};
type Caja = {saldo_esperado:number|null;caja:{estado:string;ultimo_cierre:{efectivo_contado:number}|null}|null};
const dinero=(n:number)=>new Intl.NumberFormat("es-GT",{style:"currency",currency:"GTQ"}).format(Number(n));
const hora=(s:string)=>new Intl.DateTimeFormat("es-GT",{timeZone:"America/Guatemala",dateStyle:"short",timeStyle:"short"}).format(new Date(s));
export default function Reserva({activo,revision,userId,onChanged}:{activo:boolean;revision:number;userId:string;onChanged:()=>void}) {
 const clave=`tienda:reserva-pendiente:${userId}`;const [recuperado]=useState(()=>recuperarReserva(clave));
 const [pendiente,setPendiente]=useState<ReservaPayload|null>(recuperado.pendiente);const [preparada,setPreparada]=useState<ReservaPayload|null>(null);
 const [datos,setDatos]=useState<Datos|null>(null);const [caja,setCaja]=useState<Caja|null>(null);const [pagina,setPagina]=useState(0);const [intento,setIntento]=useState(0);
 const [cargando,setCargando]=useState(true);const [errorCarga,setErrorCarga]=useState("");const [error,setError]=useState("");const [mensaje,setMensaje]=useState("");
 const [tipo,setTipo]=useState<TipoReserva>("CAJA_A_RESERVA");const [monto,setMonto]=useState("");const [concepto,setConcepto]=useState("");const [guardando,setGuardando]=useState(false);const bloqueo=useRef(false);
 const bloqueado=!!pendiente||!!preparada||guardando||!!recuperado.error;
 useEffect(()=>{
  if(!activo)return;const controller=new AbortController();
  async function cargar(){if(!supabase)return;setCargando(true);setErrorCarga("");try{
   const [r,c]=await Promise.all([supabase.rpc("obtener_reserva",{p_pagina:pagina}).abortSignal(controller.signal),supabase.rpc("obtener_caja_dia",{p_fecha:hoyGuatemala()}).abortSignal(controller.signal)]);
   if(controller.signal.aborted)return;if(r.error||c.error||!Array.isArray(r.data?.movimientos)||!Number.isFinite(r.data?.saldo))throw new Error();setDatos(r.data as Datos);setCaja(c.data as Caja);
  }catch{if(!controller.signal.aborted)setErrorCarga("No pudimos consultar los fondos. Revisa la conexión.");}finally{if(!controller.signal.aborted)setCargando(false);}}
  void cargar();return ()=>controller.abort();
 },[activo,revision,pagina,intento]);
 function preparar(e:FormEvent){e.preventDefault();if(bloqueado||!datos||cargando||errorCarga)return;setError("");setMensaje("");try{setPreparada(prepararReserva(datos.inicializada?tipo:"INICIAL",monto,concepto,crypto.randomUUID()));}catch(e){setError(e instanceof Error?e.message:"Revisa el movimiento.");}}
 async function confirmar(p:ReservaPayload,reintento=false){if(!supabase||bloqueo.current)return;bloqueo.current=true;setGuardando(true);setError("");try{
  try{localStorage.setItem(clave,JSON.stringify(p));}catch{throw new Error("No se envió el movimiento: habilita el almacenamiento del navegador para conservar la referencia.");}
  setPendiente(p);setPreparada(null);const r=await supabase.rpc("operar_reserva",p);
  if(r.error){if(["22023","23503","23514"].includes(r.error.code)||(!reintento&&r.error.code==="42501")){localStorage.removeItem(clave);setPendiente(null);setIntento(v=>v+1);throw new Error(r.error.message);}throw new Error("No pudimos confirmar el resultado. Reintenta con la misma referencia; no prepares otro movimiento.");}
  if(!r.data?.id_evento||r.data.tipo!==p.p_tipo||Number(r.data.monto)!==p.p_monto)throw new Error("La respuesta requiere revisión. Reintenta con la misma referencia.");
  localStorage.removeItem(clave);setPendiente(null);setMonto("");setConcepto("");setPagina(0);setMensaje(`Movimiento confirmado. Comprobante #${r.data.id_evento}.`);setIntento(v=>v+1);onChanged();
 }catch(e){setError(e instanceof Error?e.message:"No pudimos confirmar el movimiento. Conserva la referencia y reintenta.");}finally{bloqueo.current=false;setGuardando(false);}}
 const revisar=pendiente??preparada;const saldoCaja=caja?.caja?.estado==="CERRADA"?caja.caja.ultimo_cierre?.efectivo_contado:caja?.saldo_esperado;
 const operacion=datos?.inicializada?tipo:"INICIAL";
 return <>
  <div className="section-heading"><div><p className="eyebrow">EFECTIVO APARTADO DE LA CAJA</p><h1>Reserva de la tienda</h1><p className="muted">Conserva su saldo entre jornadas. Compras, gastos y retiros personales se distinguen en el historial.</p></div><button className="secondary" disabled={cargando||bloqueado} onClick={()=>setIntento(v=>v+1)}>Actualizar fondos</button></div>
  {recuperado.error&&<p className="error" role="alert">{recuperado.error}</p>}{error&&<p className="error" role="alert">{error}</p>}{mensaje&&<p className="inventory-note" role="status">{mensaje}</p>}
  {revisar&&<section className="catalog-card purchase-panel cobros-section" aria-label="Confirmar movimiento de Reserva"><h2>{pendiente?"Confirmación pendiente":"Revisa el movimiento"}</h2><p><strong>{nombresReserva[revisar.p_tipo]} · {dinero(revisar.p_monto)}</strong></p><p>{revisar.p_concepto}</p><p className="footnote">Referencia: {revisar.p_solicitud_id}. Los movimientos nuevos se registran en la fecha actual de Guatemala. Los reintentos conservan el comprobante original si ya fue registrado.</p><div className="form-actions">{!pendiente&&<button className="secondary" onClick={()=>setPreparada(null)}>Volver a editar</button>}<button disabled={guardando} onClick={()=>void confirmar(revisar,!!pendiente)}>{guardando?"Confirmando…":pendiente?"Reintentar confirmación":"Confirmar movimiento"}</button></div></section>}
  {cargando?<p className="state" role="status">Consultando fondos…</p>:errorCarga?<p className="error" role="alert">{errorCarga}</p>:datos&&<>
   <div className="cash-grid"><article className="cash-stat"><span>Reserva acumulada</span><strong>{datos.inicializada?dinero(datos.saldo):"Sin iniciar"}</strong></article><article className="cash-stat"><span>Caja de hoy</span><strong>{saldoCaja==null?"Sin apertura":dinero(saldoCaja)}</strong><small>{caja?.caja?.estado==="CERRADA"?"Último conteo de cierre de hoy":"Saldo esperado de atención"}</small></article><article className="cash-stat"><span>Efectivo en ambos fondos</span><strong>{!datos.inicializada||saldoCaja==null?"Pendiente de apertura":dinero(Number(datos.saldo)+Number(saldoCaja))}</strong><small>Compara los saldos con el dinero físico.</small></article></div>
   {Number(datos.saldo)!==Number(datos.saldo_libro)&&<p className="error" role="alert">El saldo de Reserva no coincide con sus movimientos. Revisa el historial antes de operar.</p>}
   <section className="catalog-card purchase-panel cobros-section"><h2>{datos.inicializada?"Registrar en Reserva":"Preparar el saldo inicial"}</h2>
    {!datos.inicializada&&<p>Cuenta únicamente el efectivo que ya tienes guardado aparte. No incluyas los Q400–Q500 que dejarás para cambio. Si aún no has apartado dinero, inicia con Q0.00 y después usa un traslado desde Caja.</p>}
    <form onSubmit={preparar}><fieldset className="purchase-fields" disabled={bloqueado||Number(datos.saldo)!==Number(datos.saldo_libro)}>
     {datos.inicializada&&<><label htmlFor="reserva-tipo">Operación</label><select id="reserva-tipo" value={tipo} onChange={e=>setTipo(e.target.value as TipoReserva)}>{Object.entries(nombresReserva).filter(([k])=>k!=="INICIAL").map(([k,n])=><option key={k} value={k}>{n}</option>)}</select></>}
     <label htmlFor="reserva-monto">Monto (Q)</label><input id="reserva-monto" required inputMode="decimal" value={monto} onChange={e=>setMonto(e.target.value)}/>
     <label htmlFor="reserva-concepto">Concepto</label><textarea id="reserva-concepto" required maxLength={500} value={concepto} onChange={e=>setConcepto(e.target.value)}/>
     <p className="footnote">{operacion.includes("CAJA")?"Los traslados requieren la caja de hoy abierta y saldo suficiente. No son gastos ni ingresos del negocio.":operacion==="RETIRO_PERSONAL"?"Dinero para ti o para gastos de tu casa. No es un gasto de la tienda.":operacion==="GASTO"?"Solo gastos del negocio, por ejemplo luz o internet de la tienda. Para uso compartido registra aquí únicamente la parte del negocio; la parte de casa es retiro personal.":operacion==="APORTE"?"Dinero externo que agregas a Reserva. Si proviene de Caja, usa un traslado para evitar duplicarlo.":"El saldo inicial se registra una sola vez y no modifica Caja."}</p>
     <button>Revisar movimiento</button>
    </fieldset></form><p className="footnote">Para comprar mercadería o abonar a proveedores, usa Compras o Proveedores y pagos y elige Efectivo → Reserva. No registres además un gasto aquí: descontaría dos veces.</p>
   </section>
   <section className="catalog-card cobros-section"><div className="purchase-panel"><h2>Historial acumulado de Reserva</h2><p className="muted">No se reinicia al cerrar Caja. Saldo posterior indica cuánto había después de cada movimiento registrado.</p></div><div className="table-scroll" role="region" aria-label="Movimientos de Reserva" tabIndex={0}><table><thead><tr><th>Fecha / comprobante</th><th>Operación</th><th>Concepto</th><th className="numeric">Entrada / salida</th><th className="numeric">Saldo posterior</th></tr></thead><tbody>{datos.movimientos.map(m=><tr key={m.id_evento}><td>#{m.id_evento}<span className="history-date">{hora(m.fecha)}</span></td><td>{m.tipo==="COMPRA"?`Compra #${m.compra_id}`:m.tipo==="PAGO_PROVEEDOR"?`Pago a proveedor #${m.pago_id}`:nombresReserva[m.tipo]}</td><td className="inventario-motivo">{m.concepto}</td><td className="numeric">{m.reserva_delta>=0?"+":"−"}{dinero(Math.abs(m.reserva_delta))}</td><td className="numeric">{dinero(m.saldo_posterior)}</td></tr>)}{!datos.movimientos.length&&<tr><td colSpan={5}>Todavía no hay movimientos en Reserva.</td></tr>}</tbody></table></div><div className="pagination"><span>{datos.total} movimientos · página {pagina+1}</span><div><button className="secondary" disabled={bloqueado||pagina===0} onClick={()=>setPagina(v=>v-1)}>Anterior</button>{" "}<button className="secondary" disabled={bloqueado||(pagina+1)*20>=datos.total} onClick={()=>setPagina(v=>v+1)}>Siguiente</button></div></div></section>
  </>}
 </>;
}
