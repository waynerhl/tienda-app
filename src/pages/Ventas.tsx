import { patronBusquedaNombre } from "../services/busquedas";
import { useEffect, useRef, useState } from "react";
import type { FormEvent } from "react";
import { supabase } from "../lib/supabase";
import {
  cantidadEntera,
  costoCentavos,
  hoyGuatemala,
} from "../services/compraValidation";

import { calcularPresentacion, tienePaquete } from "../services/presentacionValidation";
import type { PrecioPresentacion } from "../services/presentacionValidation";

type Producto = PrecioPresentacion & {
  id_producto: number;
  nombre: string;
  codigo_barras: string | null;
  precio_venta: number;
  existencia: number;
};

type Linea = { producto: Producto; cantidad: string };
type Pago = { id_forma_pago: number; nombre: string };
type Cliente = { id_cliente: number; nombre: string };

type Payload = {
  p_solicitud_id: string;
  p_cliente_id: number | null;
  p_forma_pago_id: number;
  p_fecha_limite: string | null;
  p_items: {
    producto_id: number;
    cantidad: number;
    precio_esperado: number;
    paquete_version_esperada?: number;
  }[];
};

type Venta = {
  id_venta: number;
  total: number;
  estado: string;
  fecha?: string;
};

const moneda = new Intl.NumberFormat("es-GT", {
  style: "currency",
  currency: "GTQ",
});

function totalCentavos(lineas: Linea[]) {
  let total = 0;
  for (const linea of lineas) {
    total += calcularPresentacion(linea.producto, linea.cantidad).centavos;
    if (!Number.isSafeInteger(total) || total > 999999999999) {
      throw new Error("El total supera el máximo permitido.");
    }
  }
  return total;
}

function recuperar(clave: string): {
  payload: Payload | null;
  error: string;
} {
  try {
    const texto = localStorage.getItem(clave);
    if (!texto) return { payload: null, error: "" };

    const p = JSON.parse(texto) as Payload;
    if (
      !p ||
      typeof p.p_solicitud_id !== "string" ||
      !Number.isInteger(p.p_forma_pago_id) ||
      !Array.isArray(p.p_items) ||
      p.p_items.length === 0 ||
      !p.p_items.every(
        (item) =>
          item &&
          Number.isInteger(item.producto_id) &&
          Number.isInteger(item.cantidad) &&
          item.cantidad > 0 &&
          Number.isFinite(item.precio_esperado) &&
          (item.paquete_version_esperada === undefined || (Number.isSafeInteger(item.paquete_version_esperada) && item.paquete_version_esperada >= 0)),
      )
    ) {
      throw new Error("Borrador inválido");
    }
    return { payload: p, error: "" };
  } catch {
    return {
      payload: null,
      error:
        "No pudimos recuperar una operación pendiente. Revisa el historial antes de preparar otra venta.",
    };
  }
}

function DesglosePresentacion({ producto, cantidad }: { producto: Producto; cantidad: string }) {
  let d: ReturnType<typeof calcularPresentacion> | null = null;
  try { d = calcularPresentacion(producto,cantidad); } catch { /* Cantidad incompleta mientras se escribe. */ }
  if (!d) return <p className="muted">Completa una cantidad válida para calcular el importe.</p>;
  return <p className="inventory-note">{tienePaquete(producto) ? `${d.paquetes} × ${producto.paquete_nombre} de ${producto.paquete_unidades} + ${d.sueltas} unidades sueltas` : `${d.unidades} unidades`} · <strong>{moneda.format(d.centavos / 100)}</strong></p>;
}

