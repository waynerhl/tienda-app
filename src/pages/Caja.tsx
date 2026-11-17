import { useEffect, useRef, useState } from "react";
import type { FormEvent } from "react";
import { supabase } from "../lib/supabase";
import { hoyGuatemala } from "../services/compraValidation";
import { prepararCaja, recuperarCaja } from "../services/cajaValidation";
import type { CajaPayload, TipoCaja } from "../services/cajaValidation";
import "./Efectivo.css";
import "./Caja.css";

type Cierre = {
  id_evento: number;
  fecha_cierre: string;
  efectivo_inicial: number;
  entradas_automaticas: number;
  salidas_automaticas: number;
  gastos: number;
  retiros: number;
  aportes: number;
  saldo_esperado: number;
  efectivo_contado: number;
  diferencia: number;
  observacion: string;
};
type Evento = {
  id_evento: number;
  fecha: string;
  tipo: TipoCaja;
  monto: number | null;
  concepto: string;
  usuario: string;
  datos: Partial<Cierre>;
};
type EstadoCaja = {
  fecha: string;
  caja: {
    efectivo_inicial: number;
    estado: "ABIERTA" | "CERRADA";
    ultimo_cierre: Cierre | null;
  } | null;
  automatico: {
    entradas: number;
    salidas: number;
    variacion: number;
    inconsistencias_total: number;
  };
  gastos: number;
  retiros: number;
  aportes: number;
  saldo_esperado: number | null;
  eventos: Evento[];
};
type Confirmada = {
  id_evento: number;
  fecha: string;
  tipo: TipoCaja;
  monto: number | null;
  datos: Partial<Cierre>;
  repetida: boolean;
};
const dinero = (n: number) =>
  new Intl.NumberFormat("es-GT", { style: "currency", currency: "GTQ" }).format(
    Number(n),
  );
const hora = (s: string) =>
  new Intl.DateTimeFormat("es-GT", {
    timeZone: "America/Guatemala",
    dateStyle: "short",
    timeStyle: "short",
  }).format(new Date(s));
const nombres: Record<TipoCaja, string> = {
  APERTURA: "Apertura",
  AJUSTE_FONDO: "Corrección del fondo inicial",
  GASTO: "Gasto de la tienda",
  RETIRO_PERSONAL: "Retiro personal",
  APORTE: "Aporte de efectivo",
  CIERRE: "Cierre con conteo",
  REAPERTURA: "Reapertura",
};

