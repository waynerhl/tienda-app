import { useEffect, useRef, useState } from "react";
import type { FormEvent } from "react";
import { supabase } from "../lib/supabase";
import {
  prepararAbono,
  prepararCliente,
  recuperarAbono,
} from "../services/cobroValidation";
import type {
  AbonoConfirmado,
  AbonoPayload,
  Cliente,
  Cuenta,
  EstadoCliente,
  FormaAbono,
  ListaClientes,
} from "../types/cobro";

const dinero = (valor: number) =>
  new Intl.NumberFormat("es-GT", { style: "currency", currency: "GTQ" }).format(
    Number(valor),
  );
const fecha = (valor: string | null) =>
  valor
    ? valor.slice(0, 10).split("-").reverse().join("/")
    : "Sin fecha límite";
const hora = (valor: string) =>
  new Intl.DateTimeFormat("es-GT", {
    dateStyle: "short",
    timeStyle: "short",
    timeZone: "America/Guatemala",
  }).format(new Date(valor));

function Paginacion({
  pagina,
  total,
  bloqueado,
  cambiar,
}: {
  pagina: number;
  total: number;
  bloqueado: boolean;
  cambiar: (n: number) => void;
}) {
  return (
    <div className="pagination">
      <span>
        {total
          ? `${pagina * 20 + 1}–${Math.min((pagina + 1) * 20, total)} de ${total}`
          : "Sin registros"}
      </span>
      <div>
        <button
          type="button"
          className="secondary"
          disabled={bloqueado || pagina === 0}
          onClick={() => cambiar(pagina - 1)}
        >
          Anterior
        </button>
        <button
          type="button"
          className="secondary"
          disabled={bloqueado || (pagina + 1) * 20 >= total}
          onClick={() => cambiar(pagina + 1)}
        >
          Siguiente
        </button>
      </div>
    </div>
  );
}

