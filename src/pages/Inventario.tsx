import { patronBusquedaNombre } from "../services/busquedas";
import { useEffect, useRef, useState } from "react";
import type { FormEvent } from "react";
import { supabase } from "../lib/supabase";
import {
  prepararAjuste,
  recuperarAjuste,
  nombresAjuste,
} from "../services/inventarioValidation";
import type {
  ProductoInv,
  LoteInv,
  TipoAjuste,
  AjustePayload,
  AjusteResultado,
} from "../services/inventarioValidation";
import "./Inventario.css";
type DatosInv = {
  producto: ProductoInv;
  total_lotes: number;
  suma_lotes: number;
  lotes: LoteInv[];
  ajustes: {
    id_ajuste: number;
    fecha: string;
    tipo: TipoAjuste;
    lote_id: number | null;
    motivo: string;
    resultado: AjusteResultado;
  }[];
  movimientos: {
    id_movimiento_inventario: number;
    fecha: string;
    tipo: string;
    cantidad: number;
    factor: number;
    lote_id: number | null;
    observacion: string | null;
  }[];
};
const fecha = (s: string | null) =>
  s ? s.split("-").reverse().join("/") : "Sin fecha registrada";
const hora = (s: string) =>
  new Intl.DateTimeFormat("es-GT", {
    timeZone: "America/Guatemala",
    dateStyle: "short",
    timeStyle: "short",
  }).format(new Date(s));