export default function Ventas({
  userId,
  revisionExterna,
  onRegistered,
}: {
  userId: string;
  revisionExterna: number;
  onRegistered: () => void;
}) {
  const clave = "tienda:venta-pendiente:" + userId;
  const [recuperado] = useState(() => recuperar(clave));
  const [pendiente, setPendiente] = useState<Payload | null>(
    recuperado.payload,
  );

  const [productos, setProductos] = useState<Producto[]>([]);
  const [clientes, setClientes] = useState<Cliente[]>([]);
  const [pagos, setPagos] = useState<Pago[]>([]);
  const [historial, setHistorial] = useState<Venta[]>([]);
  const [lineas, setLineas] = useState<Linea[]>([]);
  const [cliente, setCliente] = useState("");
  const [pago, setPago] = useState("");
  const [fecha, setFecha] = useState("");
  const [recibido, setRecibido] = useState("");
  const [busqueda, setBusqueda] = useState("");
  const [modo, setModo] = useState("nombre");
  const [consulta, setConsulta] = useState({
    texto: "",
    modo: "nombre",
  });
  const [revision, setRevision] = useState(0);
  const [cargando, setCargando] = useState(true);
  const [errorCarga, setErrorCarga] = useState("");
  const [error, setError] = useState("");
  const [guardando, setGuardando] = useState(false);
  const [confirmada, setConfirmada] = useState<Venta | null>(null);
  const bloqueo = useRef(false);

  useEffect(() => {
    const controller = new AbortController();

    async function cargar() {
      if (!supabase) return;
      setCargando(true);
      setErrorCarga("");

      try {
        let query = supabase
          .from("productos")
          .select(
            "id_producto,nombre,codigo_barras,precio_venta,existencia,paquete_nombre,paquete_unidades,paquete_precio,paquete_predeterminado,paquete_version",
          )
          .eq("activo", true)
          .order("nombre")
          .order("id_producto")
          .limit(20);

        if (consulta.texto) {
          query =
            consulta.modo === "codigo_barras"
              ? query.eq("codigo_barras", consulta.texto)
              : query.ilike(
                  "nombre_busqueda", patronBusquedaNombre(consulta.texto),
                );
        }

        const [pr, cl, pa, ve] = await Promise.all([
          query.abortSignal(controller.signal),
          supabase
            .from("clientes")
            .select("id_cliente,nombre")
            .order("nombre")
            .limit(1000)
            .abortSignal(controller.signal),
          supabase
            .from("formas_pago")
            .select("id_forma_pago,nombre")
            .order("nombre")
            .abortSignal(controller.signal),
          supabase
            .from("ventas")
            .select("id_venta,total,estado,fecha")
            .order("fecha", { ascending: false })
            .order("id_venta", { ascending: false })
            .limit(20)
            .abortSignal(controller.signal),
        ]);

        if (controller.signal.aborted) return;
        if (pr.error || cl.error || pa.error || ve.error) {
          throw new Error("Carga incompleta");
        }

        setProductos((pr.data ?? []) as Producto[]);
        setClientes(cl.data ?? []);
        setPagos(pa.data ?? []);
        setHistorial((ve.data ?? []) as Venta[]);
      } catch {
        if (!controller.signal.aborted) {
          setErrorCarga(
            "No pudimos actualizar los datos. Comprueba la conexión y vuelve a intentar.",
          );
        }
      } finally {
        if (!controller.signal.aborted) setCargando(false);
      }
    }

    void cargar();
    return () => controller.abort();
  }, [consulta, revision, revisionExterna]);

  const metodo = pagos.find(
    (p) => String(p.id_forma_pago) === pago,
  );
  const esCredito = metodo?.nombre === "CREDITO";
  const esEfectivo = metodo?.nombre === "EFECTIVO";
  const bloqueado =
    guardando || pendiente !== null || !!recuperado.error;

  let total: number | null = null;
  let cambio: number | null = null;

  try {
    total = totalCentavos(lineas);
    if (esEfectivo && recibido.trim()) {
      cambio = costoCentavos(recibido) - total;
    }
  } catch {
    // Se completará cuando las cantidades y el efectivo sean válidos.
  }

  function agregar(producto: Producto, incremento?: number) {
    const paso = incremento ?? (tienePaquete(producto) && producto.paquete_predeterminado ? Number(producto.paquete_unidades) : 1);
    if (bloqueado) return;

    const actual = lineas.find(
      (l) => l.producto.id_producto === producto.id_producto,
    );
    const cantidad = actual
      ? Number(actual.cantidad || 0) + paso
      : paso;

    if (cantidad > producto.existencia) {
      setError("No hay suficiente existencia registrada.");
      return;
    }

    setError("");
    setLineas(
      actual
        ? lineas.map((l) =>
            l.producto.id_producto === producto.id_producto
              ? { producto, cantidad: String(cantidad) }
              : l,
          )
        : [...lineas, { producto, cantidad: String(cantidad) }],
    );
  }

  function limpiarPendiente() {
    localStorage.removeItem(clave);
    setPendiente(null);
  }

  async function cobrar(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!supabase || bloqueo.current || recuperado.error) return;
    if (!pendiente && (cargando || errorCarga)) return;

    setError("");
    let payload = pendiente;

    if (!payload) {
      try {
        if (!lineas.length) throw new Error("Agrega productos.");
        if (!metodo) throw new Error("Selecciona la forma de pago.");
        if (esCredito && !cliente) {
          throw new Error("Una venta a crédito requiere un cliente.");
        }
        if (
          esCredito &&
          fecha &&
          (fecha < hoyGuatemala() ||
            !Number.isFinite(Date.parse(fecha)))
        ) {
          throw new Error("Revisa la fecha límite de pago.");
        }

        const suma = totalCentavos(lineas);

        if (esCredito && suma === 0) {
          throw new Error("El crédito requiere un total mayor que cero.");
        }
        if (esEfectivo) {
          if (!recibido.trim()) {
            throw new Error("Indica cuánto efectivo recibiste.");
          }
          if (costoCentavos(recibido) < suma) {
            throw new Error("El efectivo recibido es insuficiente.");
          }
        }

        const items = lineas.map((linea) => {
          const cantidad = cantidadEntera(linea.cantidad);
          if (cantidad > linea.producto.existencia) {
            throw new Error(
              "Revisa la existencia de " + linea.producto.nombre,
            );
          }
          return {
            producto_id: linea.producto.id_producto,
            cantidad,
            precio_esperado: Number(linea.producto.precio_venta),
            paquete_version_esperada: linea.producto.paquete_version ?? 0,
          };
        });

        payload = {
          p_solicitud_id: crypto.randomUUID(),
          p_cliente_id: cliente ? Number(cliente) : null,
          p_forma_pago_id: metodo.id_forma_pago,
          p_fecha_limite: esCredito && fecha ? fecha : null,
          p_items: items,
        };

        // Conservar la misma solicitud permite reintentar sin duplicar.
        localStorage.setItem(clave, JSON.stringify(payload));
        setPendiente(payload);
      } catch (err) {
        setError(
          err instanceof Error
            ? err.message
            : "Revisa los datos antes de cobrar.",
        );
        return;
      }
    }

    bloqueo.current = true;
    setGuardando(true);

    try {
      const { data, error: rpcError } = await supabase.rpc(
        "registrar_venta_segura",
        payload,
      );

      if (rpcError) {
        const rechazoConfirmado = [
          "22023",
          "22003",
          "22P02",
          "42501",
          "23503",
          "23514",
          "P0001",
        ].includes(rpcError.code);

        if (rechazoConfirmado) limpiarPendiente();

        setError(
          rechazoConfirmado
            ? rpcError.message
            : "No se confirmó la respuesta. Reintenta la confirmación: se usará la misma operación.",
        );
        return;
      }

      if (
        !data ||
        !Number.isInteger(data.id_venta) ||
        !Number.isFinite(Number(data.total))
      ) {
        throw new Error("Respuesta incompleta");
      }

      limpiarPendiente();
      setConfirmada(data as Venta);
      setLineas([]);
      setRecibido("");
      setFecha("");
      setRevision((v) => v + 1);
      onRegistered();
    } catch {
      setError(
        "No pudimos confirmar la respuesta. Reintenta la confirmación con la misma operación.",
      );
    } finally {
      bloqueo.current = false;
      setGuardando(false);
    }
  }

  function buscar(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setConsulta({ texto: busqueda.trim(), modo });
  }

  return (
    <section aria-labelledby="ventas-title">
      <div className="section-heading">
        <div>
          <p className="eyebrow">SALIDA DE MERCADERÍA</p>
          <h1 id="ventas-title">Ventas</h1>
          <p className="muted">
            Prepara el carrito y confirma el cobro.
          </p>
        </div>
        <button
          className="secondary"
          disabled={cargando || guardando}
          onClick={() => setRevision((v) => v + 1)}
        >
          Actualizar datos
        </button>
      </div>

      {confirmada && (
        <p className="success" role="status">
          Última venta confirmada: #{confirmada.id_venta} por{" "}
          {moneda.format(Number(confirmada.total))}.
        </p>
      )}

      {(errorCarga || recuperado.error) && (
        <p className="error" role="alert">
          {recuperado.error || errorCarga}
        </p>
      )}

      {pendiente ? (
        <div className="catalog-card purchase-panel">
          <h2>Venta pendiente de confirmación</h2>
          <p>
            Conservamos la operación para comprobarla o reintentar
            sin descontar inventario dos veces.
          </p>
          <p className="footnote">
            Referencia: {pendiente.p_solicitud_id}
          </p>
          <form onSubmit={cobrar}>
            <button disabled={guardando}>
              {guardando
                ? "Confirmando…"
                : "Reintentar confirmación"}
            </button>
          </form>
        </div>
      ) : (
        <>
          <div className="catalog-card purchase-panel">
            <h2>1. Busca y agrega productos</h2>
            <form onSubmit={buscar}>
              <label htmlFor="sale-mode">Buscar por</label>
              <select
                id="sale-mode"
                value={modo}
                onChange={(e) => setModo(e.target.value)}
              >
                <option value="nombre">Nombre</option>
                <option value="codigo_barras">
                  Código de barras exacto
                </option>
              </select>

              <label htmlFor="sale-search">Producto</label>
              <div className="search-controls">
                <input
                  id="sale-search"
                  value={busqueda}
                  onChange={(e) => setBusqueda(e.target.value)}
                  placeholder="Escribe o escanea el código"
                />
                <button disabled={cargando}>Buscar</button>
              </div>
            </form>

            <p className="footnote">
              Hasta 20 coincidencias. Los lotes vencidos no se venden.
            </p>

            {cargando ? (
              <p role="status">Cargando…</p>
            ) : (
              <ul className="purchase-results">
                {productos.map((producto) => (
                  <li key={producto.id_producto}>
                    <div>
                      <strong>{producto.nombre}</strong>
                      <small>
                        {moneda.format(Number(producto.precio_venta))}
                        {" · "}
                        Existencia registrada: {producto.existencia}
                      </small>
                      {tienePaquete(producto) && <small>{producto.paquete_nombre} × {producto.paquete_unidades}: {moneda.format(Number(producto.paquete_precio))} · Agregar añade {producto.paquete_predeterminado ? `${producto.paquete_unidades} unidades` : "1 unidad"}.</small>}
                    </div>
                    <div className="form-actions">
                    <button
                      className="secondary"
                      type="button"
                      disabled={
                        bloqueado ||
                        !!errorCarga ||
                        producto.existencia < (tienePaquete(producto) && producto.paquete_predeterminado ? Number(producto.paquete_unidades) : 1)
                      }
                      onClick={() => agregar(producto)}
                    >
                      Agregar
                    </button>
                    {tienePaquete(producto) && <button type="button" className="secondary" disabled={bloqueado || !!errorCarga || producto.existencia < (producto.paquete_predeterminado ? 1 : Number(producto.paquete_unidades))} onClick={() => agregar(producto,producto.paquete_predeterminado ? 1 : Number(producto.paquete_unidades))}>{producto.paquete_predeterminado ? "+1 unidad" : `+1 ${producto.paquete_nombre} (${producto.paquete_unidades})`}</button>}
                    </div>
                  </li>
                ))}
                {!productos.length && (
                  <li>No se encontraron productos.</li>
                )}
              </ul>
            )}
          </div>

          <form
            className="catalog-card purchase-panel purchase-detail"
            onSubmit={cobrar}
          >
            <h2>2. Revisa el carrito</h2>

            {lineas.map((linea) => (
              <div
                className="purchase-line"
                key={linea.producto.id_producto}
              >
                <strong>{linea.producto.nombre}</strong>
                <p>
                  {moneda.format(
                    Number(linea.producto.precio_venta),
                  )}{" "}
                  por unidad
                </p>

                <label
                  htmlFor={"sale-qty-" + linea.producto.id_producto}
                >
                  Cantidad total en unidades
                </label>
                <input
                  id={"sale-qty-" + linea.producto.id_producto}
                  type="number"
                  min="1"
                  max={linea.producto.existencia}
                  step="1"
                  required
                  value={linea.cantidad}
                  onChange={(e) =>
                    setLineas((actuales) =>
                      actuales.map((l) =>
                        l.producto.id_producto ===
                        linea.producto.id_producto
                          ? { ...l, cantidad: e.target.value }
                          : l,
                      ),
                    )
                  }
                />
                <DesglosePresentacion producto={linea.producto} cantidad={linea.cantidad} />
                <button
                  type="button"
                  className="secondary"
                  onClick={() =>
                    setLineas((actuales) =>
                      actuales.filter(
                        (l) =>
                          l.producto.id_producto !==
                          linea.producto.id_producto,
                      ),
                    )
                  }
                >
                  Quitar
                </button>
              </div>
            ))}

            {!lineas.length && (
              <p className="state">El carrito está vacío.</p>
            )}

            <h2>3. Datos del cobro</h2>

            <label htmlFor="sale-client">Cliente</label>
            <select
              id="sale-client"
              value={cliente}
              onChange={(e) => setCliente(e.target.value)}
              required={esCredito}
            >
              <option value="">Consumidor final / sin cliente</option>
              {clientes.map((c) => (
                <option key={c.id_cliente} value={c.id_cliente}>
                  {c.nombre}
                </option>
              ))}
            </select>

            <label htmlFor="sale-payment">Forma de pago</label>
            <select
              id="sale-payment"
              value={pago}
              onChange={(e) => setPago(e.target.value)}
              required
            >
              <option value="">Selecciona una forma de pago</option>
              {pagos.map((p) => (
                <option
                  key={p.id_forma_pago}
                  value={p.id_forma_pago}
                >
                  {p.nombre}
                </option>
              ))}
            </select>

            {esCredito && (
              <>
                <label htmlFor="sale-due">
                  Fecha límite de pago (opcional)
                </label>
                <input
                  id="sale-due"
                  type="date"
                  min={hoyGuatemala()}
                  value={fecha}
                  onChange={(e) => setFecha(e.target.value)}
                />
                <p className="footnote">
                  Se creará una cuenta por cobrar para el cliente.
                </p>
              </>
            )}

            {esEfectivo && (
              <>
                <label htmlFor="sale-cash">
                  Efectivo recibido (Q)
                </label>
                <input
                  id="sale-cash"
                  inputMode="decimal"
                  required
                  value={recibido}
                  onChange={(e) => setRecibido(e.target.value)}
                />
                <p>
                  Cambio:{" "}
                  {cambio === null
                    ? "Pendiente"
                    : cambio < 0
                      ? "Efectivo insuficiente"
                      : moneda.format(cambio / 100)}
                </p>
              </>
            )}

            <div className="purchase-summary">
              <div>
                <span>Total</span>
                <strong>
                  {total === null
                    ? "Revisa las cantidades"
                    : moneda.format(total / 100)}
                </strong>
              </div>
              <button
                disabled={
                  bloqueado ||
                  cargando ||
                  !!errorCarga ||
                  !lineas.length
                }
              >
                Registrar venta
              </button>
            </div>
          </form>
        </>
      )}

      {error && (
        <p className="error" role="alert">
          {error}
        </p>
      )}

      <section className="catalog-card purchase-history">
        <div className="purchase-panel">
          <h2>Últimas 20 ventas</h2>
        </div>
        <div className="table-scroll">
          <table>
            <thead>
              <tr>
                <th>Venta</th>
                <th>Total</th>
                <th>Estado</th>
              </tr>
            </thead>
            <tbody>
              {historial.map((venta) => (
                <tr key={venta.id_venta}>
                  <td>#{venta.id_venta}</td>
                  <td>{moneda.format(Number(venta.total))}</td>
                  <td>{venta.estado}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>
    </section>
  );
}