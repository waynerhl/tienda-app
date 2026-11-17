import { useEffect, useState } from "react";
import { supabase } from "../lib/supabase";
import { hoyGuatemala } from "../services/compraValidation";
import "./Efectivo.css";

type Movimiento = {
  tipo: "VENTA" | "COBRO_CLIENTE" | "COMPRA" | "PAGO_PROVEEDOR";
  id: number;
  fecha: string;
  contraparte: string;
  referencia: string;
  entrada: number;
  salida: number;
};
type Flujo = {
  fecha: string;
  actualizado: string;
  entradas: number;
  salidas: number;
  variacion: number;
  total_movimientos: number;
  ventas_efectivo: number;
  cobros_clientes: number;
  compras_efectivo: number;
  pagos_proveedores: number;
  movimientos: Movimiento[];
  inconsistencias_total: number;
  inconsistencias: { tipo: string; id: number; referencia: string }[];
};
const dinero = (n: number) =>
  new Intl.NumberFormat("es-GT", { style: "currency", currency: "GTQ" }).format(
    Number(n),
  );
const hora = (d: string) =>
  new Intl.DateTimeFormat("es-GT", {
    timeZone: "America/Guatemala",
    dateStyle: "short",
    timeStyle: "short",
  }).format(new Date(d));
const conceptos: Record<Movimiento["tipo"], string> = {
  VENTA: "Venta en efectivo",
  COBRO_CLIENTE: "Cobro a cliente",
  COMPRA: "Compra en efectivo",
  PAGO_PROVEEDOR: "Pago a proveedor",
};

