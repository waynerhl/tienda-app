import { useEffect, useState } from "react";
import CostosReporte from "../components/CostosReporte";
import type { Costos } from "../components/CostosReporte";
import type { FormEvent } from "react";
import { supabase } from "../lib/supabase";
import { hoyGuatemala } from "../services/compraValidation";
import {
  validarPeriodo,
  csvVentasDiarias,
} from "../services/reporteValidation";
import type { DiaVentas } from "../services/reporteValidation";
import "./Efectivo.css";
import "./Reportes.css";
type ProductoReporte = {
  id_producto: number;
  nombre: string;
  codigo_barras: string | null;
  activo: boolean;
  existencia_actual: number;
  existencia_minima: number;
  unidades: number;
  importe: number;
};
type Reporte = {
  costos: Costos;
  desde: string;
  hasta: string;
  dias: number;
  actualizado: string;
  ventas: number;
  transacciones: number;
  ticket_promedio: number;
  unidades: number;
  productos_vendidos: number;
  activos_sin_ventas: number;
  ventas_credito: number;
  ventas_sin_credito: number;
  serie: DiaVentas[];
  top_unidades: ProductoReporte[];
  top_importe: ProductoReporte[];
  menor_venta: ProductoReporte[];
  por_pago: { nombre: string; transacciones: number; total: number }[];
  inconsistencias_total: number;
  inconsistencias: {
    id_venta: number;
    total: number;
    total_detalles: number;
  }[];
};
const dinero = (n: number) =>
  new Intl.NumberFormat("es-GT", { style: "currency", currency: "GTQ" }).format(
    Number(n),
  );
const fecha = (d: string) => d.split("-").reverse().join("/");
const hora = (s: string) =>
  new Intl.DateTimeFormat("es-GT", {
    timeZone: "America/Guatemala",
    dateStyle: "short",
    timeStyle: "short",
  }).format(new Date(s));
