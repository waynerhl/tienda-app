import { useEffect, useState } from "react";
import type { FormEvent } from "react";
import { supabase } from "../lib/supabase";
import { hoyGuatemala } from "../services/compraValidation";
import { csvRotacion, validarRotacion } from "../services/rotacionValidation";
import type { ProductoRotacion } from "../services/rotacionValidation";
import "./Efectivo.css";
import "./Rotacion.css";

type Consulta = { desde: string; hasta: string; objetivo: number; busqueda: string; filtro: string; orden: string; pagina: number };
type Datos = {
  desde: string; hasta: string; dias: number; objetivo: number; fecha_stock: string;
  total: number; activos: number; con_ventas: number; sin_ventas: number; reponer: number;
  revisar: number; bajo_minimo: number; ventas_excluidas: number; productos: ProductoRotacion[];
};
const numero = (n: number, digitos = 2) => new Intl.NumberFormat("es-GT", { maximumFractionDigits: digitos }).format(n);
const dinero = (n: number) => new Intl.NumberFormat("es-GT", { style: "currency", currency: "GTQ" }).format(n);
const fecha = (s: string) => s.split("-").reverse().join("/");
const etiquetas = { REVISAR: "Revisar inventario", SIN_VENTAS: "Sin ventas", REPONER: "Reponer", SUFICIENTE: "Cobertura suficiente" };