function ClienteForm({
  cliente,
  onSaved,
  onCancel,
}: {
  cliente: Cliente | null;
  onSaved: (id: number) => void;
  onCancel: () => void;
}) {
  const [nombre, setNombre] = useState(cliente?.nombre ?? "");
  const [telefono, setTelefono] = useState(cliente?.telefono ?? "");
  const [direccion, setDireccion] = useState(cliente?.direccion ?? "");
  const [limite, setLimite] = useState(
    cliente?.limite_credito == null ? "" : String(cliente.limite_credito),
  );
  const [error, setError] = useState("");
  const [guardando, setGuardando] = useState(false);
  const [incierto, setIncierto] = useState(false);
  const bloqueo = useRef(false);
  async function guardar(event: FormEvent) {
    event.preventDefault();
    if (!supabase || bloqueo.current || incierto) return;
    setError("");
    let payload;
    try {
      payload = prepararCliente(nombre, telefono, direccion, limite);
    } catch (e) {
      setError((e as Error).message);
      return;
    }
    bloqueo.current = true;
    setGuardando(true);
    let rechazoConfirmado = false;
    try {
      const query = cliente
        ? supabase
            .from("clientes")
            .update(payload)
            .eq("id_cliente", cliente.id_cliente)
        : supabase.from("clientes").insert(payload);
      const { data, error: fallo } = await query.select("id_cliente").single();
      if (fallo) {
        if (
          ["22001", "22003", "23514", "42501", "22P02"].includes(fallo.code)
        ) {
          rechazoConfirmado = true;
          throw new Error(
            "No se guardó el cliente. Revisa los datos y tus permisos.",
          );
        }
        setIncierto(true);
        throw new Error(
          "No pudimos confirmar el guardado. Cierra este formulario y actualiza la lista antes de repetirlo.",
        );
      }
      if (!data?.id_cliente)
        throw new Error("No se pudo confirmar el cliente guardado.");
      onSaved(data.id_cliente);
    } catch (e) {
      setError(
        e instanceof Error
          ? e.message
          : "No se pudo confirmar el guardado. Actualiza la lista antes de repetirlo.",
      );
      // Los errores de transporte pueden ocurrir después de que se haya guardado.
      if (!rechazoConfirmado) setIncierto(true);
    } finally {
      bloqueo.current = false;
      setGuardando(false);
    }
  }
  return (
    <section
      className="catalog-card purchase-panel cobros-section"
      aria-labelledby="cliente-form-titulo"
    >
      <h2 id="cliente-form-titulo">
        {cliente ? "Editar cliente" : "Nuevo cliente"}
      </h2>
      <form onSubmit={guardar}>
        <fieldset className="purchase-fields" disabled={guardando || incierto}>
          <label htmlFor="cliente-nombre">Nombre</label>
          <input
            id="cliente-nombre"
            autoFocus
            required
            maxLength={150}
            value={nombre}
            onChange={(e) => setNombre(e.target.value)}
          />
          <div className="form-grid">
            <div>
              <label htmlFor="cliente-telefono">Teléfono (opcional)</label>
              <input
                id="cliente-telefono"
                type="tel"
                maxLength={20}
                value={telefono}
                onChange={(e) => setTelefono(e.target.value)}
              />
            </div>
            <div>
              <label htmlFor="cliente-limite">
                Límite de crédito (Q, opcional)
              </label>
              <input
                id="cliente-limite"
                inputMode="decimal"
                placeholder="Sin límite definido"
                value={limite}
                onChange={(e) => setLimite(e.target.value)}
              />
            </div>
          </div>
          <small className="muted">
            En blanco: sin tope definido. Q 0.00: sin crédito disponible.
            Cambiar el límite no modifica las deudas existentes.
          </small>
          <label htmlFor="cliente-direccion">Dirección (opcional)</label>
          <input
            id="cliente-direccion"
            maxLength={250}
            value={direccion}
            onChange={(e) => setDireccion(e.target.value)}
          />
        </fieldset>
        {error && (
          <p className="error" role="alert">
            {error}
          </p>
        )}
        <div className="form-actions">
          <button
            type="button"
            className="secondary"
            disabled={guardando}
            onClick={onCancel}
          >
            Cerrar
          </button>
          <button disabled={guardando || incierto}>
            {guardando ? "Guardando…" : "Guardar cliente"}
          </button>
        </div>
      </form>
    </section>
  );
}