function ResumenCierre({ cierre }: { cierre: Cierre }) {
  return (
    <div className="caja-cierre">
      <dl className="cash-breakdown">
        <div>
          <dt>Esperado al cerrar</dt>
          <dd>{dinero(cierre.saldo_esperado)}</dd>
        </div>
        <div>
          <dt>Efectivo contado</dt>
          <dd>{dinero(cierre.efectivo_contado)}</dd>
        </div>
        <div>
          <dt>Diferencia (contado − esperado)</dt>
          <dd>{dinero(cierre.diferencia)}</dd>
        </div>
      </dl>
      <p className="footnote">
        {Number(cierre.diferencia) === 0
          ? "La caja coincidió con el conteo."
          : Number(cierre.diferencia) > 0
            ? "Se registró un sobrante."
            : "Se registró un faltante."}
      </p>
      {cierre.observacion && (
        <p className="cobros-texto">Observación: {cierre.observacion}</p>
      )}
    </div>
  );
}
function Formulario({
  tipo,
  fecha,
  bloqueado,
  esperado,
  onPrepare,
}: {
  tipo: TipoCaja;
  fecha: string;
  bloqueado: boolean;
  esperado: number | null;
  onPrepare: (p: CajaPayload) => void;
}) {
  const [monto, setMonto] = useState("");
  const [concepto, setConcepto] = useState("");
  const [elegido, setElegido] = useState<TipoCaja>("GASTO");
  const [error, setError] = useState("");
  const esManual = tipo === "GASTO";
  const accion = esManual ? elegido : tipo;
  function preparar(event: FormEvent) {
    event.preventDefault();
    if (bloqueado) return;
    setError("");
    try {
      const p = prepararCaja(
        fecha,
        accion,
        monto,
        concepto,
        crypto.randomUUID(),
      );
      if (
        accion === "CIERRE" &&
        esperado != null &&
        Math.round(Number(p.p_monto) * 100) !==
          Math.round(Number(esperado) * 100) &&
        !p.p_concepto
      )
        throw new Error(
          "Escribe una observación para documentar la diferencia de caja.",
        );
      onPrepare(p);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Revisa los datos.");
    }
  }
  return (
    <section className="catalog-card purchase-panel cobros-section">
      <h2>{esManual ? "Registrar salida o aporte" : nombres[tipo]}</h2>
      {tipo === "APERTURA" && (
        <p className="muted">
          Indica cuánto efectivo había antes de la primera operación de esta
          fecha. Las ventas, compras y abonos ya registrados ese día también se
          incluyen.
        </p>
      )}
      {tipo === "CIERRE" && (
        <p className="muted">
          Cuenta el dinero físico. El cierre bloquea las operaciones en efectivo
          de esta fecha; el administrador puede reabrirla dejando un motivo.
        </p>
      )}
      {tipo === "REAPERTURA" && (
        <p className="muted">
          El cierre anterior seguirá en el historial. La caja volverá a aceptar
          operaciones en efectivo.
        </p>
      )}
      {tipo === "AJUSTE_FONDO" && (
        <p className="muted">
          Corrige un error del fondo inicial e indica el motivo. Si agregaste
          dinero físico durante el día, registra un aporte.
        </p>
      )}
      <form onSubmit={preparar}>
        <fieldset className="purchase-fields" disabled={bloqueado}>
          {esManual && (
            <>
              <label htmlFor="caja-tipo">Tipo de movimiento</label>
              <select
                id="caja-tipo"
                value={elegido}
                onChange={(e) => setElegido(e.target.value as TipoCaja)}
              >
                <option value="GASTO">Gasto de la tienda</option>
                <option value="RETIRO_PERSONAL">Retiro personal</option>
                <option value="APORTE">Aporte de efectivo</option>
              </select>
              <small className="muted">
                Los pagos de compras y abonos a proveedores se registran en sus
                módulos y ya se incluyen automáticamente.
              </small>
            </>
          )}
          {tipo !== "REAPERTURA" && (
            <>
              <label htmlFor={`caja-monto-${tipo}`}>
                {tipo === "APERTURA" || tipo === "AJUSTE_FONDO"
                  ? "Fondo inicial (Q)"
                  : tipo === "CIERRE"
                    ? "Efectivo contado (Q)"
                    : "Monto (Q)"}
              </label>
              <input
                id={`caja-monto-${tipo}`}
                inputMode="decimal"
                required
                value={monto}
                onChange={(e) => setMonto(e.target.value)}
              />
            </>
          )}
          <label htmlFor={`caja-concepto-${tipo}`}>
            {tipo === "CIERRE"
              ? "Observación del conteo"
              : tipo === "REAPERTURA"
                ? "Motivo de reapertura"
                : "Concepto"}
          </label>
          <textarea
            id={`caja-concepto-${tipo}`}
            maxLength={500}
            required={
              esManual || tipo === "REAPERTURA" || tipo === "AJUSTE_FONDO"
            }
            value={concepto}
            onChange={(e) => setConcepto(e.target.value)}
          />
          <div className="form-actions">
            <button>
              Revisar {esManual ? "movimiento" : nombres[tipo].toLowerCase()}
            </button>
          </div>
        </fieldset>
        {error && (
          <p className="error" role="alert">
            {error}
          </p>
        )}
      </form>
    </section>
  );
}