function FormularioAjuste({
  producto,
  lote,
  bloqueado,
  onPrepare,
}: {
  producto: ProductoInv;
  lote: LoteInv | null;
  bloqueado: boolean;
  onPrepare: (p: AjustePayload) => void;
}) {
  const [tipo, setTipo] = useState<TipoAjuste>("CONTEO");
  const [cantidad, setCantidad] = useState("");
  const [motivo, setMotivo] = useState("");
  const [error, setError] = useState("");
  function preparar(e: FormEvent) {
    e.preventDefault();
    if (bloqueado) return;
    setError("");
    try {
      onPrepare(
        prepararAjuste(
          producto,
          lote,
          tipo,
          cantidad,
          motivo,
          crypto.randomUUID(),
        ),
      );
    } catch (e) {
      setError(e instanceof Error ? e.message : "Revisa los datos.");
    }
  }
  const antes = lote ? lote.existencia : producto.existencia;
  return (
    <section className="catalog-card purchase-panel cobros-section">
      <h2>Preparar ajuste</h2>
      <p>
        <strong>{producto.nombre}</strong>
        {lote && <> · {lote.numero_lote || `Lote #${lote.id_lote}`}</>} ·
        Existencia vista: <strong>{antes}</strong>
      </p>
      <form onSubmit={preparar}>
        <fieldset className="purchase-fields" disabled={bloqueado}>
          <label htmlFor="inventario-tipo">Operación</label>
          <select
            id="inventario-tipo"
            value={tipo}
            onChange={(e) => setTipo(e.target.value as TipoAjuste)}
          >
            {Object.entries(nombresAjuste).map(([v, n]) => (
              <option
                key={v}
                value={v}
                disabled={v === "VENCIMIENTO" && !lote?.vencido}
              >
                {n}
              </option>
            ))}
          </select>
          <label htmlFor="inventario-cantidad">
            {tipo === "CONTEO"
              ? "Unidades contadas físicamente"
              : "Unidades del movimiento"}
          </label>
          <input
            id="inventario-cantidad"
            required
            inputMode="numeric"
            value={cantidad}
            onChange={(e) => setCantidad(e.target.value)}
          />
          <small className="muted">
            {tipo === "CONTEO"
              ? "Indica el total que contaste en esta unidad de inventario. Se admite cero."
              : "Indica cuántas unidades entran o salen; debe ser mayor que cero."}
          </small>
          <label htmlFor="inventario-motivo">Motivo</label>
          <textarea
            id="inventario-motivo"
            required
            maxLength={500}
            value={motivo}
            onChange={(e) => setMotivo(e.target.value)}
          />
          <div className="form-actions">
            <button>Revisar ajuste</button>
          </div>
        </fieldset>
        {error && (
          <p className="error" role="alert">
            {error}
          </p>
        )}
      </form>
      <p className="footnote">
        Un ajuste cambia existencias. Las compras y ventas se registran en sus
        propios módulos. Da de baja por vencimiento cuando retires físicamente
        las unidades.
      </p>
    </section>
  );
}
function DetalleInventario({
  id,
  activo,
  revision,
  bloqueado,
  onPrepare,
}: {
  id: number;
  activo: boolean;
  revision: number;
  bloqueado: boolean;
  onPrepare: (p: AjustePayload) => void;
}) {
  const [datos, setDatos] = useState<DatosInv | null>(null);
  const [pagina, setPagina] = useState(0);
  const [lote, setLote] = useState<LoteInv | null>(null);
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
          .rpc("obtener_inventario_producto", {
            p_producto_id: id,
            p_pagina_lotes: pagina,
          })
          .abortSignal(controller.signal);
        if (controller.signal.aborted) return;
        if (
          r.error ||
          r.data?.producto?.id_producto !== id ||
          !Array.isArray(r.data?.lotes)
        )
          throw new Error();
        setDatos(r.data as DatosInv);
        setLote(null);
      } catch {
        if (!controller.signal.aborted)
          setError("No pudimos consultar el inventario del producto.");
      } finally {
        if (!controller.signal.aborted) setCargando(false);
      }
    }
    void cargar();
    return () => controller.abort();
  }, [id, activo, revision, pagina, intento]);
  if (cargando)
    return (
      <p className="state" role="status">
        Consultando inventario…
      </p>
    );
  if (error || !datos)
    return (
      <div>
        <p className="error" role="alert">
          {error}
        </p>
        <button onClick={() => setIntento((v) => v + 1)}>
          Reintentar consulta
        </button>
      </div>
    );
  const inconsistente =
    datos.producto.controla_lotes &&
    Number(datos.suma_lotes) !== datos.producto.existencia;
  return (
    <section className="cobros-section" aria-label="Inventario del producto">
      <h2>{datos.producto.nombre}</h2>
      <p>
        Existencia total: <strong>{datos.producto.existencia}</strong> ·{" "}
        {datos.producto.activo ? "Producto activo" : "Producto inactivo"}
      </p>
      {inconsistente && (
        <p className="error" role="alert">
          La suma de lotes ({datos.suma_lotes}) no coincide con el producto.
          Revisa el historial antes de ajustar.
        </p>
      )}
      {datos.producto.controla_lotes && (
        <section className="catalog-card">
          <div className="purchase-panel">
            <h3>Selecciona el lote físico</h3>
            <p className="muted">
              Incluye lotes agotados para poder registrar un conteo o corregir
              una entrada.
            </p>
          </div>
          <div
            className="table-scroll"
            tabIndex={0}
            role="region"
            aria-label="Lotes del producto"
          >
            <table>
              <thead>
                <tr>
                  <th>Lote</th>
                  <th>Vencimiento</th>
                  <th className="numeric">Existencia</th>
                  <th>Estado</th>
                  <th>Seleccionar</th>
                </tr>
              </thead>
              <tbody>
                {datos.lotes.map((l) => (
                  <tr key={l.id_lote}>
                    <td>{l.numero_lote || `#${l.id_lote}`}<span className="history-date">{l.origen === "LOTE_INICIAL" ? "Inventario inicial" : "Compra"}</span></td>
                    <td>{fecha(l.fecha_vencimiento)}</td>
                    <td className="numeric">{l.existencia}</td>
                    <td>
                      <span className={`badge ${l.vencido ? "low" : ""}`}>
                        {l.vencido
                          ? "Vencido"
                          : l.fecha_vencimiento
                            ? "Vigente"
                            : "Sin fecha"}
                      </span>
                    </td>
                    <td>
                      <button
                        className="secondary"
                        disabled={bloqueado || inconsistente}
                        onClick={() => setLote(l)}
                      >
                        {lote?.id_lote === l.id_lote
                          ? "Seleccionado"
                          : "Usar lote"}
                      </button>
                    </td>
                  </tr>
                ))}
                {!datos.lotes.length && (
                  <tr>
                    <td colSpan={5}>
                      No hay lotes en esta página. Los lotes nuevos se registran
                      al comprar o en Inventario inicial antes de operar.
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
          <div className="pagination">
            <span>
              {datos.total_lotes} lotes · página {pagina + 1}
            </span>
            <div>
              <button
                className="secondary"
                disabled={bloqueado || pagina === 0}
                onClick={() => setPagina((v) => v - 1)}
              >
                Anterior lote
              </button>
              <button
                className="secondary"
                disabled={bloqueado || (pagina + 1) * 20 >= datos.total_lotes}
                onClick={() => setPagina((v) => v + 1)}
              >
                Siguiente lote
              </button>
            </div>
          </div>
        </section>
      )}
      {(!datos.producto.controla_lotes || lote) && (
        <FormularioAjuste
          key={`${id}-${lote?.id_lote ?? "producto"}-${revision}-${intento}`}
          producto={datos.producto}
          lote={lote}
          bloqueado={bloqueado || inconsistente}
          onPrepare={onPrepare}
        />
      )}
      <section className="catalog-card cobros-section">
        <div className="purchase-panel">
          <h3>Últimos 20 ajustes manuales</h3>
        </div>
        {!datos.ajustes.length ? (
          <p className="state">Todavía no hay ajustes manuales.</p>
        ) : (
          <div
            className="table-scroll"
            tabIndex={0}
            role="region"
            aria-label="Ajustes manuales"
          >
            <table>
              <thead>
                <tr>
                  <th>Comprobante / fecha</th>
                  <th>Operación</th>
                  <th>Lote</th>
                  <th className="numeric">Antes</th>
                  <th className="numeric">Después</th>
                  <th>Motivo</th>
                </tr>
              </thead>
              <tbody>
                {datos.ajustes.map((a) => (
                  <tr key={a.id_ajuste}>
                    <td>
                      #{a.id_ajuste}
                      <span className="history-date">{hora(a.fecha)}</span>
                    </td>
                    <td>{nombresAjuste[a.tipo]}</td>
                    <td>{a.lote_id ?? "—"}</td>
                    <td className="numeric">
                      {a.resultado.existencia_anterior}
                    </td>
                    <td className="numeric">{a.resultado.existencia_nueva}</td>
                    <td className="inventario-motivo">{a.motivo}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
      <section className="catalog-card cobros-section">
        <div className="purchase-panel">
          <h3>Últimos 30 movimientos</h3>
          <p className="muted">
            Compras, ventas y otras entradas o salidas registradas.
          </p>
        </div>
        {!datos.movimientos.length ? (
          <p className="state">Todavía no hay movimientos.</p>
        ) : (
          <div
            className="table-scroll"
            tabIndex={0}
            role="region"
            aria-label="Movimientos de inventario"
          >
            <table>
              <thead>
                <tr>
                  <th>Referencia / fecha</th>
                  <th>Tipo</th>
                  <th>Lote</th>
                  <th className="numeric">Unidades</th>
                  <th>Observación</th>
                </tr>
              </thead>
              <tbody>
                {datos.movimientos.map((m) => (
                  <tr key={m.id_movimiento_inventario}>
                    <td>
                      #{m.id_movimiento_inventario}
                      <span className="history-date">{hora(m.fecha)}</span>
                    </td>
                    <td>{m.tipo.replaceAll("_", " ")}</td>
                    <td>{m.lote_id ?? "—"}</td>
                    <td className="numeric">
                      {m.factor > 0 ? "+" : "−"}
                      {m.cantidad}
                    </td>
                    <td className="inventario-motivo">
                      {m.observacion || "—"}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </section>
  );
}

export default function Inventario({
  userId,
  activo,
  revision,
  onChanged,
}: {
  userId: string;
  activo: boolean;
  revision: number;
  onChanged: () => void;
}) {
  const clave = `tienda:ajuste-inventario-pendiente:${userId}`;
  const [recuperado] = useState(() => recuperarAjuste(clave));
  const [pendiente, setPendiente] = useState<AjustePayload | null>(
    recuperado.pendiente,
  );
  const [preparada, setPreparada] = useState<AjustePayload | null>(null);
  const [elegido, setElegido] = useState<number | null>(
    () => recuperado.pendiente?.p_producto_id ?? null,
  );
  const [busqueda, setBusqueda] = useState("");
  const [modo, setModo] = useState("nombre");
  const [consulta, setConsulta] = useState({ texto: "", modo: "nombre" });
  const [productos, setProductos] = useState<ProductoInv[]>([]);
  const [cargando, setCargando] = useState(true);
  const [errorCarga, setErrorCarga] = useState("");
  const [error, setError] = useState("");
  const [confirmado, setConfirmado] = useState<AjusteResultado | null>(null);
  const [guardando, setGuardando] = useState(false);
  const [intento, setIntento] = useState(0);
  const bloqueo = useRef(false);
  useEffect(() => {
    if (!activo) return;
    const controller = new AbortController();
    async function cargar() {
      if (!supabase) return;
      setCargando(true);
      setErrorCarga("");
      try {
        let q = supabase
          .from("productos")
          .select(
            "id_producto,nombre,codigo_barras,existencia,controla_lotes,activo",
          )
          .order("nombre")
          .order("id_producto")
          .limit(20);
        if (consulta.texto)
          q =
            consulta.modo === "codigo_barras"
              ? q.eq("codigo_barras", consulta.texto)
              : q.ilike(
                  "nombre_busqueda", patronBusquedaNombre(consulta.texto),
                );
        const r = await q.abortSignal(controller.signal);
        if (controller.signal.aborted) return;
        if (r.error) throw new Error();
        setProductos((r.data ?? []) as ProductoInv[]);
      } catch {
        if (!controller.signal.aborted)
          setErrorCarga("No pudimos consultar los productos.");
      } finally {
        if (!controller.signal.aborted) setCargando(false);
      }
    }
    void cargar();
    return () => controller.abort();
  }, [activo, revision, consulta, intento]);
  function preparar(p: AjustePayload) {
    setPreparada(p);
    setError("");
    setConfirmado(null);
    setTimeout(
      () =>
        document
          .getElementById("inventario-confirmacion")
          ?.scrollIntoView({ behavior: "smooth", block: "center" }),
      0,
    );
  }
  async function confirmar() {
    if (!supabase || bloqueo.current || recuperado.error) return;
    const p = pendiente ?? preparada;
    if (!p) return;
    const esReintento = pendiente !== null;
    setError("");
    if (!pendiente) {
      try {
        localStorage.setItem(clave, JSON.stringify(p));
      } catch {
        setError(
          "No se pudo guardar la confirmación pendiente. No se envió el ajuste.",
        );
        return;
      }
      setPendiente(p);
      setPreparada(null);
    }
    bloqueo.current = true;
    setGuardando(true);
    try {
      const { data, error: fallo } = await supabase.rpc(
        "registrar_ajuste_inventario",
        p,
      );
      if (fallo) {
        if (
          [
            "22023",
            "22003",
            "22P02",
            "42501",
            "23503",
            "23514",
            "P0001",
            "40P01",
            "40001",
          ].includes(fallo.code) &&
          !(esReintento && fallo.code === "42501")
        ) {
          localStorage.removeItem(clave);
          setPendiente(null);
          setIntento((v) => v + 1);
          throw new Error(fallo.message);
        }
        throw new Error(
          "No pudimos confirmar la respuesta. Reintenta la misma confirmación.",
        );
      }
      const r = data as AjusteResultado;
      if (
        !r ||
        !Number.isSafeInteger(r.id_ajuste) ||
        r.producto_id !== p.p_producto_id ||
        r.lote_id !== p.p_lote_id ||
        r.tipo !== p.p_tipo ||
        !Number.isSafeInteger(r.existencia_nueva) ||
        !Number.isSafeInteger(r.producto_nuevo)
      )
        throw new Error(
          "No se pudo verificar la respuesta. Reintenta la confirmación.",
        );
      setConfirmado(r);
      try {
        localStorage.removeItem(clave);
        setPendiente(null);
      } catch {
        setError(
          "El ajuste está registrado. Reintenta para limpiar el pendiente de este dispositivo.",
        );
      }
      setIntento((v) => v + 1);
      onChanged();
    } catch (e) {
      setError(
        e instanceof Error
          ? e.message
          : "No pudimos confirmar el ajuste. Reintenta la misma confirmación.",
      );
    } finally {
      bloqueo.current = false;
      setGuardando(false);
    }
  }
  const bloqueado =
    guardando || !!pendiente || !!preparada || !!recuperado.error;
  const operacion = pendiente ?? preparada;
  const variacion = operacion
    ? operacion.p_tipo === "CONTEO"
      ? operacion.p_cantidad - operacion.p_existencia_esperada
      : operacion.p_tipo === "AJUSTE_POSITIVO"
        ? operacion.p_cantidad
        : -operacion.p_cantidad
    : 0;
  return (
    <>
      <div className="section-heading">
        <div>
          <p className="eyebrow">EXISTENCIAS FÍSICAS</p>
          <h1>Ajustes de inventario</h1>
          <p className="muted">
            Conteos, pérdidas y bajas de productos vencidos.
          </p>
        </div>
        <button
          className="secondary"
          disabled={guardando}
          onClick={() => setIntento((v) => v + 1)}
        >
          Actualizar inventario
        </button>
      </div>
      {recuperado.error && (
        <p className="error" role="alert">
          {recuperado.error}
        </p>
      )}
      {confirmado && (
        <p className="success" role="status">
          Ajuste #{confirmado.id_ajuste} confirmado. Existencia de la unidad
          ajustada: {confirmado.existencia_anterior} →{" "}
          {confirmado.existencia_nueva}. Total del producto al confirmar:{" "}
          {confirmado.producto_nuevo}.
          {confirmado.variacion === 0
            ? " El conteo coincidió y quedó registrado sin mover stock."
            : ""}
        </p>
      )}
      {operacion && (
        <section
          id="inventario-confirmacion"
          className="catalog-card purchase-panel cobros-section"
          aria-label="Confirmación de inventario"
        >
          <h2>
            {pendiente
              ? "Confirmación pendiente"
              : "Revisa el cambio de existencias"}
          </h2>
          <p>
            {nombresAjuste[operacion.p_tipo]} · Producto #
            {operacion.p_producto_id}
            {operacion.p_lote_id != null && <> · Lote #{operacion.p_lote_id}</>}
          </p>
          <p>
            Existencia vista: <strong>{operacion.p_existencia_esperada}</strong>{" "}
            → Después:{" "}
            <strong>{operacion.p_existencia_esperada + variacion}</strong> (
            {variacion > 0 ? "+" : ""}
            {variacion} unidades).
          </p>
          <p className="cobros-texto">Motivo: {operacion.p_motivo}</p>
          <p className="footnote">
            Si la existencia cambió desde la consulta, el servidor rechazará el
            ajuste para que revises de nuevo.
          </p>
          <div className="form-actions">
            {!pendiente && (
              <button
                className="secondary"
                disabled={guardando}
                onClick={() => setPreparada(null)}
              >
                Volver
              </button>
            )}
            <button
              disabled={guardando || !!recuperado.error}
              onClick={() => void confirmar()}
            >
              {guardando
                ? "Confirmando…"
                : pendiente
                  ? "Reintentar confirmación"
                  : "Confirmar ajuste"}
            </button>
          </div>
        </section>
      )}
      {error && (
        <p className="error" role="alert">
          {error}
        </p>
      )}
      <section className="catalog-card">
        <form
          className="search-form"
          onSubmit={(e) => {
            e.preventDefault();
            setConsulta({ texto: busqueda.trim(), modo });
          }}
        >
          <label htmlFor="inventario-modo">Buscar por</label>
          <select
            id="inventario-modo"
            value={modo}
            onChange={(e) => setModo(e.target.value)}
          >
            <option value="nombre">Nombre</option>
            <option value="codigo_barras">Código de barras exacto</option>
          </select>
          <label htmlFor="inventario-buscar">Producto</label>
          <div className="search-controls">
            <input
              id="inventario-buscar"
              maxLength={150}
              value={busqueda}
              onChange={(e) => setBusqueda(e.target.value)}
            />
            <button>Buscar producto</button>
          </div>
          <p className="footnote">
            Hasta 20 coincidencias, incluidos productos inactivos.
          </p>
        </form>
        {cargando ? (
          <p className="state" role="status">
            Buscando productos…
          </p>
        ) : errorCarga ? (
          <div className="purchase-panel">
            <p className="error" role="alert">
              {errorCarga}
            </p>
            <button onClick={() => setIntento((v) => v + 1)}>
              Reintentar búsqueda
            </button>
          </div>
        ) : (
          <div
            className="table-scroll"
            tabIndex={0}
            role="region"
            aria-label="Productos para inventario"
          >
            <table>
              <thead>
                <tr>
                  <th>Producto</th>
                  <th>Código</th>
                  <th className="numeric">Existencia</th>
                  <th>Seleccionar</th>
                </tr>
              </thead>
              <tbody>
                {productos.map((p) => (
                  <tr key={p.id_producto}>
                    <td>
                      {p.nombre}
                      {!p.activo && (
                        <span className="history-date">Inactivo</span>
                      )}
                    </td>
                    <td>{p.codigo_barras || "—"}</td>
                    <td className="numeric">{p.existencia}</td>
                    <td>
                      <button
                        className="secondary"
                        disabled={bloqueado}
                        onClick={() => {
                          setElegido(p.id_producto);
                          setConfirmado(null);
                        }}
                      >
                        {elegido === p.id_producto
                          ? "Seleccionado"
                          : "Ver inventario"}
                      </button>
                    </td>
                  </tr>
                ))}
                {!productos.length && (
                  <tr>
                    <td colSpan={4}>No se encontraron productos.</td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        )}
      </section>
      {elegido != null && (
        <DetalleInventario
          key={elegido}
          id={elegido}
          activo={activo}
          revision={revision + intento}
          bloqueado={bloqueado}
          onPrepare={preparar}
        />
      )}
      <p className="inventory-note">
        Los ajustes no generan ventas, compras, deudas ni movimientos de caja.
        No borran el historial; si cometiste un error, registra una corrección
        con su motivo.
      </p>
    </>
  );
}
