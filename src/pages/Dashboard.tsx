import { useEffect, useState } from "react";
import { supabase } from "../lib/supabase";

type Datos = {
  fecha: string;
  actualizado: string;
  ventas_hoy: number;
  transacciones_hoy: number;
  ticket_promedio: number;
  productos_activos: number;
  agotados: number;
  bajo_minimo: number;
  lotes_proximos: number;
  lotes_vencidos: number;
  por_cobrar: number;
  por_cobrar_vencido: number;
  por_pagar: number;
  por_pagar_vencido: number;
  ventas_inconsistentes: number;
  serie: {
    dia: string;
    total: number;
    transacciones: number;
  }[];
  reponer: {
    id_producto: number;
    nombre: string;
    existencia: number;
    existencia_minima: number;
  }[];
  vencimientos: {
    id_lote: number;
    numero_lote: string | null;
    producto: string;
    fecha_vencimiento: string;
    existencia: number;
    dias: number;
  }[];
  inconsistencias: {
    id_venta: number;
    total: number;
    total_detalles: number;
  }[];
};

const moneda = new Intl.NumberFormat("es-GT", {
  style: "currency",
  currency: "GTQ",
});

const fechaCorta = (fecha: string) =>
  fecha.split("-").reverse().join("/");

export default function Dashboard({
  activo,
  revision,
}: {
  activo: boolean;
  revision: number;
}) {
  const [datos, setDatos] = useState<Datos | null>(null);
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
        const { data, error } = await supabase
          .rpc("obtener_dashboard")
          .abortSignal(controller.signal);

        if (controller.signal.aborted) return;
        if (error) throw error;

        if (!data || !Array.isArray(data.serie)) {
          throw new Error("Respuesta incompleta");
        }

        setDatos(data as Datos);
      } catch {
        if (!controller.signal.aborted) {
          setDatos(null);
          setError(
            "No pudimos cargar el dashboard. Comprueba la conexión y vuelve a intentar.",
          );
        }
      } finally {
        if (!controller.signal.aborted) setCargando(false);
      }
    }

    void cargar();
    return () => controller.abort();
  }, [activo, revision, intento]);

  if (cargando) {
    return <p className="state" role="status">Cargando resumen…</p>;
  }

  if (error || !datos) {
    return (
      <div className="catalog-card purchase-panel">
        <p className="error" role="alert">
          {error || "No se recibieron datos."}
        </p>
        <button onClick={() => setIntento((v) => v + 1)}>
          Reintentar
        </button>
      </div>
    );
  }

  const maximo = Math.max(
    1,
    ...datos.serie.map((dia) => Number(dia.total)),
  );

  const tarjetas = [
    {
      titulo: "Ventas de hoy",
      valor: moneda.format(Number(datos.ventas_hoy)),
      detalle: datos.transacciones_hoy + " transacciones",
    },
    {
      titulo: "Ticket promedio",
      valor: moneda.format(Number(datos.ticket_promedio)),
      detalle: "Venta promedio por transacción",
    },
    {
      titulo: "Productos por reponer",
      valor: String(datos.agotados + datos.bajo_minimo),
      detalle:
        datos.agotados + " agotados · " +
        datos.bajo_minimo + " con existencia baja",
    },
    {
      titulo: "Lotes próximos a vencer",
      valor: String(datos.lotes_proximos),
      detalle:
        "Próximos 30 días · " +
        datos.lotes_vencidos + " lotes ya vencidos",
    },
    {
      titulo: "Por cobrar",
      valor: moneda.format(Number(datos.por_cobrar)),
      detalle:
        "Vencido: " +
        moneda.format(Number(datos.por_cobrar_vencido)),
    },
    {
      titulo: "Por pagar",
      valor: moneda.format(Number(datos.por_pagar)),
      detalle:
        "Vencido: " +
        moneda.format(Number(datos.por_pagar_vencido)),
    },
  ];

  return (
    <section aria-labelledby="dashboard-title">
      <div className="section-heading">
        <div>
          <p className="eyebrow">RESUMEN DE LA TIENDA</p>
          <h1 id="dashboard-title">Tu tienda de un vistazo</h1>
          <p className="muted">
            {fechaCorta(datos.fecha)} · Horario de Guatemala
          </p>
        </div>
        <button
          className="secondary"
          onClick={() => setIntento((v) => v + 1)}
        >
          Actualizar
        </button>
      </div>

      <div className="dashboard-grid">
        {tarjetas.map((tarjeta) => (
          <article className="catalog-card dashboard-card"
            key={tarjeta.titulo}>
            <h2>{tarjeta.titulo}</h2>
            <strong>{tarjeta.valor}</strong>
            <p className="muted">{tarjeta.detalle}</p>
          </article>
        ))}
      </div>

      {datos.ventas_inconsistentes > 0 && (
        <section className="dashboard-warning" role="status">
          <strong>Hay registros de ventas por revisar.</strong>
          <p>
            {datos.ventas_inconsistentes} ventas registradas no
            coinciden con sus detalles. Están excluidas de los
            indicadores de ventas de este panel.
          </p>
          <ul>
            {datos.inconsistencias.map((venta) => (
              <li key={venta.id_venta}>
                Venta #{venta.id_venta}: encabezado{" "}
                {moneda.format(Number(venta.total))};
                detalles{" "}
                {moneda.format(Number(venta.total_detalles))}.
              </li>
            ))}
          </ul>
        </section>
      )}

      <section className="catalog-card purchase-panel">
        <h2>Ventas de los últimos siete días</h2>
        <ul className="dashboard-bars">
          {datos.serie.map((dia) => (
            <li key={dia.dia}>
              <span>{fechaCorta(dia.dia)}</span>
              <div className="dashboard-bar-track" aria-hidden="true">
                <div
                  className="dashboard-bar"
                  style={{
                    width:
                      (Number(dia.total) / maximo) * 100 + "%",
                  }}
                />
              </div>
              <strong>
                {moneda.format(Number(dia.total))}
              </strong>
            </li>
          ))}
        </ul>
        <p className="footnote">
          Las ventas incluyen operaciones a crédito.
          Este importe no representa el efectivo disponible en caja.
        </p>
      </section>

      <section className="catalog-card purchase-history">
        <div className="purchase-panel">
          <h2>Prioridad de reabastecimiento</h2>
          <p className="muted">
            Primeros 20 productos que alcanzaron su mínimo.
          </p>
        </div>

        {datos.reponer.length === 0 ? (
          <p className="state">
            No hay productos activos que requieran reposición
            según los mínimos registrados.
          </p>
        ) : (
          <div className="table-scroll">
            <table>
              <thead>
                <tr>
                  <th>Producto</th>
                  <th>Existencia</th>
                  <th>Mínimo</th>
                  <th>Situación</th>
                </tr>
              </thead>
              <tbody>
                {datos.reponer.map((producto) => (
                  <tr key={producto.id_producto}>
                    <td>{producto.nombre}</td>
                    <td>{producto.existencia}</td>
                    <td>{producto.existencia_minima}</td>
                    <td>
                      <span className="badge low">
                        {producto.existencia === 0
                          ? "Agotado"
                          : "Stock bajo"}
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section className="catalog-card purchase-history">
        <div className="purchase-panel">
          <h2>Vencimientos que requieren atención</h2>
          <p className="muted">
            Primeros 20 lotes con unidades disponibles,
            vencidos o que vencen en los próximos 30 días.
          </p>
        </div>

        {datos.vencimientos.length === 0 ? (
          <p className="state">
            No hay lotes con vencimientos en este rango.
          </p>
        ) : (
          <div className="table-scroll">
            <table>
              <thead>
                <tr>
                  <th>Producto / lote</th>
                  <th>Unidades</th>
                  <th>Vencimiento</th>
                  <th>Situación</th>
                </tr>
              </thead>
              <tbody>
                {datos.vencimientos.map((lote) => (
                  <tr key={lote.id_lote}>
                    <td>
                      {lote.producto}
                      <small className="history-date">
                        {lote.numero_lote || "Sin número"}
                      </small>
                    </td>
                    <td>{lote.existencia}</td>
                    <td>{fechaCorta(lote.fecha_vencimiento)}</td>
                    <td>
                      <span className="badge low">
                        {lote.dias < 0
                          ? "Vencido"
                          : lote.dias === 0
                            ? "Vence hoy"
                            : "En " + lote.dias + " días"}
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <p className="footnote">
        Productos activos: {datos.productos_activos}.
        {" "}Actualizado a las{" "}
        {new Intl.DateTimeFormat("es-GT", {
          timeZone: "America/Guatemala",
          hour: "2-digit",
          minute: "2-digit",
        }).format(new Date(datos.actualizado))}.
      </p>
    </section>
  );
}