import AbonoCuenta from "../components/AbonoCuenta";
import { useEffect, useRef, useState } from "react";
import type { FormEvent } from "react";
import { supabase } from "../lib/supabase";
import { prepararProveedor } from "../services/proveedorValidation";
import type {
  Proveedor,
  CuentaProveedor,
  EstadoProveedor,
  FormaAbono,
  ListaProveedores,
} from "../types/pagoProveedor";

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

function ProveedorForm({
  proveedor,
  onSaved,
  onCancel,
}: {
  proveedor: Proveedor | null;
  onSaved: (id: number) => void;
  onCancel: () => void;
}) {
  const [nombre, setNombre] = useState(proveedor?.nombre ?? "");
  const [telefono, setTelefono] = useState(proveedor?.telefono ?? "");
  const [direccion, setDireccion] = useState(proveedor?.direccion ?? "");
  const [correo, setCorreo] = useState(proveedor?.correo ?? "");
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
      payload = prepararProveedor(nombre, telefono, direccion, correo);
    } catch (e) {
      setError((e as Error).message);
      return;
    }
    bloqueo.current = true;
    setGuardando(true);
    let rechazoConfirmado = false;
    try {
      const query = proveedor
        ? supabase
            .from("proveedores")
            .update(payload)
            .eq("id_proveedor", proveedor.id_proveedor)
        : supabase.from("proveedores").insert(payload);
      const { data, error: fallo } = await query
        .select("id_proveedor")
        .single();
      if (fallo) {
        if (
          ["22001", "22003", "23514", "42501", "22P02"].includes(fallo.code)
        ) {
          rechazoConfirmado = true;
          throw new Error(
            "No se guardó el proveedor. Revisa los datos y tus permisos.",
          );
        }
        setIncierto(true);
        throw new Error(
          "No pudimos confirmar el guardado. Cierra este formulario y actualiza la lista antes de repetirlo.",
        );
      }
      if (!data?.id_proveedor)
        throw new Error("No se pudo confirmar el proveedor guardado.");
      onSaved(data.id_proveedor);
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
      aria-labelledby="proveedor-form-titulo"
    >
      <h2 id="proveedor-form-titulo">
        {proveedor ? "Editar proveedor" : "Nuevo proveedor"}
      </h2>
      <form onSubmit={guardar}>
        <fieldset className="purchase-fields" disabled={guardando || incierto}>
          <label htmlFor="proveedor-nombre">Nombre</label>
          <input
            id="proveedor-nombre"
            autoFocus
            required
            maxLength={150}
            value={nombre}
            onChange={(e) => setNombre(e.target.value)}
          />
          <div className="form-grid">
            <div>
              <label htmlFor="proveedor-telefono">Teléfono (opcional)</label>
              <input
                id="proveedor-telefono"
                type="tel"
                maxLength={20}
                value={telefono}
                onChange={(e) => setTelefono(e.target.value)}
              />
            </div>
            <div>
              <label htmlFor="proveedor-correo">Correo (opcional)</label>
              <input
                id="proveedor-correo"
                type="email"
                maxLength={150}
                value={correo}
                onChange={(e) => setCorreo(e.target.value)}
              />
            </div>
          </div>
          <label htmlFor="proveedor-direccion">Dirección (opcional)</label>
          <input
            id="proveedor-direccion"
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
            {guardando ? "Guardando…" : "Guardar proveedor"}
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
  cuenta: CuentaProveedor;
  revision: number;
}) {
  const [pagos, setPagos] = useState<
    {
      id_pago_cuenta_por_pagar: number;
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
            .from("pagos_cuentas_por_pagar")
            .select("id_pago_cuenta_por_pagar,fecha,monto,forma_pago_id")
            .eq("cuenta_por_pagar_id", cuenta.id_cuenta_por_pagar)
            .order("fecha", { ascending: false })
            .order("id_pago_cuenta_por_pagar", { ascending: false })
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
  }, [cuenta.id_cuenta_por_pagar, revision, intento]);
  return (
    <section
      className="catalog-card cobros-section"
      aria-label="Historial de abonos"
    >
      <div className="purchase-panel">
        <h2>Pagos de la compra #{cuenta.compra_id}</h2>
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
                <tr key={p.id_pago_cuenta_por_pagar}>
                  <td>#{p.id_pago_cuenta_por_pagar}</td>
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

function CuentasProveedor({
  id,
  activo,
  revision,
  onAbonar,
  onEditar,
}: {
  id: number;
  activo: boolean;
  revision: number;
  onAbonar: (c: CuentaProveedor) => void;
  onEditar: (c: Proveedor) => void;
}) {
  const [datos, setDatos] = useState<EstadoProveedor | null>(null);
  const [pagina, setPagina] = useState(0);
  const [cargando, setCargando] = useState(true);
  const [error, setError] = useState("");
  const [intento, setIntento] = useState(0);
  const [historial, setHistorial] = useState<CuentaProveedor | null>(null);
  useEffect(() => {
    if (!activo) return;
    const controller = new AbortController();
    async function cargar() {
      if (!supabase) return;
      setCargando(true);
      setError("");
      try {
        const r = await supabase
          .rpc("obtener_pagos_proveedor", {
            p_proveedor_id: id,
            p_pagina: pagina,
          })
          .abortSignal(controller.signal);
        if (controller.signal.aborted) return;
        if (r.error || !r.data?.proveedor || !Array.isArray(r.data.cuentas))
          throw new Error();
        setDatos(r.data as EstadoProveedor);
      } catch {
        if (!controller.signal.aborted)
          setError("No pudimos cargar las cuentas del proveedor.");
      } finally {
        if (!controller.signal.aborted) setCargando(false);
      }
    }
    void cargar();
    return () => controller.abort();
  }, [id, activo, revision, pagina, intento]);
  return (
    <section className="cobros-section" aria-label="Cuentas del proveedor">
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
                <h2>{datos.proveedor.nombre}</h2>
                <p className="muted">
                  {datos.proveedor.telefono || "Sin teléfono"} ·{" "}
                  {datos.proveedor.correo || "Sin correo"}
                </p>
              </div>
              <button
                className="secondary"
                onClick={() => onEditar(datos.proveedor)}
              >
                Editar proveedor
              </button>
            </div>
            {datos.proveedor.direccion && (
              <p className="muted cobros-texto">{datos.proveedor.direccion}</p>
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
                aria-label="Cuentas del proveedor"
              >
                <table>
                  <thead>
                    <tr>
                      <th>Compra / documento</th>
                      <th className="numeric">Original</th>
                      <th className="numeric">Saldo</th>
                      <th>Fecha límite</th>
                      <th>Estado</th>
                      <th>Acciones</th>
                    </tr>
                  </thead>
                  <tbody>
                    {datos.cuentas.map((c) => (
                      <tr key={c.id_cuenta_por_pagar}>
                        <td>
                          #{c.compra_id}
                          <span className="history-date">
                            {c.numero_documento || "Sin documento"}
                          </span>
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
                              Ver pagos
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
                          Este proveedor todavía no tiene compras a crédito
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
                key={historial.id_cuenta_por_pagar}
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

export default function Proveedores({
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
  const [datos, setDatos] = useState<ListaProveedores>({
    total: 0,
    proveedores: [],
  });
  const [cargando, setCargando] = useState(true);
  const [error, setError] = useState("");
  const [mensaje, setMensaje] = useState("");
  const [intento, setIntento] = useState(0);
  const [elegido, setElegido] = useState<number | null>(null);
  const [editor, setEditor] = useState<{ proveedor: Proveedor | null } | null>(
    null,
  );
  const [cuenta, setCuenta] = useState<CuentaProveedor | null>(null);
  useEffect(() => {
    if (!activo) return;
    const controller = new AbortController();
    async function cargar() {
      if (!supabase) return;
      setCargando(true);
      setError("");
      try {
        const r = await supabase
          .rpc("listar_proveedores_pagos", {
            p_busqueda: consulta.texto,
            p_pagina: consulta.pagina,
          })
          .abortSignal(controller.signal);
        if (controller.signal.aborted) return;
        if (r.error || !Array.isArray(r.data?.proveedores)) throw new Error();
        setDatos(r.data as ListaProveedores);
      } catch {
        if (!controller.signal.aborted)
          setError("No pudimos cargar los proveedores. Comprueba la conexión.");
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
          <p className="eyebrow">PAGOS A PROVEEDORES</p>
          <h1>Proveedores y pagos</h1>
          <p className="muted">
            Consulta tus deudas por compras y registra los pagos que entregas.
          </p>
        </div>
        <div className="catalog-actions">
          <button className="secondary" onClick={actualizar}>
            Actualizar
          </button>
          <button
            onClick={() => {
              setEditor({ proveedor: null });
              setMensaje("");
            }}
          >
            Nuevo proveedor
          </button>
        </div>
      </div>
      {mensaje && (
        <p className="success" role="status">
          {mensaje}
        </p>
      )}
      {editor && (
        <ProveedorForm
          key={editor.proveedor?.id_proveedor ?? "nuevo"}
          proveedor={editor.proveedor}
          onCancel={() => setEditor(null)}
          onSaved={(id) => {
            setEditor(null);
            setElegido(id);
            setCuenta(null);
            setMensaje(
              "Proveedor guardado. Ya puedes seleccionarlo en Compras.",
            );
            actualizar();
          }}
        />
      )}
      <section className="catalog-card" aria-label="Lista de proveedores">
        <form
          className="search-form"
          onSubmit={(e) => {
            e.preventDefault();
            setConsulta({ texto: busqueda.trim(), pagina: 0 });
          }}
        >
          <label htmlFor="buscar-proveedor">Buscar por nombre o teléfono</label>
          <div className="search-controls">
            <input
              id="buscar-proveedor"
              maxLength={150}
              value={busqueda}
              onChange={(e) => setBusqueda(e.target.value)}
            />
            <button>Buscar</button>
          </div>
        </form>
        {cargando ? (
          <p className="state" role="status">
            Cargando proveedores…
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
              aria-label="Proveedores y saldos"
            >
              <table>
                <thead>
                  <tr>
                    <th>Proveedor</th>
                    <th>Teléfono</th>
                    <th className="numeric">Deuda</th>
                    <th className="numeric">Vencido</th>
                    <th>Acciones</th>
                  </tr>
                </thead>
                <tbody>
                  {datos.proveedores.map((c) => (
                    <tr key={c.id_proveedor}>
                      <td className="product-name">{c.nombre}</td>
                      <td>{c.telefono || "—"}</td>
                      <td className="numeric">{dinero(c.saldo)}</td>
                      <td className="numeric">{dinero(c.vencido)}</td>
                      <td>
                        <button
                          className="secondary"
                          onClick={() => {
                            setElegido(c.id_proveedor);
                            setCuenta(null);
                          }}
                        >
                          Ver cuentas
                        </button>
                      </td>
                    </tr>
                  ))}
                  {!datos.proveedores.length && (
                    <tr>
                      <td colSpan={5}>
                        No hay proveedores que coincidan con la búsqueda.
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
        <CuentasProveedor
          key={elegido}
          id={elegido}
          activo={activo}
          revision={revision + intento}
          onEditar={(proveedor) => setEditor({ proveedor })}
          onAbonar={(c) => {
            setCuenta(c);
            setTimeout(
              () =>
                document
                  .getElementById("registrar-abono-cxp")
                  ?.scrollIntoView({ behavior: "smooth", block: "center" }),
              0,
            );
          }}
        />
      )}
      <AbonoCuenta
        tipo="cxp"
        cuenta={
          cuenta
            ? {
                id_cuenta: cuenta.id_cuenta_por_pagar,
                referencia: `Compra #${cuenta.compra_id}`,
                saldo_pendiente: cuenta.saldo_pendiente,
              }
            : null
        }
        userId={userId}
        onRegistered={() => {
          setCuenta(null);
          actualizar();
        }}
      />
      <p className="footnote">
        Los saldos suman cuentas de compras registradas. Una cuenta está vencida
        si conserva saldo y su fecha límite ya pasó, según el horario de
        Guatemala.
      </p>
    </>
  );
}