export default function Caja({
  activo,
  revision,
  userId,
  onChanged,
}: {
  activo: boolean;
  revision: number;
  userId: string;
  onChanged: () => void;
}) {
  const clave = `tienda:caja-pendiente:${userId}`;
  const [recuperado] = useState(() => recuperarCaja(clave));
  const [pendiente, setPendiente] = useState<CajaPayload | null>(
    recuperado.pendiente,
  );
  const [preparada, setPreparada] = useState<CajaPayload | null>(null);
  const [fecha, setFecha] = useState(
    () => recuperado.pendiente?.p_fecha ?? hoyGuatemala(),
  );
  const [datos, setDatos] = useState<EstadoCaja | null>(null);
  const [cargando, setCargando] = useState(true);
  const [errorCarga, setErrorCarga] = useState("");
  const [error, setError] = useState("");
  const [mensaje, setMensaje] = useState("");
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
        const r = await supabase
          .rpc("obtener_caja_dia", { p_fecha: fecha })
          .abortSignal(controller.signal);
        if (controller.signal.aborted) return;
        if (
          r.error ||
          r.data?.fecha !== fecha ||
          !Array.isArray(r.data?.eventos) ||
          !r.data?.automatico
        )
          throw new Error();
        setDatos(r.data as EstadoCaja);
      } catch {
        if (!controller.signal.aborted)
          setErrorCarga("No pudimos consultar la caja. Comprueba la conexión.");
      } finally {
        if (!controller.signal.aborted) setCargando(false);
      }
    }
    void cargar();
    return () => controller.abort();
  }, [activo, revision, fecha, intento]);
  function preparar(p: CajaPayload) {
    setPreparada(p);
    setError("");
    setMensaje("");
    setTimeout(
      () =>
        document
          .getElementById("caja-confirmacion")
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
    setMensaje("");
    if (!pendiente) {
      try {
        localStorage.setItem(clave, JSON.stringify(p));
      } catch {
        setError(
          "No pudimos guardar la confirmación pendiente en este navegador. No se envió la operación.",
        );
        return;
      }
      setPendiente(p);
      setPreparada(null);
    }
    bloqueo.current = true;
    setGuardando(true);
    try {
      const { data, error: fallo } = await supabase.rpc("operar_caja", p);
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
          "No pudimos confirmar la respuesta. Reintenta esta misma confirmación.",
        );
      }
      const r = data as Confirmada;
      if (
        !r ||
        !Number.isSafeInteger(r.id_evento) ||
        r.fecha !== p.p_fecha ||
        r.tipo !== p.p_tipo ||
        (p.p_monto === null ? r.monto !== null : Number(r.monto) !== p.p_monto)
      )
        throw new Error(
          "No se pudo verificar la respuesta. Reintenta la confirmación.",
        );
      setMensaje(`${nombres[r.tipo]} registrada. Comprobante #${r.id_evento}.`);
      try {
        localStorage.removeItem(clave);
        setPendiente(null);
      } catch {
        setError(
          "La operación está registrada. Reintenta para limpiar el pendiente de este dispositivo.",
        );
      }
      setIntento((v) => v + 1);
      onChanged();
    } catch (e) {
      setError(
        e instanceof Error
          ? e.message
          : "No pudimos confirmar la operación. Reintenta la misma confirmación.",
      );
    } finally {
      bloqueo.current = false;
      setGuardando(false);
    }
  }
  const bloqueado =
    guardando || !!pendiente || !!preparada || !!recuperado.error;
  const confirmarDatos = pendiente ?? preparada;
  return (
    <>
      <div className="section-heading">
        <div>
          <p className="eyebrow">CONTROL DIARIO DE CAJA</p>
          <h1>Apertura y cierre</h1>
          <p className="muted">
            Una caja compartida por fecha, en horario de Guatemala.
          </p>
        </div>
        <button
          className="secondary"
          disabled={cargando || guardando}
          onClick={() => setIntento((v) => v + 1)}
        >
          Actualizar
        </button>
      </div>
      <div className="catalog-card search-form cash-filter">
        <label htmlFor="caja-fecha">Fecha de caja</label>
        <input
          id="caja-fecha"
          type="date"
          min="1900-01-01"
          max={hoyGuatemala()}
          disabled={bloqueado}
          value={fecha}
          onChange={(e) => {
            if (/^\d{4}-\d{2}-\d{2}$/.test(e.target.value)) {
              setFecha(e.target.value);
              setMensaje("");
              setError("");
            }
          }}
        />
      </div>
      {mensaje && (
        <p className="success" role="status">
          {mensaje}
        </p>
      )}
      {recuperado.error && (
        <p className="error" role="alert">
          {recuperado.error}
        </p>
      )}
      {confirmarDatos && (
        <section
          id="caja-confirmacion"
          className="catalog-card purchase-panel cobros-section"
          aria-label="Confirmación de caja"
        >
          <h2>
            {pendiente ? "Confirmación pendiente" : "Revisa antes de confirmar"}
          </h2>
          <p>
            <strong>{nombres[confirmarDatos.p_tipo]}</strong> · Fecha:{" "}
            {confirmarDatos.p_fecha.split("-").reverse().join("/")}
          </p>
          {confirmarDatos.p_monto != null && (
            <p>
              {confirmarDatos.p_tipo === "CIERRE" ? "Contado" : "Monto"}:{" "}
              <strong>{dinero(confirmarDatos.p_monto)}</strong>
            </p>
          )}
          {confirmarDatos.p_concepto && (
            <p className="cobros-texto">{confirmarDatos.p_concepto}</p>
          )}
          {!pendiente &&
            confirmarDatos.p_tipo === "CIERRE" &&
            datos?.saldo_esperado != null && (
              <p>
                Esperado al consultar: {dinero(datos.saldo_esperado)} ·
                Diferencia prevista:{" "}
                {dinero(
                  Number(confirmarDatos.p_monto) - Number(datos.saldo_esperado),
                )}
                . El servidor recalculará el importe al cerrar.
              </p>
            )}
          {pendiente && (
            <p>
              Reintenta para verificar si ya quedó registrada. Se utilizará la
              misma referencia.
            </p>
          )}
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
                  : "Confirmar operación"}
            </button>
          </div>
        </section>
      )}
      {error && (
        <p className="error" role="alert">
          {error}
        </p>
      )}
      {cargando ? (
        <p className="state" role="status">
          Consultando caja…
        </p>
      ) : errorCarga ? (
        <div>
          <p className="error" role="alert">
            {errorCarga}
          </p>
          <button onClick={() => setIntento((v) => v + 1)}>
            Reintentar consulta
          </button>
        </div>
      ) : (
        datos && (
          <section data-caja-fecha={datos.fecha}>
            <p className="inventory-note">
              Estado: <strong>{datos.caja?.estado ?? "SIN APERTURA"}</strong>.
              El saldo esperado suma el fondo inicial, ventas y cobros en
              efectivo y aportes; resta compras, pagos a proveedores, gastos y
              retiros.
            </p>
            <div className="cash-grid caja-grid">
              <article className="cash-stat">
                <span>Fondo inicial</span>
                <strong>
                  {datos.caja
                    ? dinero(datos.caja.efectivo_inicial)
                    : "Sin apertura"}
                </strong>
              </article>
              <article className="cash-stat">
                <span>Entradas automáticas</span>
                <strong>{dinero(datos.automatico.entradas)}</strong>
                <small>Ventas y cobros en efectivo</small>
              </article>
              <article className="cash-stat">
                <span>Salidas automáticas</span>
                <strong>{dinero(datos.automatico.salidas)}</strong>
                <small>Compras y pagos en efectivo</small>
              </article>
              <article className="cash-stat">
                <span>Gastos / retiros personales</span>
                <strong>
                  {dinero(Number(datos.gastos) + Number(datos.retiros))}
                </strong>
                <small>
                  Gastos: {dinero(datos.gastos)} · Retiros:{" "}
                  {dinero(datos.retiros)}
                </small>
              </article>
              <article className="cash-stat">
                <span>Aportes</span>
                <strong>{dinero(datos.aportes)}</strong>
              </article>
              <article className="cash-stat">
                <span>Saldo esperado</span>
                <strong>
                  {datos.saldo_esperado == null
                    ? "Sin apertura"
                    : dinero(datos.saldo_esperado)}
                </strong>
                <small>El conteo físico se registra en el cierre.</small>
              </article>
            </div>
            {datos.automatico.inconsistencias_total > 0 && (
              <p className="error" role="alert">
                Hay {datos.automatico.inconsistencias_total} movimientos
                inconsistentes. Revísalos en Efectivo antes de cerrar.
              </p>
            )}
            {datos.saldo_esperado != null &&
              Number(datos.saldo_esperado) < 0 && (
                <p className="inventory-note">
                  El saldo esperado es negativo. Revisa el fondo inicial y los
                  registros antes del conteo.
                </p>
              )}
            {!datos.caja ? (
              <Formulario
                key={`${fecha}-apertura`}
                fecha={fecha}
                tipo="APERTURA"
                bloqueado={bloqueado}
                esperado={null}
                onPrepare={preparar}
              />
            ) : datos.caja.estado === "ABIERTA" ? (
              <>
                <details className="cobros-section">
                  <summary>Corregir fondo inicial</summary>
                  <Formulario
                    key={`${fecha}-fondo-${intento}`}
                    fecha={fecha}
                    tipo="AJUSTE_FONDO"
                    bloqueado={bloqueado}
                    esperado={datos.saldo_esperado}
                    onPrepare={preparar}
                  />
                </details>
                <Formulario
                  key={`${fecha}-manual-${intento}`}
                  fecha={fecha}
                  tipo="GASTO"
                  bloqueado={bloqueado}
                  esperado={datos.saldo_esperado}
                  onPrepare={preparar}
                />
                <Formulario
                  key={`${fecha}-cierre`}
                  fecha={fecha}
                  tipo="CIERRE"
                  bloqueado={
                    bloqueado || datos.automatico.inconsistencias_total > 0
                  }
                  esperado={datos.saldo_esperado}
                  onPrepare={preparar}
                />
              </>
            ) : (
              <Formulario
                key={`${fecha}-reapertura`}
                fecha={fecha}
                tipo="REAPERTURA"
                bloqueado={bloqueado}
                esperado={datos.saldo_esperado}
                onPrepare={preparar}
              />
            )}
            {datos.caja?.ultimo_cierre && (
              <section className="catalog-card purchase-panel cobros-section">
                <h2>Último cierre registrado</h2>
                <p className="muted">
                  Comprobante #{datos.caja.ultimo_cierre.id_evento} ·{" "}
                  {hora(datos.caja.ultimo_cierre.fecha_cierre)}
                </p>
                {datos.caja.estado === "ABIERTA" && (
                  <p className="muted">
                    La caja se reabrió después de este cierre.
                  </p>
                )}
                <ResumenCierre cierre={datos.caja.ultimo_cierre} />
              </section>
            )}
            <section className="catalog-card cobros-section">
              <div className="purchase-panel">
                <h2>Historial de caja</h2>
                <p className="muted">
                  Últimos 30 eventos de esta fecha. Los movimientos automáticos
                  se consultan en Efectivo.
                </p>
              </div>
              {!datos.eventos.length ? (
                <p className="state">Todavía no hay eventos de caja.</p>
              ) : (
                <div
                  className="table-scroll"
                  tabIndex={0}
                  role="region"
                  aria-label="Eventos de caja"
                >
                  <table>
                    <thead>
                      <tr>
                        <th>Comprobante / fecha</th>
                        <th>Operación</th>
                        <th className="numeric">Monto</th>
                        <th>Concepto</th>
                        <th>Registrado por</th>
                        <th>Cierre</th>
                      </tr>
                    </thead>
                    <tbody>
                      {datos.eventos.map((e) => (
                        <tr key={e.id_evento}>
                          <td>
                            #{e.id_evento}
                            <span className="history-date">
                              {hora(e.fecha)}
                            </span>
                          </td>
                          <td>{nombres[e.tipo]}</td>
                          <td className="numeric">
                            {e.monto == null ? "—" : dinero(e.monto)}
                          </td>
                          <td className="caja-concepto">{e.concepto || "—"}</td>
                          <td>{e.usuario}</td>
                          <td>
                            {e.tipo === "CIERRE" && (
                              <details>
                                <summary>Ver conteo</summary>
                                <ResumenCierre cierre={e.datos as Cierre} />
                              </details>
                            )}
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </section>
            <p className="footnote">
              Registra aquí gastos y retiros ya realizados. No vuelvas a
              registrar una compra o un pago a proveedor como gasto de caja. Un
              retiro personal reduce efectivo y se mantiene separado de los
              gastos de la tienda.
            </p>
          </section>
        )
      )}
    </>
  );
}
