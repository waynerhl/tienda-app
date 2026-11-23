import { useEffect,useRef,useState } from "react";
import type { FormEvent } from "react";
import { supabase } from "../lib/supabase";
import { prepararPresentacion } from "../services/presentacionValidation";
import type { Producto } from "../types/producto";
export default function PresentacionForm({producto,onCancel,onSaved}:{producto:Producto;onCancel:()=>void;onSaved:(p:Producto)=>void}) {
 const dialog=useRef<HTMLDialogElement>(null);const lock=useRef(false);
 const [activa,setActiva]=useState(!!producto.paquete_unidades);const [nombre,setNombre]=useState(producto.paquete_nombre??"");
 const [unidades,setUnidades]=useState(producto.paquete_unidades?String(producto.paquete_unidades):"");const [precio,setPrecio]=useState(producto.paquete_precio==null?"":String(producto.paquete_precio));
 const [predeterminada,setPredeterminada]=useState(producto.paquete_predeterminado??false);const [guardando,setGuardando]=useState(false);const [error,setError]=useState("");
 useEffect(()=>{const el=dialog.current;el?.showModal();return ()=>el?.close();},[]);
 async function guardar(e:FormEvent){e.preventDefault();if(!supabase||lock.current)return;setError("");try{
  const payload=prepararPresentacion(producto.id_producto,producto.paquete_version??0,activa,nombre,unidades,precio,predeterminada);lock.current=true;setGuardando(true);
  const r=await supabase.rpc("configurar_paquete_producto",payload);if(r.error)throw new Error(r.error.code==="22023"||r.error.code==="42501"?r.error.message:"No pudimos confirmar el cambio. Actualiza el catálogo y revisa la presentación antes de repetirlo.");
  if(r.data?.id_producto!==producto.id_producto)throw new Error("Actualiza el catálogo para comprobar el cambio.");onSaved(r.data as Producto);
 }catch(e){setError(e instanceof Error?e.message:"No pudimos confirmar la presentación. Actualiza el catálogo.");}finally{lock.current=false;setGuardando(false);}}
 return <dialog ref={dialog} className="product-dialog" aria-labelledby="presentacion-titulo" onCancel={e=>{e.preventDefault();if(!lock.current)onCancel();}}>
  <div className="form-heading"><h2 id="presentacion-titulo">Presentación: {producto.nombre}</h2><button type="button" className="secondary" disabled={guardando} onClick={onCancel}>Cerrar</button></div>
  <p className="muted">El inventario se conserva por unidades. Se cobra cada paquete completo a su precio total y los sobrantes al precio individual.</p>
  <form onSubmit={guardar}><fieldset disabled={guardando}>
   <label className="checkbox-row"><input type="checkbox" checked={activa} onChange={e=>setActiva(e.target.checked)}/> Habilitar precio por paquete</label>
   {activa&&<>
    <label htmlFor="presentacion-nombre">Nombre de la presentación</label><input id="presentacion-nombre" required maxLength={50} placeholder="Caja o Cartón" value={nombre} onChange={e=>setNombre(e.target.value)}/>
    <label htmlFor="presentacion-unidades">Unidades por paquete</label><input id="presentacion-unidades" required inputMode="numeric" value={unidades} onChange={e=>setUnidades(e.target.value)}/>
    <label htmlFor="presentacion-precio">Precio total del paquete (Q)</label><input id="presentacion-precio" required inputMode="decimal" value={precio} onChange={e=>setPrecio(e.target.value)}/>
    <label className="checkbox-row"><input type="checkbox" checked={predeterminada} onChange={e=>setPredeterminada(e.target.checked)}/> Al pulsar Agregar en Ventas, añadir un paquete completo</label>
    <p className="footnote">Si no marcas esta última opción, Agregar añade una unidad. También podrás añadir paquetes con su botón. Una presentación por producto; cambiarla no modifica ventas anteriores.</p>
   </>}
   {!activa&&<p className="footnote">Las ventas nuevas usarán solo el precio por unidad. Se conservan los precios de las ventas anteriores.</p>}
   {error&&<p className="error" role="alert">{error}</p>}<div className="form-actions"><button>{guardando?"Guardando…":"Guardar presentación"}</button></div>
  </fieldset></form>
 </dialog>;
}
