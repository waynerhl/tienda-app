import { useEffect, useRef, useState } from "react";
import type { FormEvent } from "react";
import { supabase } from "../lib/supabase";
import { prepararAbono, recuperarAbono } from "../services/cobroValidation";
import type { AbonoConfirmado, AbonoPayload, FormaAbono } from "../types/cobro";
type CuentaAbono = {
  id_cuenta: number;
  referencia: string;
  saldo_pendiente: number;
};
const dinero = (valor: number) =>
  new Intl.NumberFormat("es-GT", { style: "currency", currency: "GTQ" }).format(
    Number(valor),
  );

export default function AbonoCuenta({
  tipo = "cxc",
  cuenta,
  userId,
  onRegistered,
}: {
  tipo?: "cxc" | "cxp";
  cuenta: CuentaAbono | null;
  userId: string;
  onRegistered: () => void;
}) {
  const esPago = tipo === "cxp";
  const clave = `tienda:abono-${tipo}-pendiente:${userId}`;
  const [recuperado] = useState(() => recuperarAbono(clave));
  const [pendiente, setPendiente] = useState<AbonoPayload | null>(
    recuperado.pendiente,
  );
  const [formas, setFormas] = useState<FormaAbono[]>([]);
  const [monto, setMonto] = useState("");
  const [forma, setForma] = useState("");
  const [fondo, setFondo] = useState<"CAJA" | "RESERVA">("CAJA");
  const cuentaId = cuenta?.id_cuenta ?? null;
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
          cuenta.id_cuenta,
          monto,
          cuenta.saldo_pendiente,
          formas.find((f) => String(f.id_forma_pago) === forma),
          crypto.randomUUID(),
        );
        if (esPago) payload.p_fondo = formas.find(f => String(f.id_forma_pago) === forma)?.nombre === "EFECTIVO" ? fondo : "CAJA";
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
        esPago ? "registrar_abono_cxp_fondo" : "registrar_abono_cxc",
        esPago ? { ...payload, p_fondo: payload.p_fondo ?? "CAJA" } : payload,
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
          ].includes(fallo.code) && !(pendiente && fallo.code === "42501")
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
      id={`registrar-abono-${tipo}`}
      className="catalog-card purchase-panel cobros-section"
      aria-labelledby={`abono-titulo-${tipo}`}
    >
      <h2 id={`abono-titulo-${tipo}`}>
        {esPago ? "Registrar pago a proveedor" : "Registrar abono"}
      </h2>
      {confirmado && (
        <p className="success" role="status">
          Abono #{confirmado.id_pago} confirmado por {dinero(confirmado.monto)}.
          Saldo de la cuenta al confirmar: {dinero(confirmado.saldo_pendiente)}. {esPago && confirmado.fondo_efectivo === "RESERVA" && <>Pagado desde Reserva.</>}
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
          registrada. {esPago && pendiente.p_fondo === "RESERVA" && <>Desde Reserva.</>}
        </p>
      )}
      {!cuenta && !pendiente ? (
        <p className="muted">
          Selecciona {esPago ? "un proveedor" : "un cliente"} y luego una cuenta
          para abonar.
        </p>
      ) : (
        <form onSubmit={enviar}>
          {!pendiente && cuenta && (
            <>
              <p>
                {cuenta.referencia} · Saldo mostrado:{" "}
                <strong>{dinero(cuenta.saldo_pendiente)}</strong>
              </p>
              <fieldset className="purchase-fields" disabled={bloqueado}>
                <div className="form-grid">
                  <div>
                    <label htmlFor={`abono-monto-${tipo}`}>
                      {esPago ? "Monto entregado (Q)" : "Monto recibido (Q)"}
                    </label>
                    <input
                      id={`abono-monto-${tipo}`}
                      inputMode="decimal"
                      required
                      value={monto}
                      onChange={(e) => setMonto(e.target.value)}
                    />
                  </div>
                  <div>
                    <label htmlFor={`abono-forma-${tipo}`}>Forma de pago</label>
                    <select
                      id={`abono-forma-${tipo}`}
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
              {esPago && formas.find(f => String(f.id_forma_pago) === forma)?.nombre === "EFECTIVO" && <div><label htmlFor="abono-fondo">Pagar efectivo desde</label><select id="abono-fondo" value={fondo} disabled={bloqueado} onChange={e => setFondo(e.target.value as "CAJA" | "RESERVA")}><option value="CAJA">Caja de atención</option><option value="RESERVA">Reserva (administrador)</option></select></div>}
              <p className="footnote">
                {esPago
                  ? "Confirma únicamente el dinero que ya entregaste al proveedor. El abono reduce la cuenta de esa compra."
                  : "Confirma únicamente el dinero que ya recibiste. El abono reduce la deuda; no registra otra venta."}
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
                  : esPago
                    ? "Confirmar pago entregado"
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