export default function Rotacion({ activo, revision }: { activo: boolean; revision: number }) {
  const [consulta, setConsulta] = useState<Consulta>(() => {
    const hasta = hoyGuatemala();
    const desde = new Date(Date.parse(hasta) - 29 * 86400000).toISOString().slice(0, 10);
    return { desde, hasta, objetivo: 7, busqueda: "", filtro: "todos", orden: "reponer", pagina: 0 };
  });
  const [desde, setDesde] = useState(consulta.desde);
  const [hasta, setHasta] = useState(consulta.hasta);
  const [objetivo, setObjetivo] = useState(String(consulta.objetivo));
  const [busqueda, setBusqueda] = useState("");
  const [filtro, setFiltro] = useState("todos");
  const [orden, setOrden] = useState("reponer");
  const [datos, setDatos] = useState<Datos | null>(null);
  const [cargando, setCargando] = useState(true);
  const [error, setError] = useState("");
  const [errorFiltro, setErrorFiltro] = useState("");
  const [intento, setIntento] = useState(0);

  useEffect(() => {
    if (!activo) return;
    const controller = new AbortController();
    async function cargar() {
      if (!supabase) return;
      setCargando(true); setError("");
      try {
        const { data, error } = await supabase.rpc("obtener_rotacion_productos", {
          p_desde: consulta.desde, p_hasta: consulta.hasta, p_objetivo: consulta.objetivo,
          p_busqueda: consulta.busqueda, p_filtro: consulta.filtro, p_orden: consulta.orden, p_pagina: consulta.pagina,
        }).abortSignal(controller.signal);
        if (controller.signal.aborted) return;
        if (error || !Array.isArray(data?.productos) || !Number.isFinite(data?.total)) throw new Error();
        setDatos(data as Datos);
      } catch {
        if (!controller.signal.aborted) setError("No pudimos consultar la rotación. Comprueba tu conexión y vuelve a intentar.");
      } finally {
        if (!controller.signal.aborted) setCargando(false);
      }
    }
    void cargar();
    return () => controller.abort();
  }, [activo, revision, consulta, intento]);

  function consultar(e: FormEvent) {
    e.preventDefault(); setErrorFiltro("");
    try {
      const dias = validarRotacion(desde, hasta, objetivo);
      setConsulta({ desde, hasta, objetivo: dias, busqueda: busqueda.trim(), filtro, orden, pagina: 0 });
    } catch (e) { setErrorFiltro(e instanceof Error ? e.message : "Revisa los filtros."); }
  }
  function exportar() {
    if (!datos || cargando || error || !datos.productos.length) return;
    const url = URL.createObjectURL(new Blob([csvRotacion(datos.productos, datos.desde, datos.hasta, datos.objetivo, datos.fecha_stock)], { type: "text/csv;charset=utf-8" }));
    const a = document.createElement("a"); a.href = url;
    a.download = `rotacion_${datos.desde}_${datos.hasta}_pagina_${consulta.pagina + 1}.csv`;
    document.body.append(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(url), 0);
  }
  return <>
    <div className="section-heading">
      <div><p className="eyebrow">PLANIFICA EL REABASTECIMIENTO</p><h1>Rotación de productos</h1>
        <p className="muted">Compara las ventas registradas con las unidades disponibles hoy.</p></div>
      <button className="secondary" disabled={cargando} onClick={() => setIntento(v => v + 1)}>Actualizar rotación</button>
    </div>
    <form className="catalog-card purchase-panel rotacion-filtros" onSubmit={consultar}>
      <div><label htmlFor="rot-desde">Ventas desde</label><input id="rot-desde" type="date" required min="1900-01-01" max={hoyGuatemala()} value={desde} onChange={e => setDesde(e.target.value)} /></div>
      <div><label htmlFor="rot-hasta">Ventas hasta</label><input id="rot-hasta" type="date" required min="1900-01-01" max={hoyGuatemala()} value={hasta} onChange={e => setHasta(e.target.value)} /></div>
      <div><label htmlFor="rot-objetivo">Días que quieres cubrir</label><input id="rot-objetivo" inputMode="numeric" required value={objetivo} onChange={e => setObjetivo(e.target.value)} /></div>
      <div><label htmlFor="rot-busqueda">Nombre o código exacto</label><input id="rot-busqueda" maxLength={150} value={busqueda} onChange={e => setBusqueda(e.target.value)} /></div>
      <div><label htmlFor="rot-filtro">Mostrar</label><select id="rot-filtro" value={filtro} onChange={e => setFiltro(e.target.value)}>
        <option value="todos">Todos los activos</option><option value="reponer">Reponer según ventas</option><option value="sin_ventas">Sin ventas registradas</option><option value="revisar">Revisar inventario</option>
      </select></div>
      <div><label htmlFor="rot-orden">Ordenar por</label><select id="rot-orden" value={orden} onChange={e => setOrden(e.target.value)}>
        <option value="reponer">Prioridad de reposición</option><option value="mas">Más unidades vendidas</option><option value="menos">Menos unidades vendidas</option>
      </select></div>
      <button>Consultar rotación</button>
    </form>
    {errorFiltro && <p className="error" role="alert">{errorFiltro}</p>}
    {cargando ? <p className="state" role="status">Analizando ventas e inventario…</p> : error ?
      <div className="state"><p className="error" role="alert">{error}</p><button onClick={() => setIntento(v => v + 1)}>Reintentar</button></div> : datos && <>
      <p className="muted">Ventas: {fecha(datos.desde)} a {fecha(datos.hasta)} ({datos.dias} días naturales). Inventario actual consultado el {fecha(datos.fecha_stock)}. Objetivo: {datos.objetivo} días.</p>
      <div className="dashboard-grid">
        <article className="catalog-card dashboard-card"><h2>Productos activos</h2><strong>{datos.activos}</strong><p className="muted">{datos.con_ventas} con ventas en el período</p></article>
        <article className="catalog-card dashboard-card"><h2>Reponer según ventas</h2><strong>{datos.reponer}</strong><p className="muted">Para el objetivo o el mínimo actual</p></article>
        <article className="catalog-card dashboard-card"><h2>Sin ventas registradas</h2><strong>{datos.sin_ventas}</strong><p className="muted">No implica falta de demanda</p></article>
      </div>
      {datos.ventas_excluidas > 0 && <p className="dashboard-warning" role="status">Se excluyeron {datos.ventas_excluidas} ventas cuyos encabezados no coinciden con sus detalles. Revísalas en Resumen o Reportes.</p>}
      {datos.revisar > 0 && <p className="dashboard-warning" role="status">Hay {datos.revisar} productos con diferencias entre existencias y lotes. Sus sugerencias quedan sin calcular hasta revisar Inventario.</p>}
      <section className="catalog-card cobros-section" aria-label="Resultados de rotación">
        <div className="purchase-panel"><h2>Ventas y cobertura por producto</h2><p className="muted">Resumen de todo el catálogo activo: {datos.bajo_minimo} productos en el mínimo o por debajo. La tabla sigue tus filtros.</p>
          <button className="secondary" disabled={!datos.productos.length} onClick={exportar}>Exportar página CSV</button></div>
        {!datos.productos.length ? <p className="state">No hay productos en esta página para los filtros consultados.</p> :
        <div className="table-scroll" role="region" aria-label="Tabla de rotación" tabIndex={0}><table>
          <thead><tr><th>Producto</th><th className="numeric">Vendidas</th><th className="numeric">Importe</th><th className="numeric">Disponible hoy</th><th className="numeric">Promedio / día</th><th className="numeric">Cobertura</th><th className="numeric">Compra sugerida</th><th>Estado</th></tr></thead>
          <tbody>{datos.productos.map(p => <tr key={p.id_producto}>
            <td className="product-name">{p.nombre}<span className="history-date">{p.codigo_barras ?? "Sin código"} · Mínimo: {p.existencia_minima}</span>{p.vencido > 0 && <span className="history-date">{p.vencido} unidades vencidas excluidas</span>}</td>
            <td className="numeric">{numero(p.unidades, 0)}</td><td className="numeric">{dinero(p.importe)}</td>
            <td className="numeric">{p.inconsistente ? "Por revisar" : numero(p.disponible, 0)}</td>
            <td className="numeric">{p.unidades > 0 && p.promedio_diario < 0.01 ? "< 0.01" : numero(p.promedio_diario)}</td>
            <td className="numeric">{p.cobertura_dias === null ? "Sin cálculo" : `${numero(p.cobertura_dias)} días`}</td>
            <td className="numeric">{p.sugerencia === null ? "Sin cálculo" : `${numero(p.sugerencia, 0)} unidades`}</td>
            <td>{etiquetas[p.estado]}{p.bajo_minimo && <span className="history-date">En mínimo o por debajo</span>}</td>
          </tr>)}</tbody>
        </table></div>}
        <div className="pagination"><span>{datos.total ? `${Math.min(consulta.pagina * 20 + 1, datos.total)}–${Math.min(consulta.pagina * 20 + datos.productos.length, datos.total)} de ${datos.total}` : "0 productos"}</span>
          <div><button className="secondary" disabled={consulta.pagina === 0} onClick={() => setConsulta(c => ({ ...c, pagina: c.pagina - 1 }))}>Anterior</button>{" "}
          <button className="secondary" disabled={(consulta.pagina + 1) * 20 >= datos.total} onClick={() => setConsulta(c => ({ ...c, pagina: c.pagina + 1 }))}>Siguiente</button></div>
        </div>
      </section>
      <section className="catalog-card purchase-panel cobros-section">
        <h2>Cómo interpretar las sugerencias</h2>
        <p>El promedio divide las unidades vendidas entre todos los días del período, incluidos los días sin ventas. La cobertura divide el disponible actual entre ese promedio.</p>
        <p>La compra sugerida busca cubrir el objetivo y superar el mínimo registrado: toma la mayor de esas dos metas, redondea a unidades enteras y descuenta el disponible.</p>
        <p>Sin ventas registradas, la cobertura y la compra quedan sin calcular. Revisa si el producto es nuevo, estuvo agotado o faltan ventas por registrar antes de decidir.</p>
        <p>En productos por lote se excluye lo ya vencido; las unidades vigentes hoy pueden vencer antes del objetivo. Revisa Vencimientos en Resumen. Estas estimaciones no corrigen períodos de desabastecimiento ni predicen cambios de demanda.</p>
        <p className="muted">Revisa las cantidades y guárdalas en Lista de compras. Esta consulta no agrega partidas ni modifica existencias. El CSV contiene únicamente la página visible; importa los códigos de barras como texto para conservar ceros iniciales.</p>
      </section>
    </>}
  </>;
}
