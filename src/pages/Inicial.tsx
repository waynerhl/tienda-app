import { useEffect, useRef, useState } from "react";
import type { FormEvent } from "react";
import { supabase } from "../lib/supabase";
import { hoyGuatemala } from "../services/compraValidation";
import { nuevaPartida, prepararInicial, recuperarInicial } from "../services/inicialValidation";
import type { ProductoInicial, PartidaInicialForm, InicialPayload, InicialResultado } from "../services/inicialValidation";
import "./Inventario.css";
import "./Inicial.css";
const dinero = (n: number) => new Intl.NumberFormat("es-GT", { style: "currency", currency: "GTQ" }).format(Number(n));
function RevisionInicial({ p }: { p: InicialPayload }) {
  return <div className="table-scroll" tabIndex={0} role="region" aria-label="Partidas iniciales a confirmar"><table>
    <thead><tr><th>Lote</th><th>Vencimiento</th><th className="numeric">Unidades</th><th className="numeric">Costo unitario</th><th className="numeric">Valor</th></tr></thead>
    <tbody>{p.p_partidas.map((f,i) => <tr key={i}><td>{f.numero_lote ?? "Sin lotes"}</td><td>{f.fecha_vencimiento ?? "Sin vencimiento"}</td><td className="numeric">{f.cantidad}</td><td className="numeric">{dinero(Number(f.costo_unitario))}</td><td className="numeric">{dinero(f.cantidad * Number(f.costo_unitario))}</td></tr>)}</tbody>
  </table></div>;
}
export default function Inicial({ activo, revision, userId, onChanged }: { activo: boolean; revision: number; userId: string; onChanged: () => void }) {
  const clave = `tienda:inventario-inicial-pendiente:${userId}`;
  const [recuperado] = useState(() => recuperarInicial(clave));
  const [pendiente, setPendiente] = useState<InicialPayload | null>(recuperado.pendiente);
  const [preparada, setPreparada] = useState<InicialPayload | null>(null);
  const [producto, setProducto] = useState<ProductoInicial | null>(null);
  const [filas, setFilas] = useState<PartidaInicialForm[]>([nuevaPartida()]);
  const [motivo, setMotivo] = useState("Inventario inicial contado antes de comenzar a usar la app.");
  const [texto, setTexto] = useState(""); const [modo, setModo] = useState("nombre");
  const [consulta, setConsulta] = useState({ texto: "", modo: "nombre" });
  const [productos, setProductos] = useState<ProductoInicial[]>([]);
  const [cargando, setCargando] = useState(true); const [errorCarga, setErrorCarga] = useState("");
  const [error, setError] = useState(""); const [guardando, setGuardando] = useState(false);
  const [resultado, setResultado] = useState<InicialResultado | null>(null); const [intento, setIntento] = useState(0);
  const bloqueo = useRef(false); const bloqueado = !!pendiente || !!preparada || guardando || !!recuperado.error;
  useEffect(() => {
    if (!activo) return; const controller = new AbortController();
    async function cargar() {
      if (!supabase) return; setCargando(true); setErrorCarga("");
      try {
        const r = await supabase.rpc("obtener_productos_inicial", { p_busqueda: consulta.texto, p_modo: consulta.modo }).abortSignal(controller.signal);
        if (controller.signal.aborted) return;
        if (r.error || !Array.isArray(r.data)) throw new Error(); setProductos(r.data as ProductoInicial[]);
      } catch { if (!controller.signal.aborted) setErrorCarga("No pudimos consultar los productos. Revisa la conexión."); }
      finally { if (!controller.signal.aborted) setCargando(false); }
    }
    void cargar(); return () => controller.abort();
  }, [activo, revision, consulta, intento]);
  function elegir(p: ProductoInicial) { if (bloqueado || !p.disponible_inicial) return; setProducto(p); setFilas([nuevaPartida()]); setError(""); setResultado(null); }
  function cambiar(i: number, campo: keyof PartidaInicialForm, valor: string) { setFilas(f => f.map((p,j) => i === j ? { ...p, [campo]: valor } : p)); }
  function preparar(e: FormEvent) {
    e.preventDefault(); if (!producto || bloqueado) return; setError("");
    try { setPreparada(prepararInicial(producto, filas, motivo, crypto.randomUUID())); }
    catch (e) { setError(e instanceof Error ? e.message : "Revisa los datos."); }
  }
  async function confirmar(p: InicialPayload, reintento = false) {
    if (!supabase || bloqueo.current) return; bloqueo.current = true; setGuardando(true); setError("");
    try {
      try { localStorage.setItem(clave, JSON.stringify(p)); }
      catch { throw new Error("No pudimos guardar la referencia de confirmación. No se envió la carga; habilita el almacenamiento del navegador."); }
      setPendiente(p); setPreparada(null);
      const r = await supabase.rpc("registrar_inventario_inicial", p);
      if (r.error) {
        const conocida = ["22023","22007","22008","23505"].includes(r.error.code) || (!reintento && r.error.code === "42501");
        if (conocida) { localStorage.removeItem(clave); setPendiente(null); setProducto(null); setIntento(v => v + 1); throw new Error(r.error.message); }
        throw new Error("No pudimos confirmar el resultado. Conserva esta referencia y pulsa Reintentar confirmación; no prepares otra carga.");
      }
      if (r.data?.producto_id !== p.p_producto_id || !r.data?.id_inicial || r.data?.cantidad !== p.p_partidas.reduce((n,f) => n + f.cantidad,0)) throw new Error("La respuesta requiere revisión. Reintenta con la misma referencia para comprobar el resultado.");
      // Si falla limpiar el navegador, se conserva la solicitud para un reintento seguro.
      localStorage.removeItem(clave); setPendiente(null); setProducto(null); setResultado(r.data as InicialResultado); setIntento(v => v + 1); onChanged();
    } catch (e) { setError(e instanceof Error ? e.message : "No pudimos confirmar el resultado. Reintenta con la misma referencia."); }
    finally { bloqueo.current = false; setGuardando(false); }
  }
  const revisar = pendiente ?? preparada;
  return <>
    <div className="section-heading"><div><p className="eyebrow">MERCADERÍA QUE YA TIENES</p><h1>Inventario inicial</h1><p className="muted">Registra el conteo y costo antes de comenzar a operar cada producto.</p></div></div>
    <p className="dashboard-warning">Se admite una sola carga por producto sin historial y con existencia cero. Incluye todos sus lotes en la misma confirmación. No genera compras, deudas ni salidas de caja.</p>
    {recuperado.error && <p className="error" role="alert">{recuperado.error}</p>}
    {error && <p className="error" role="alert">{error}</p>}
    {resultado && <section className="catalog-card purchase-panel cobros-section" role="status"><h2>Inventario inicial registrado</h2><p>Comprobante #{resultado.id_inicial} · {resultado.cantidad} unidades · Valor inicial {dinero(resultado.valor_inicial)}.</p><p>Consulta los lotes en Inventario y los productos disponibles en Ventas. Las nuevas compras se registran en Compras.</p></section>}
    {revisar && <section className="catalog-card cobros-section" aria-label="Confirmación de inventario inicial">
      <div className="purchase-panel"><h2>{pendiente ? "Confirmación pendiente" : "Revisa antes de registrar"}</h2><p>Producto #{revisar.p_producto_id}{producto ? `: ${producto.nombre}` : ""} · Referencia: <span className="inicial-referencia">{revisar.p_solicitud_id}</span></p><p>{revisar.p_motivo}</p><p><strong>{revisar.p_partidas.reduce((n,f) => n+f.cantidad,0)} unidades en total.</strong> Comprueba que no las registraste antes.</p></div>
      <RevisionInicial p={revisar} />
      <div className="purchase-panel form-actions">{!pendiente && <button className="secondary" disabled={guardando} onClick={() => setPreparada(null)}>Volver a editar</button>}
        <button disabled={guardando} onClick={() => void confirmar(revisar,!!pendiente)}>{guardando ? "Confirmando…" : pendiente ? "Reintentar confirmación" : "Confirmar inventario inicial"}</button></div>
    </section>}
    <form className="catalog-card purchase-panel cobros-section" onSubmit={e => { e.preventDefault(); if (!bloqueado) setConsulta({ texto: texto.trim(), modo }); }}>
      <fieldset className="purchase-fields" disabled={bloqueado}>
        <label htmlFor="inicial-modo">Buscar por</label><select id="inicial-modo" value={modo} onChange={e => setModo(e.target.value)}><option value="nombre">Nombre</option><option value="codigo_barras">Código de barras exacto</option></select>
        <label htmlFor="inicial-busqueda">Producto</label><input id="inicial-busqueda" maxLength={150} value={texto} onChange={e => setTexto(e.target.value)} /><div className="form-actions"><button>Buscar producto</button></div>
      </fieldset><p className="footnote">Hasta 20 coincidencias. Crea primero el producto en Productos y activa Control por lotes si corresponde.</p>
    </form>
    {cargando ? <p className="state" role="status">Consultando productos…</p> : errorCarga ? <div><p className="error" role="alert">{errorCarga}</p><button onClick={() => setIntento(v => v + 1)}>Actualizar productos</button></div> :
      <section className="catalog-card cobros-section"><div className="table-scroll" role="region" aria-label="Productos para inventario inicial" tabIndex={0}><table>
        <thead><tr><th>Producto</th><th className="numeric">Existencia</th><th>Preparación</th><th>Acción</th></tr></thead>
        <tbody>{productos.map(p => <tr key={p.id_producto}><td className="product-name">{p.nombre}<span className="history-date">{p.codigo_barras ?? "Sin código"} · {p.controla_lotes ? "Con lotes" : "Sin lotes"}</span></td><td className="numeric">{p.existencia}</td>
          <td>{p.inicial ? `Inicial ya registrado: #${p.inicial.id_inicial}, ${p.inicial.cantidad} unidades` : p.disponible_inicial ? "Listo para cargar" : "Tiene historial, existencias o está inactivo"}</td>
          <td><button className="secondary" disabled={bloqueado || !p.disponible_inicial} onClick={() => elegir(p)}>Preparar inicial</button></td></tr>)}
          {!productos.length && <tr><td colSpan={4}>No hay coincidencias. Revisa el nombre o crea el producto primero.</td></tr>}</tbody>
      </table></div></section>}
    {producto && !revisar && <form className="catalog-card purchase-panel cobros-section" onSubmit={preparar}>
      <h2>Existencias iniciales: {producto.nombre}</h2><p className="muted">Anota únicamente unidades aptas para vender. El costo es por unidad, no el precio de venta. Cero significa costo conocido de Q0.00; no lo uses para un costo desconocido.</p>
      <fieldset className="purchase-fields" disabled={bloqueado}>{filas.map((f,i) => <fieldset className="purchase-line" key={i}><legend>{producto.controla_lotes ? `Lote ${i+1}` : "Unidades contadas"}</legend>
        <div className="inicial-fila">{producto.controla_lotes && <><div><label htmlFor={`inicial-lote-${i}`}>Número o referencia del lote</label><input id={`inicial-lote-${i}`} required maxLength={50} value={f.numero_lote} onChange={e => cambiar(i,"numero_lote",e.target.value)} /></div>
          <div><label htmlFor={`inicial-fecha-${i}`}>Vencimiento (si aplica)</label><input id={`inicial-fecha-${i}`} type="date" min={hoyGuatemala()} value={f.fecha_vencimiento} onChange={e => cambiar(i,"fecha_vencimiento",e.target.value)} /></div></>}
          <div><label htmlFor={`inicial-cantidad-${i}`}>Cantidad de unidades</label><input id={`inicial-cantidad-${i}`} required inputMode="numeric" value={f.cantidad} onChange={e => cambiar(i,"cantidad",e.target.value)} /></div>
          <div><label htmlFor={`inicial-costo-${i}`}>Costo por unidad (Q)</label><input id={`inicial-costo-${i}`} required inputMode="decimal" value={f.costo} onChange={e => cambiar(i,"costo",e.target.value)} /></div></div>
        {filas.length>1 && <button type="button" className="secondary" onClick={() => setFilas(f => f.filter((_,j) => i!==j))}>Quitar lote {i+1}</button>}
      </fieldset>)}
      {producto.controla_lotes && <button type="button" className="secondary" disabled={filas.length>=100} onClick={() => setFilas(f => [...f,nuevaPartida()])}>Añadir otro lote</button>}
      <p className="footnote">Si el empaque no tiene número de lote, usa una referencia interna, por ejemplo INICIAL-01. Deja vencimiento vacío solo si el producto no tiene fecha de vencimiento.</p>
      <label htmlFor="inicial-motivo">Motivo del registro</label><textarea id="inicial-motivo" required maxLength={500} value={motivo} onChange={e => setMotivo(e.target.value)} />
      <div className="form-actions"><button>Revisar inventario inicial</button><button type="button" className="secondary" onClick={() => setProducto(null)}>Cerrar preparación</button></div>
      </fieldset></form>}
  </>;
}