function TablaProductos({
  productos,
  label,
}: {
  productos: ProductoReporte[];
  label: string;
}) {
  if (!productos.length)
    return (
      <p className="state">No hay productos para mostrar en esta selección.</p>
    );
  return (
    <div className="table-scroll" tabIndex={0} role="region" aria-label={label}>
      <table>
        <thead>
          <tr>
            <th>Producto</th>
            <th className="numeric">Unidades vendidas</th>
            <th className="numeric">Importe vendido</th>
            <th className="numeric">Existencia actual</th>
            <th className="numeric">Mínimo actual</th>
          </tr>
        </thead>
        <tbody>
          {productos.map((p) => (
            <tr key={p.id_producto}>
              <td className="product-name">
                {p.nombre}
                {!p.activo && (
                  <span className="history-date">Actualmente inactivo</span>
                )}
              </td>
              <td className="numeric">{p.unidades}</td>
              <td className="numeric">{dinero(p.importe)}</td>
              <td className="numeric">{p.existencia_actual}</td>
              <td className="numeric">{p.existencia_minima}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
function Grafica({ serie }: { serie: DiaVentas[] }) {
  const max = Math.max(1, ...serie.map((d) => Number(d.total)));
  const x = (i: number) =>
    serie.length === 1 ? 380 : 10 + (i / (serie.length - 1)) * 740;
  const y = (n: number) => 170 - (Number(n) / max) * 150;
  return (
    <figure className="reporte-grafica">
      <div className="reporte-escala">
        <span>Importe diario (Q)</span>
        <span>Máximo de la escala: {dinero(max)}</span>
      </div>
      <svg
        viewBox="0 0 760 180"
        preserveAspectRatio="none"
        role="img"
        aria-label="Ventas diarias del período"
      >
        <line
          x1="10"
          y1="170"
          x2="750"
          y2="170"
          stroke="#c9d8cf"
          vectorEffect="non-scaling-stroke"
        />
        <polyline
          fill="none"
          stroke="#168466"
          strokeWidth="2"
          vectorEffect="non-scaling-stroke"
          points={serie.map((d, i) => `${x(i)},${y(d.total)}`).join(" ")}
        />
        {serie.map((d, i) => (
          <circle key={d.dia} cx={x(i)} cy={y(d.total)} r="2.5" fill="#146d53">
            <title>
              {fecha(d.dia)}: {dinero(d.total)} · {d.transacciones} ventas
            </title>
          </circle>
        ))}
      </svg>
      <figcaption>
        <span>{fecha(serie[0].dia)}</span>
        <span>{fecha(serie[serie.length - 1].dia)}</span>
      </figcaption>
    </figure>
  );
}
export default function Reportes({
  activo,
  revision,
}: {
  activo: boolean;
  revision: number;
}) {
  const [inicial] = useState(() => {
    const hoy = hoyGuatemala();
    return { desde: hoy.slice(0, 7) + "-01", hasta: hoy };
  });
  const [desde, setDesde] = useState(inicial.desde);
  const [hasta, setHasta] = useState(inicial.hasta);
  const [consulta, setConsulta] = useState(inicial);
  const [datos, setDatos] = useState<Reporte | null>(null);
  const [cargando, setCargando] = useState(true);
  const [error, setError] = useState("");
  const [errorFiltro, setErrorFiltro] = useState("");
  const [intento, setIntento] = useState(0);
  const [orden, setOrden] = useState<"unidades" | "importe">("unidades");
  useEffect(() => {
    if (!activo) return;
    const controller = new AbortController();
    async function cargar() {
      if (!supabase) return;
      setCargando(true);
      setError("");
      try {
        const r = await supabase
          .rpc("obtener_reporte_ventas_costos", {
            p_desde: consulta.desde,
            p_hasta: consulta.hasta,
          })
          .abortSignal(controller.signal);
        if (controller.signal.aborted) return;
        if (
          r.error ||
          r.data?.desde !== consulta.desde ||
          r.data?.hasta !== consulta.hasta ||
          !Array.isArray(r.data?.serie) ||
          !r.data.serie.length ||
          !Array.isArray(r.data?.costos?.mayores) ||
          !Array.isArray(r.data?.costos?.menores)
        )
          throw new Error();
        setDatos(r.data as Reporte);
      } catch {
        if (!controller.signal.aborted)
          setError("No pudimos generar el reporte. Comprueba la conexión.");
      } finally {
        if (!controller.signal.aborted) setCargando(false);
      }
    }
    void cargar();
    return () => controller.abort();
  }, [activo, revision, consulta, intento]);
  function consultar(e: FormEvent) {
    e.preventDefault();
    setErrorFiltro("");
    try {
      validarPeriodo(desde, hasta);
      setConsulta({ desde, hasta });
    } catch (e) {
      setErrorFiltro(e instanceof Error ? e.message : "Revisa el período.");
    }
  }
  function exportar() {
    if (!datos || cargando || error) return;
    const url = URL.createObjectURL(
      new Blob([csvVentasDiarias(datos.serie)], {
        type: "text/csv;charset=utf-8",
      }),
    );
    const a = document.createElement("a");
    a.href = url;
    a.download = `ventas_diarias_${datos.desde}_${datos.hasta}.csv`;
    document.body.append(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 0);
  }
  return (
    <>
      <div className="section-heading">
        <div>
          <p className="eyebrow">ANÁLISIS DE LA TIENDA</p>
          <h1>Reportes de ventas</h1>
          <p className="muted">
            Compara días y revisa qué productos se venden en cada período.
          </p>
        </div>
        <button
          className="secondary"
          disabled={cargando}
          onClick={() => setIntento((v) => v + 1)}
        >
          Actualizar reporte
        </button>
      </div>
      <form
        className="catalog-card purchase-panel reporte-filtro"
        onSubmit={consultar}
      >
        <div>
          <label htmlFor="reporte-desde">Desde</label>
          <input
            id="reporte-desde"
            type="date"
            min="1900-01-01"
            max={hoyGuatemala()}
            required
            value={desde}
            onChange={(e) => setDesde(e.target.value)}
          />
        </div>
        <div>
          <label htmlFor="reporte-hasta">Hasta</label>
          <input
            id="reporte-hasta"
            type="date"
            min="1900-01-01"
            max={hoyGuatemala()}
            required
            value={hasta}
            onChange={(e) => setHasta(e.target.value)}
          />
        </div>
        <button>Consultar período</button>
      </form>
      {errorFiltro && (
        <p className="error" role="alert">
          {errorFiltro}
        </p>
      )}
      {cargando ? (
        <p className="state" role="status">
          Generando reporte…
        </p>
      ) : error ? (
        <div>
          <p className="error" role="alert">
            {error}
          </p>
          <button onClick={() => setIntento((v) => v + 1)}>
            Reintentar reporte
          </button>
        </div>
      ) : (
        datos && (
          <section
            data-reporte-desde={datos.desde}
            data-reporte-hasta={datos.hasta}
          >
            <p className="footnote">
              Período consultado:{" "}
              <strong>
                {fecha(datos.desde)} al {fecha(datos.hasta)}
              </strong>{" "}
              · {datos.dias} días · Horario de Guatemala.
            </p>
            <div className="cash-grid">
              <article className="cash-stat">
                <span>Ventas registradas</span>
                <strong>{dinero(datos.ventas)}</strong>
                <small>Incluye ventas a crédito</small>
              </article>
              <article className="cash-stat">
                <span>Transacciones</span>
                <strong>{datos.transacciones}</strong>
              </article>
              <article className="cash-stat">
                <span>Ticket promedio</span>
                <strong>{dinero(datos.ticket_promedio)}</strong>
              </article>
              <article className="cash-stat">
                <span>Unidades vendidas</span>
                <strong>{datos.unidades}</strong>
                <small>{datos.productos_vendidos} productos distintos</small>
              </article>
            </div>
            {datos.inconsistencias_total > 0 && (
              <section className="dashboard-warning" role="alert">
                <strong>
                  Hay {datos.inconsistencias_total} ventas por revisar en este
                  período.
                </strong>
                <p>
                  Sus encabezados y detalles no coinciden o no tienen detalles.
                  Se excluyeron de los indicadores y rankings.
                </p>
                <ul>
                  {datos.inconsistencias.map((i) => (
                    <li key={i.id_venta}>
                      Venta #{i.id_venta}: encabezado {dinero(i.total)};
                      detalles {dinero(i.total_detalles)}.
                    </li>
                  ))}
                </ul>
                {datos.inconsistencias_total > datos.inconsistencias.length && (
                  <p>
                    Se muestran los primeros {datos.inconsistencias.length}{" "}
                    casos.
                  </p>
                )}
              </section>
            )}
            <section className="catalog-card purchase-panel cobros-section">
              <div className="section-heading">
                <h2>Ventas por día</h2>
                <button className="secondary" onClick={exportar}>
                  Descargar ventas diarias CSV
                </button>
              </div>
              <Grafica serie={datos.serie} />
              <details className="cobros-section">
                <summary>Ver detalle diario ({datos.dias} días)</summary>
                <div
                  className="table-scroll"
                  tabIndex={0}
                  role="region"
                  aria-label="Ventas diarias"
                >
                  <table>
                    <thead>
                      <tr>
                        <th>Fecha</th>
                        <th className="numeric">Importe vendido</th>
                        <th className="numeric">Transacciones</th>
                        <th className="numeric">Unidades</th>
                      </tr>
                    </thead>
                    <tbody>
                      {datos.serie.map((d) => (
                        <tr key={d.dia}>
                          <td>{fecha(d.dia)}</td>
                          <td className="numeric">{dinero(d.total)}</td>
                          <td className="numeric">{d.transacciones}</td>
                          <td className="numeric">{d.unidades}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </details>
            </section>
            <CostosReporte datos={datos.costos} />
            <section className="catalog-card cobros-section">
              <div className="purchase-panel">
                <h2>Productos destacados del período</h2>
                <label htmlFor="reporte-orden">Ordenar por</label>
                <select
                  id="reporte-orden"
                  value={orden}
                  onChange={(e) =>
                    setOrden(e.target.value as "unidades" | "importe")
                  }
                >
                  <option value="unidades">Mayor cantidad vendida</option>
                  <option value="importe">Mayor importe vendido</option>
                </select>
                <p className="footnote">
                  Primeros 20. Existencias y mínimos corresponden al catálogo
                  actual.
                </p>
              </div>
              <TablaProductos
                productos={
                  orden === "unidades" ? datos.top_unidades : datos.top_importe
                }
                label="Productos más vendidos"
              />
            </section>
            <section className="catalog-card cobros-section">
              <div className="purchase-panel">
                <h2>Catálogo activo con menor venta</h2>
                <p className="muted">
                  {datos.activos_sin_ventas} productos actualmente activos no
                  tienen ventas registradas en este período.
                </p>
                <p className="footnote">
                  Primeros 20, de menor a mayor cantidad vendida. Revisa cuándo
                  incorporaste cada producto antes de decidir reponerlo.
                </p>
              </div>
              <TablaProductos
                productos={datos.menor_venta}
                label="Productos con menor venta"
              />
            </section>
            <section className="catalog-card cobros-section">
              <div className="purchase-panel">
                <h2>Forma de pago registrada en las ventas</h2>
                <p className="muted">
                  A crédito: {dinero(datos.ventas_credito)} · Sin crédito:{" "}
                  {dinero(datos.ventas_sin_credito)}
                </p>
              </div>
              {!datos.por_pago.length ? (
                <p className="state">
                  No hay ventas registradas en este período.
                </p>
              ) : (
                <div
                  className="table-scroll"
                  tabIndex={0}
                  role="region"
                  aria-label="Ventas por forma de pago"
                >
                  <table>
                    <thead>
                      <tr>
                        <th>Forma de pago</th>
                        <th className="numeric">Transacciones</th>
                        <th className="numeric">Importe vendido</th>
                      </tr>
                    </thead>
                    <tbody>
                      {datos.por_pago.map((p) => (
                        <tr key={p.nombre}>
                          <td>{p.nombre}</td>
                          <td className="numeric">{p.transacciones}</td>
                          <td className="numeric">{dinero(p.total)}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </section>
            <p className="inventory-note">
              Este reporte mide ventas registradas. Los abonos a deudas no
              vuelven a sumarse como ventas; el dinero en efectivo y el conteo
              físico se revisan en Efectivo y Caja.
            </p>
            <p className="footnote">Actualizado: {hora(datos.actualizado)}.</p>
          </section>
        )
      )}
    </>
  );
}