function HistorialAbonos({
  cuenta,
  revision,
}: {
  cuenta: Cuenta;
  revision: number;
}) {
  const [pagos, setPagos] = useState<
    {
      id_pago_cuenta_por_cobrar: number;
      fecha: string;
      monto: number;
      forma_pago_id: number;
    }[]
  >([]);
  const [formas, setFormas] = useState<FormaAbono[]>([]);
  const [estado, setEstado] = useState("cargando");
  const [intento, setIntento] = useState(0);
  useEffect(() => {
    const controller = new AbortController();
    async function cargar() {
      if (!supabase) return;
      setEstado("cargando");
      try {
        const [p, f] = await Promise.all([
          supabase
            .from("pagos_cuentas_por_cobrar")
            .select("id_pago_cuenta_por_cobrar,fecha,monto,forma_pago_id")
            .eq("cuenta_por_cobrar_id", cuenta.id_cuenta_por_cobrar)
            .order("fecha", { ascending: false })
            .order("id_pago_cuenta_por_cobrar", { ascending: false })
            .limit(20)
            .abortSignal(controller.signal),
          supabase
            .from("formas_pago")
            .select("id_forma_pago,nombre")
            .abortSignal(controller.signal),
        ]);
        if (controller.signal.aborted) return;
        if (p.error || f.error) throw new Error();
        setPagos(p.data ?? []);
        setFormas(f.data ?? []);
        setEstado("listo");
      } catch {
        if (!controller.signal.aborted) setEstado("error");
      }
    }
    void cargar();
    return () => controller.abort();
  }, [cuenta.id_cuenta_por_cobrar, revision, intento]);
  return (
    <section
      className="catalog-card cobros-section"
      aria-label="Historial de abonos"
    >
      <div className="purchase-panel">
        <h2>Abonos de la venta #{cuenta.venta_id}</h2>
        <p className="muted">Últimos 20 abonos. Horario de Guatemala.</p>
      </div>
      {estado === "cargando" ? (
        <p className="state" role="status">
          Cargando abonos…
        </p>
      ) : estado === "error" ? (
        <div className="purchase-panel">
          <p className="error" role="alert">
            No pudimos cargar los abonos.
          </p>
          <button onClick={() => setIntento((v) => v + 1)}>Reintentar</button>
        </div>
      ) : !pagos.length ? (
        <p className="state">Esta cuenta aún no tiene abonos.</p>
      ) : (
        <div
          className="table-scroll"
          tabIndex={0}
          role="region"
          aria-label="Últimos abonos"
        >
          <table>
            <thead>
              <tr>
                <th>Comprobante</th>
                <th>Fecha</th>
                <th>Forma de pago</th>
                <th className="numeric">Monto</th>
              </tr>
            </thead>
            <tbody>
              {pagos.map((p) => (
                <tr key={p.id_pago_cuenta_por_cobrar}>
                  <td>#{p.id_pago_cuenta_por_cobrar}</td>
                  <td>{hora(p.fecha)}</td>
                  <td>
                    {formas.find((f) => f.id_forma_pago === p.forma_pago_id)
                      ?.nombre ?? "—"}
                  </td>
                  <td className="numeric">{dinero(p.monto)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}

function AbonoForm({
  cuenta,
  userId,
  onRegistered,
}: {
  cuenta: Cuenta | null;
  userId: string;
  onRegistered: () => void;
}) {
  const clave = `tienda:abono-cxc-pendiente:${userId}`;
  const [recuperado] = useState(() => recuperarAbono(clave));
  const [pendiente, setPendiente] = useState<AbonoPayload | null>(
    recuperado.pendiente,
  );
  const [formas, setFormas] = useState<FormaAbono[]>([]);
  const [monto, setMonto] = useState("");
  const [forma, setForma] = useState("");
  const cuentaId = cuenta?.id_cuenta_por_cobrar ?? null;
  const [cuentaAnterior, setCuentaAnterior] = useState(cuentaId);
  if (cuentaAnterior !== cuentaId) {
    setCuentaAnterior(cuentaId);
    setMonto("");
    setForma("");
  }
  const [revision, setRevision] = useState(0);
  const [errorCarga, setErrorCarga] = useState("");
  const [error, setError] = useState("");
  const [guardando, setGuardando] = useState(false);
  const [confirmado, setConfirmado] = useState<AbonoConfirmado | null>(null);
  const bloqueo = useRef(false);
  useEffect(() => {
    const controller = new AbortController();
    async function cargar() {
      if (!supabase) return;
      setErrorCarga("");
      try {
        const r = await supabase
          .from("formas_pago")
          .select("id_forma_pago,nombre")
          .neq("nombre", "CREDITO")
          .order("nombre")
          .abortSignal(controller.signal);
        if (controller.signal.aborted) return;
        if (r.error) throw new Error();
        setFormas(r.data ?? []);
      } catch {
        if (!controller.signal.aborted)
          setErrorCarga("No pudimos cargar las formas de pago.");
      }
    }
    void cargar();
    return () => controller.abort();
  }, [revision]);
  async function enviar(event: FormEvent) {
    event.preventDefault();
    if (!supabase || bloqueo.current || recuperado.error) return;
    setError("");
    let payload = pendiente;
    if (!payload) {
      if (!cuenta) return;
      try {
        payload = prepararAbono(
          cuenta.id_cuenta_por_cobrar,
          monto,
          cuenta.saldo_pendiente,
          formas.find((f) => String(f.id_forma_pago) === forma),
          crypto.randomUUID(),
        );
        localStorage.setItem(clave, JSON.stringify(payload));
      } catch (e) {
        setError(
          e instanceof Error ? e.message : "No se pudo preparar el abono.",
        );
        return;
      }
      setPendiente(payload);
    }
    bloqueo.current = true;
    setGuardando(true);
    setConfirmado(null);
    try {
      const { data, error: fallo } = await supabase.rpc(
        "registrar_abono_cxc",
        payload,
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
          ].includes(fallo.code)
        ) {
          localStorage.removeItem(clave);
          setPendiente(null);
          onRegistered();
          throw new Error(fallo.message);
        }
        throw new Error(
          "No pudimos confirmar la respuesta. Reintenta la misma confirmación; no prepares otro abono.",
        );
      }
      const r = data as AbonoConfirmado;
      if (
        !r ||
        !Number.isSafeInteger(r.id_pago) ||
        r.cuenta_id !== payload.p_cuenta_id ||
        Number(r.monto) !== payload.p_monto ||
        !Number.isFinite(Number(r.saldo_pendiente))
      )
        throw new Error(
          "La respuesta no se pudo verificar. Reintenta la confirmación.",
        );
      // Primero mostramos el comprobante. Si falla la limpieza, el reintento sigue siendo seguro.
      setConfirmado(r);
      try {
        localStorage.removeItem(clave);
        setPendiente(null);
      } catch {
        setError(
          "El abono está registrado. Reintenta la confirmación para limpiar el pendiente de este dispositivo.",
        );
      }
      setMonto("");
      setForma("");
      onRegistered();
    } catch (e) {
      setError(
        e instanceof Error
          ? e.message
          : "No pudimos confirmar el abono. Reintenta la misma confirmación.",
      );
    } finally {
      bloqueo.current = false;
      setGuardando(false);
    }
  }
  const bloqueado = guardando || !!pendiente || !!recuperado.error;
  return (
    <section
      id="registrar-abono"
      className="catalog-card purchase-panel cobros-section"
      aria-labelledby="abono-titulo"
    >
      <h2 id="abono-titulo">Registrar abono</h2>
      {confirmado && (
        <p className="success" role="status">
          Abono #{confirmado.id_pago} confirmado por {dinero(confirmado.monto)}.
          Saldo de la cuenta al confirmar: {dinero(confirmado.saldo_pendiente)}.
        </p>
      )}
      {recuperado.error && (
        <p className="error" role="alert">
          {recuperado.error}
        </p>
      )}
      {pendiente && (
        <p className="inventory-note" role="status">
          Hay una confirmación pendiente de {dinero(pendiente.p_monto)} para la
          cuenta #{pendiente.p_cuenta_id}. Reintenta para verificar si ya quedó
          registrada.
        </p>
      )}
      {!cuenta && !pendiente ? (
        <p className="muted">
          Selecciona un cliente y luego una cuenta para abonar.
        </p>
      ) : (
        <form onSubmit={enviar}>
          {!pendiente && cuenta && (
            <>
              <p>
                Venta #{cuenta.venta_id} · Saldo mostrado:{" "}
                <strong>{dinero(cuenta.saldo_pendiente)}</strong>
              </p>
              <fieldset className="purchase-fields" disabled={bloqueado}>
                <div className="form-grid">
                  <div>
                    <label htmlFor="abono-monto">Monto recibido (Q)</label>
                    <input
                      id="abono-monto"
                      inputMode="decimal"
                      required
                      value={monto}
                      onChange={(e) => setMonto(e.target.value)}
                    />
                  </div>
                  <div>
                    <label htmlFor="abono-forma">Forma de pago</label>
                    <select
                      id="abono-forma"
                      required
                      value={forma}
                      onChange={(e) => setForma(e.target.value)}
                    >
                      <option value="">Selecciona</option>
                      {formas.map((f) => (
                        <option key={f.id_forma_pago} value={f.id_forma_pago}>
                          {f.nombre}
                        </option>
                      ))}
                    </select>
                  </div>
                </div>
              </fieldset>
              <p className="footnote">
                Confirma únicamente el dinero que ya recibiste. El abono reduce
                la deuda; no registra otra venta.
              </p>
            </>
          )}
          <div className="form-actions">
            <button
              disabled={
                guardando ||
                !!recuperado.error ||
                (!pendiente &&
                  (!formas.length ||
                    !!errorCarga ||
                    !cuenta ||
                    cuenta.saldo_pendiente <= 0))
              }
            >
              {guardando
                ? "Confirmando…"
                : pendiente
                  ? "Reintentar confirmación"
                  : "Confirmar abono recibido"}
            </button>
          </div>
        </form>
      )}
      {errorCarga && (
        <div>
          <p className="error" role="alert">
            {errorCarga}
          </p>
          <button
            className="secondary"
            onClick={() => setRevision((v) => v + 1)}
          >
            Cargar formas de pago
          </button>
        </div>
      )}
      {error && (
        <p className="error" role="alert">
          {error}
        </p>
      )}
    </section>
  );
}

function CuentasCliente({
  id,
  activo,
  revision,
  onAbonar,
  onEditar,
}: {
  id: number;
  activo: boolean;
  revision: number;
  onAbonar: (c: Cuenta) => void;
  onEditar: (c: Cliente) => void;
}) {
  const [datos, setDatos] = useState<EstadoCliente | null>(null);
  const [pagina, setPagina] = useState(0);
  const [cargando, setCargando] = useState(true);
  const [error, setError] = useState("");
  const [intento, setIntento] = useState(0);
  const [historial, setHistorial] = useState<Cuenta | null>(null);
  useEffect(() => {
    if (!activo) return;
    const controller = new AbortController();
    async function cargar() {
      if (!supabase) return;
      setCargando(true);
      setError("");
      try {
        const r = await supabase
          .rpc("obtener_cobros_cliente", { p_cliente_id: id, p_pagina: pagina })
          .abortSignal(controller.signal);
        if (controller.signal.aborted) return;
        if (r.error || !r.data?.cliente || !Array.isArray(r.data.cuentas))
          throw new Error();
        setDatos(r.data as EstadoCliente);
      } catch {
        if (!controller.signal.aborted)
          setError("No pudimos cargar las cuentas del cliente.");
      } finally {
        if (!controller.signal.aborted) setCargando(false);
      }
    }
    void cargar();
    return () => controller.abort();
  }, [id, activo, revision, pagina, intento]);
  return (
    <section className="cobros-section" aria-label="Cuentas del cliente">
      {cargando ? (
        <p className="state" role="status">
          Cargando cuentas…
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
          <>
            <div className="section-heading">
              <div>
                <h2>{datos.cliente.nombre}</h2>
                <p className="muted">
                  {datos.cliente.telefono || "Sin teléfono"} · Límite:{" "}
                  {datos.cliente.limite_credito == null
                    ? "sin tope definido"
                    : dinero(datos.cliente.limite_credito)}
                </p>
              </div>
              <button
                className="secondary"
                onClick={() => onEditar(datos.cliente)}
              >
                Editar cliente
              </button>
            </div>
            {datos.cliente.direccion && (
              <p className="muted cobros-texto">{datos.cliente.direccion}</p>
            )}
            <div className="cobros-totales">
              <p>
                Deuda pendiente <strong>{dinero(datos.saldo)}</strong>
              </p>
              <p>
                Deuda vencida <strong>{dinero(datos.vencido)}</strong>
              </p>
            </div>
            <div className="catalog-card">
              <div
                className="table-scroll"
                tabIndex={0}
                role="region"
                aria-label="Cuentas del cliente"
              >
                <table>
                  <thead>
                    <tr>
                      <th>Venta</th>
                      <th className="numeric">Original</th>
                      <th className="numeric">Saldo</th>
                      <th>Fecha límite</th>
                      <th>Estado</th>
                      <th>Acciones</th>
                    </tr>
                  </thead>
                  <tbody>
                    {datos.cuentas.map((c) => (
                      <tr key={c.id_cuenta_por_cobrar}>
                        <td>
                          #{c.venta_id}
                          <span className="history-date">{hora(c.fecha)}</span>
                        </td>
                        <td className="numeric">{dinero(c.monto_original)}</td>
                        <td className="numeric">{dinero(c.saldo_pendiente)}</td>
                        <td>{fecha(c.fecha_limite)}</td>
                        <td>
                          <span
                            className={`badge ${c.estado === "VENCIDA" ? "low" : ""}`}
                          >
                            {c.estado}
                          </span>
                        </td>
                        <td>
                          <div className="cobros-acciones">
                            <button
                              className="secondary"
                              onClick={() => setHistorial(c)}
                            >
                              Ver abonos
                            </button>
                            <button
                              disabled={c.saldo_pendiente <= 0}
                              onClick={() => onAbonar(c)}
                            >
                              Abonar
                            </button>
                          </div>
                        </td>
                      </tr>
                    ))}
                    {!datos.cuentas.length && (
                      <tr>
                        <td colSpan={6}>
                          Este cliente todavía no tiene ventas a crédito
                          registradas.
                        </td>
                      </tr>
                    )}
                  </tbody>
                </table>
              </div>
              <Paginacion
                pagina={pagina}
                total={datos.total}
                bloqueado={cargando}
                cambiar={setPagina}
              />
            </div>
            {historial && (
              <HistorialAbonos
                key={historial.id_cuenta_por_cobrar}
                cuenta={historial}
                revision={revision}
              />
            )}
          </>
        )
      )}
    </section>
  );
}

export default function Clientes({
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
  const [busqueda, setBusqueda] = useState("");
  const [consulta, setConsulta] = useState({ texto: "", pagina: 0 });
  const [datos, setDatos] = useState<ListaClientes>({ total: 0, clientes: [] });
  const [cargando, setCargando] = useState(true);
  const [error, setError] = useState("");
  const [mensaje, setMensaje] = useState("");
  const [intento, setIntento] = useState(0);
  const [elegido, setElegido] = useState<number | null>(null);
  const [editor, setEditor] = useState<{ cliente: Cliente | null } | null>(
    null,
  );
  const [cuenta, setCuenta] = useState<Cuenta | null>(null);
  useEffect(() => {
    if (!activo) return;
    const controller = new AbortController();
    async function cargar() {
      if (!supabase) return;
      setCargando(true);
      setError("");
      try {
        const r = await supabase
          .rpc("listar_clientes_cobros", {
            p_busqueda: consulta.texto,
            p_pagina: consulta.pagina,
          })
          .abortSignal(controller.signal);
        if (controller.signal.aborted) return;
        if (r.error || !Array.isArray(r.data?.clientes)) throw new Error();
        setDatos(r.data as ListaClientes);
      } catch {
        if (!controller.signal.aborted)
          setError("No pudimos cargar los clientes. Comprueba la conexión.");
      } finally {
        if (!controller.signal.aborted) setCargando(false);
      }
    }
    void cargar();
    return () => controller.abort();
  }, [activo, revision, consulta, intento]);
  function actualizar() {
    setIntento((v) => v + 1);
    onChanged();
  }
  return (
    <>
      <div className="section-heading">
        <div>
          <p className="eyebrow">CRÉDITO DE LA TIENDA</p>
          <h1>Clientes y cobros</h1>
          <p className="muted">
            Consulta deudas y registra el dinero que recibes como abono.
          </p>
        </div>
        <div className="catalog-actions">
          <button className="secondary" onClick={actualizar}>
            Actualizar
          </button>
          <button
            onClick={() => {
              setEditor({ cliente: null });
              setMensaje("");
            }}
          >
            Nuevo cliente
          </button>
        </div>
      </div>
      {mensaje && (
        <p className="success" role="status">
          {mensaje}
        </p>
      )}
      {editor && (
        <ClienteForm
          key={editor.cliente?.id_cliente ?? "nuevo"}
          cliente={editor.cliente}
          onCancel={() => setEditor(null)}
          onSaved={(id) => {
            setEditor(null);
            setElegido(id);
            setCuenta(null);
            setMensaje("Cliente guardado. Ya puedes seleccionarlo en Ventas.");
            actualizar();
          }}
        />
      )}
      <section className="catalog-card" aria-label="Lista de clientes">
        <form
          className="search-form"
          onSubmit={(e) => {
            e.preventDefault();
            setConsulta({ texto: busqueda.trim(), pagina: 0 });
          }}
        >
          <label htmlFor="buscar-cliente">Buscar por nombre o teléfono</label>
          <div className="search-controls">
            <input
              id="buscar-cliente"
              maxLength={150}
              value={busqueda}
              onChange={(e) => setBusqueda(e.target.value)}
            />
            <button>Buscar</button>
          </div>
        </form>
        {cargando ? (
          <p className="state" role="status">
            Cargando clientes…
          </p>
        ) : error ? (
          <div className="purchase-panel">
            <p className="error" role="alert">
              {error}
            </p>
            <button onClick={() => setIntento((v) => v + 1)}>Reintentar</button>
          </div>
        ) : (
          <>
            <div
              className="table-scroll"
              tabIndex={0}
              role="region"
              aria-label="Clientes y saldos"
            >
              <table>
                <thead>
                  <tr>
                    <th>Cliente</th>
                    <th>Teléfono</th>
                    <th className="numeric">Deuda</th>
                    <th className="numeric">Vencido</th>
                    <th>Acciones</th>
                  </tr>
                </thead>
                <tbody>
                  {datos.clientes.map((c) => (
                    <tr key={c.id_cliente}>
                      <td className="product-name">{c.nombre}</td>
                      <td>{c.telefono || "—"}</td>
                      <td className="numeric">{dinero(c.saldo)}</td>
                      <td className="numeric">{dinero(c.vencido)}</td>
                      <td>
                        <button
                          className="secondary"
                          onClick={() => {
                            setElegido(c.id_cliente);
                            setCuenta(null);
                          }}
                        >
                          Ver cuentas
                        </button>
                      </td>
                    </tr>
                  ))}
                  {!datos.clientes.length && (
                    <tr>
                      <td colSpan={5}>
                        No hay clientes que coincidan con la búsqueda.
                      </td>
                    </tr>
                  )}
                </tbody>
              </table>
            </div>
            <Paginacion
              pagina={consulta.pagina}
              total={datos.total}
              bloqueado={cargando}
              cambiar={(pagina) => setConsulta((v) => ({ ...v, pagina }))}
            />
          </>
        )}
      </section>
      {elegido != null && (
        <CuentasCliente
          key={elegido}
          id={elegido}
          activo={activo}
          revision={revision + intento}
          onEditar={(cliente) => setEditor({ cliente })}
          onAbonar={(c) => {
            setCuenta(c);
            setTimeout(
              () =>
                document
                  .getElementById("registrar-abono")
                  ?.scrollIntoView({ behavior: "smooth", block: "center" }),
              0,
            );
          }}
        />
      )}
      <AbonoForm
        cuenta={cuenta}
        userId={userId}
        onRegistered={() => {
          setCuenta(null);
          actualizar();
        }}
      />
      <p className="footnote">
        Los saldos suman cuentas de ventas registradas. Una cuenta está vencida
        si conserva saldo y su fecha límite ya pasó, según el horario de
        Guatemala.
      </p>
    </>
  );
}