export default function Efectivo({
  activo,
  revision,
}: {
  activo: boolean;
  revision: number;
}) {
  const [consulta, setConsulta] = useState(() => ({
    fecha: hoyGuatemala(),
    pagina: 0,
  }));
  const [datos, setDatos] = useState<Flujo | null>(null);
  const [cargando, setCargando] = useState(true);
  const [error, setError] = useState("");
  const [intento, setIntento] = useState(0);
  useEffect(() => {
    if (!activo) return;
    const controller = new AbortController();
    async function cargar() {
      if (!supabase) return;
      setCargando(true);
      setError("");
      try {
        const r = await supabase
          .rpc("obtener_flujo_efectivo", {
            p_fecha: consulta.fecha,
            p_pagina: consulta.pagina,
          })
          .abortSignal(controller.signal);
        if (controller.signal.aborted) return;
        if (
          r.error ||
          r.data?.fecha !== consulta.fecha ||
          !Array.isArray(r.data?.movimientos)
        )
          throw new Error();
        setDatos(r.data as Flujo);
      } catch {
        if (!controller.signal.aborted)
          setError(
            "No pudimos consultar el efectivo. Revisa la conexión y vuelve a intentar.",
          );
      } finally {
        if (!controller.signal.aborted) setCargando(false);
      }
    }
    void cargar();
    return () => controller.abort();
  }, [activo, revision, consulta, intento]);
  return (
    <>
      <div className="section-heading">
        <div>
          <p className="eyebrow">DINERO REGISTRADO EN LA TIENDA</p>
          <h1>Efectivo del día</h1>
          <p className="muted">
            Entradas y salidas por ventas, compras y abonos.
          </p>
        </div>
        <button
          className="secondary"
          disabled={cargando}
          onClick={() => setIntento((v) => v + 1)}
        >
          Actualizar
        </button>
      </div>
      <div className="catalog-card search-form cash-filter">
        <label htmlFor="efectivo-fecha">Fecha (horario de Guatemala)</label>
        <input
          id="efectivo-fecha"
          type="date"
          min="1900-01-01"
          max={hoyGuatemala()}
          value={consulta.fecha}
          onChange={(e) => {
            const fecha = e.target.value;
            if (/^\d{4}-\d{2}-\d{2}$/.test(fecha))
              setConsulta({ fecha, pagina: 0 });
          }}
        />
      </div>
      <p className="inventory-note">
        Esta vista incluye únicamente pagos en EFECTIVO. La variación es
        entradas menos salidas registradas; no representa la ganancia ni el
        dinero disponible en caja. Aún falta incorporar apertura, gastos,
        retiros personales y arqueo.
      </p>
      {cargando ? (
        <p className="state" role="status">
          Consultando movimientos…
        </p>
      ) : error ? (
        <div>
          <p className="error" role="alert">
            {error}
          </p>
          <button onClick={() => setIntento((v) => v + 1)}>Reintentar</button>
        </div>
      ) : (
        datos && (
          <section aria-label="Flujo de efectivo" data-fecha={datos.fecha}>
            <div className="cash-grid">
              <article className="cash-stat">
                <span>Entradas de efectivo</span>
                <strong>{dinero(datos.entradas)}</strong>
                <small>Ventas y abonos de clientes</small>
              </article>
              <article className="cash-stat">
                <span>Salidas de efectivo</span>
                <strong>{dinero(datos.salidas)}</strong>
                <small>Compras y pagos a proveedores</small>
              </article>
              <article className="cash-stat">
                <span>Variación registrada</span>
                <strong>{dinero(datos.variacion)}</strong>
                <small>Entradas menos salidas</small>
              </article>
              <article className="cash-stat">
                <span>Movimientos</span>
                <strong>{datos.total_movimientos}</strong>
                <small>Operaciones en efectivo del día</small>
              </article>
            </div>
            {datos.inconsistencias_total > 0 && (
              <div className="dashboard-warning" role="alert">
                <strong>
                  Hay {datos.inconsistencias_total} movimientos por revisar.
                </strong>
                <p>
                  Sus documentos o cuentas no coinciden con los registros
                  relacionados. Se excluyeron de los totales de esta vista.
                </p>
                <ul>
                  {datos.inconsistencias.map((x) => (
                    <li key={`${x.tipo}-${x.id}`}>{x.referencia}</li>
                  ))}
                </ul>
                {datos.inconsistencias_total > datos.inconsistencias.length && (
                  <p>
                    Se muestran los primeros {datos.inconsistencias.length}{" "}
                    casos.
                  </p>
                )}
              </div>
            )}
            <section className="catalog-card cobros-section purchase-panel">
              <h2>De dónde viene y a dónde va</h2>
              <dl className="cash-breakdown">
                <div>
                  <dt>Ventas cobradas en efectivo</dt>
                  <dd>{dinero(datos.ventas_efectivo)}</dd>
                </div>
                <div>
                  <dt>Abonos recibidos de clientes</dt>
                  <dd>{dinero(datos.cobros_clientes)}</dd>
                </div>
                <div>
                  <dt>Compras pagadas en efectivo</dt>
                  <dd>{dinero(datos.compras_efectivo)}</dd>
                </div>
                <div>
                  <dt>Pagos entregados a proveedores</dt>
                  <dd>{dinero(datos.pagos_proveedores)}</dd>
                </div>
              </dl>
              <p className="footnote">
                Una venta a crédito entra en este flujo cuando recibes un abono
                en efectivo, en la fecha de ese abono.
              </p>
            </section>
            <section
              className="catalog-card cobros-section"
              aria-label="Movimientos del día"
            >
              <div className="purchase-panel">
                <h2>Detalle de movimientos</h2>
                <p className="muted">
                  Los totales incluyen todas las páginas del día seleccionado.
                </p>
              </div>
              {!datos.movimientos.length ? (
                <p className="state">No hay movimientos en esta página.</p>
              ) : (
                <div
                  className="table-scroll"
                  tabIndex={0}
                  role="region"
                  aria-label="Movimientos de efectivo"
                >
                  <table>
                    <thead>
                      <tr>
                        <th>Fecha y hora</th>
                        <th>Concepto</th>
                        <th>Cliente / proveedor</th>
                        <th>Referencia</th>
                        <th className="numeric">Entrada</th>
                        <th className="numeric">Salida</th>
                      </tr>
                    </thead>
                    <tbody>
                      {datos.movimientos.map((m) => (
                        <tr key={`${m.tipo}-${m.id}`}>
                          <td>{hora(m.fecha)}</td>
                          <td>{conceptos[m.tipo]}</td>
                          <td>{m.contraparte}</td>
                          <td>{m.referencia}</td>
                          <td className="numeric">
                            {Number(m.entrada) > 0 ? dinero(m.entrada) : "—"}
                          </td>
                          <td className="numeric">
                            {Number(m.salida) > 0 ? dinero(m.salida) : "—"}
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
              <div className="pagination">
                <span>
                  {datos.movimientos.length
                    ? `${consulta.pagina * 20 + 1}–${Math.min((consulta.pagina + 1) * 20, datos.total_movimientos)} de ${datos.total_movimientos}`
                    : datos.total_movimientos
                      ? "Sin movimientos en esta página"
                      : "Sin movimientos registrados"}
                </span>
                <div>
                  <button
                    className="secondary"
                    disabled={consulta.pagina === 0}
                    onClick={() =>
                      setConsulta((v) => ({ ...v, pagina: v.pagina - 1 }))
                    }
                  >
                    Anterior
                  </button>
                  <button
                    className="secondary"
                    disabled={
                      (consulta.pagina + 1) * 20 >= datos.total_movimientos
                    }
                    onClick={() =>
                      setConsulta((v) => ({ ...v, pagina: v.pagina + 1 }))
                    }
                  >
                    Siguiente
                  </button>
                </div>
              </div>
            </section>
            <p className="footnote">
              Actualizado: {hora(datos.actualizado)} · Horario de Guatemala.
            </p>
          </section>
        )
      )}
    </>
  );
}
