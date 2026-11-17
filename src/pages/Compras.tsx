import { useEffect, useRef, useState } from "react";
import type { FormEvent } from "react";
import { supabase } from "../lib/supabase";
import { registrarCompra } from "../services/compras";
import {
  hoyGuatemala,
  prepararCompra,
  totalCompraCentavos,
  cantidadEntera,
  costoCentavos,
} from "../services/compraValidation";
import type {
  CompraGuardada,
  CompraResumen,
  FormaPago,
  LineaCompraForm,
  LoteCompraForm,
  ProductoCompra,
  Proveedor,
} from "../types/compra";

const money = new Intl.NumberFormat("es-GT", {
  style: "currency",
  currency: "GTQ",
});
const dateFormat = new Intl.DateTimeFormat("es-GT", {
  timeZone: "America/Guatemala",
  dateStyle: "short",
  timeStyle: "short",
});
const referencia = () => `REF-${crypto.randomUUID()}`;
const nuevoLote = (): LoteCompraForm => ({
  key: crypto.randomUUID(),
  cantidad: "",
  numero_lote: "",
  fecha_vencimiento: "",
});

export default function Compras({
  onRegistered,
  revisionExterna,
}: {
  onRegistered: () => void;
  revisionExterna: number;
}) {
  const [proveedores, setProveedores] = useState<Proveedor[]>([]);
  const [pagos, setPagos] = useState<FormaPago[]>([]);
  const [history, setHistory] = useState<CompraResumen[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState("");
  const [refresh, setRefresh] = useState(0);
  const [proveedor, setProveedor] = useState("");
  const [pago, setPago] = useState("");
  const [documento, setDocumento] = useState(referencia);
  const [fecha, setFecha] = useState("");
  const [lines, setLines] = useState<LineaCompraForm[]>([]);
  const [search, setSearch] = useState("");
  const [searchBy, setSearchBy] = useState("nombre");
  const [query, setQuery] = useState({ text: "", by: "nombre", version: 0 });
  const [results, setResults] = useState<ProductoCompra[]>([]);
  const [searching, setSearching] = useState(true);
  const [searchError, setSearchError] = useState("");
  const [saving, setSaving] = useState(false);
  const lock = useRef(false);
  const [error, setError] = useState("");
  const [saved, setSaved] = useState<CompraGuardada | null>(null);
  const [supplierOpen, setSupplierOpen] = useState(false);
  const [supplierName, setSupplierName] = useState("");
  const [supplierBusy, setSupplierBusy] = useState(false);
  const [supplierError, setSupplierError] = useState("");
  const supplierLock = useRef(false);

  useEffect(() => {
    const controller = new AbortController();
    async function load() {
      if (!supabase) return;
      setLoading(true);
      setLoadError("");
      try {
        const [vendors, methods, recent] = await Promise.all([
          supabase
            .from("proveedores")
            .select("id_proveedor,nombre")
            .order("nombre")
            .abortSignal(controller.signal),
          supabase
            .from("formas_pago")
            .select("id_forma_pago,nombre")
            .order("nombre")
            .abortSignal(controller.signal),
          supabase
            .from("compras")
            .select(
              "id_compra,proveedor_id,forma_pago_id,numero_documento,fecha,total,estado",
            )
            .order("fecha", { ascending: false })
            .order("id_compra", { ascending: false })
            .limit(30)
            .abortSignal(controller.signal),
        ]);
        if (controller.signal.aborted) return;
        if (vendors.error || methods.error || recent.error)
          throw new Error("load");
        setProveedores(vendors.data ?? []);
        setPagos(methods.data ?? []);
        setHistory((recent.data ?? []) as CompraResumen[]);
      } catch {
        if (!controller.signal.aborted)
          setLoadError(
            "No pudimos cargar proveedores, formas de pago o compras. Inténtalo de nuevo.",
          );
      } finally {
        if (!controller.signal.aborted) setLoading(false);
      }
    }
    void load();
    return () => controller.abort();
  }, [refresh, revisionExterna]);

  useEffect(() => {
    const controller = new AbortController();
    async function load() {
      if (!supabase) return;
      setSearching(true);
      setSearchError("");
      try {
        let request = supabase
          .from("productos")
          .select(
            "id_producto,nombre,codigo_barras,controla_lotes,activo,ultimo_costo",
          )
          .eq("activo", true)
          .order("nombre")
          .order("id_producto")
          .limit(20);
        if (query.text)
          request =
            query.by === "codigo_barras"
              ? request.eq("codigo_barras", query.text)
              : request.ilike(
                  "nombre",
                  `%${query.text.replace(/[\\%_]/g, "\\$&")}%`,
                );
        const { data, error } = await request.abortSignal(controller.signal);
        if (controller.signal.aborted) return;
        if (error) throw error;
        setResults((data ?? []) as ProductoCompra[]);
      } catch {
        if (!controller.signal.aborted) {
          setResults([]);
          setSearchError("No pudimos buscar productos. Vuelve a intentar.");
        }
      } finally {
        if (!controller.signal.aborted) setSearching(false);
      }
    }
    void load();
    return () => controller.abort();
  }, [query]);

  function buscar(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setQuery((q) => ({
      text: search.trim(),
      by: searchBy,
      version: q.version + 1,
    }));
  }
  function add(producto: ProductoCompra) {
    if (
      saving ||
      lines.some((line) => line.producto.id_producto === producto.id_producto)
    )
      return;
    setLines((current) => [
      ...current,
      {
        producto,
        cantidad: "1",
        costo_unitario:
          producto.ultimo_costo === null
            ? ""
            : Number(producto.ultimo_costo).toFixed(2),
        lotes: producto.controla_lotes ? [nuevoLote()] : [],
      },
    ]);
    setError("");
    setSaved(null);
  }
  function update(id: number, values: Partial<LineaCompraForm>) {
    setLines((current) =>
      current.map((line) =>
        line.producto.id_producto === id ? { ...line, ...values } : line,
      ),
    );
    setError("");
  }
  function updateLote(
    line: LineaCompraForm,
    key: string,
    values: Partial<LoteCompraForm>,
  ) {
    update(line.producto.id_producto, {
      lotes: line.lotes.map((lote) =>
        lote.key === key ? { ...lote, ...values } : lote,
      ),
    });
  }
  async function save(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (lock.current || loading || loadError) return;
    setError("");
    setSaved(null);
    if (!proveedores.some((v) => String(v.id_proveedor) === proveedor)) {
      setError("Selecciona un proveedor disponible.");
      return;
    }
    try {
      const payload = prepararCompra(
        proveedor,
        pagos.find((p) => String(p.id_forma_pago) === pago),
        documento,
        fecha,
        lines,
      );
      lock.current = true;
      setSaving(true);
      const result = await registrarCompra(payload);
      setSaved(result);
      setLines([]);
      setDocumento(referencia());
      setFecha("");
      setRefresh((v) => v + 1);
      onRegistered();
    } catch (err) {
      setError(
        err instanceof Error
          ? err.message
          : "No pudimos confirmar el registro. Revisa el historial antes de reintentar.",
      );
    } finally {
      lock.current = false;
      setSaving(false);
    }
  }
  async function createSupplier(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!supabase || supplierLock.current) return;
    const nombre = supplierName.trim();
    if (!nombre || nombre.length > 150) {
      setSupplierError("Escribe un nombre de hasta 150 caracteres.");
      return;
    }
    supplierLock.current = true;
    setSupplierBusy(true);
    setSupplierError("");
    try {
      const { data, error } = await supabase
        .from("proveedores")
        .insert({ nombre })
        .select("id_proveedor,nombre")
        .single();
      if (error || !data) throw new Error("save");
      setProveedores((current) =>
        [...current, data].sort((a, b) => a.nombre.localeCompare(b.nombre)),
      );
      setProveedor(String(data.id_proveedor));
      setSupplierOpen(false);
      setSupplierName("");
    } catch {
      setSupplierError(
        "No pudimos confirmar el proveedor. Actualiza los datos antes de reintentar.",
      );
    } finally {
      supplierLock.current = false;
      setSupplierBusy(false);
    }
  }
  let total: number | null = null;
  try {
    total = totalCompraCentavos(lines) / 100;
  } catch {
    /* Se muestra pendiente hasta completar los datos. */
  }
  const credit =
    pagos.find((p) => String(p.id_forma_pago) === pago)?.nombre === "CREDITO";

  return (
    <section aria-labelledby="compras-title">
      <div className="section-heading">
        <div>
          <p className="eyebrow">ENTRADA DE MERCADERÍA</p>
          <h1 id="compras-title">Compras</h1>
          <p className="muted">
            Registra lo que recibes y actualiza tu inventario.
          </p>
        </div>
        <button
          className="secondary"
          disabled={loading || saving || supplierBusy}
          onClick={() => setRefresh((v) => v + 1)}
        >
          Actualizar datos
        </button>
      </div>
      {saved && (
        <p className="success" role="status">
          Compra #{saved.id_compra} registrada por{" "}
          {money.format(Number(saved.total))}. El inventario se actualizó
          correctamente.
        </p>
      )}
      {loadError && (
        <p className="error" role="alert">
          {loadError}
        </p>
      )}
      {loading && <p role="status">Cargando datos de compras…</p>}
      <div className="purchase-layout">
        <div className="catalog-card purchase-panel">
          <h2>1. Datos de la compra</h2>
          <div className="supplier-toolbar">
            <button
              type="button"
              className="secondary"
              disabled={saving || supplierBusy}
              onClick={() => {
                setSupplierOpen(!supplierOpen);
                setSupplierError("");
              }}
            >
              {" "}
              {supplierOpen ? "Cerrar nuevo proveedor" : "Nuevo proveedor"}
            </button>
          </div>
          {supplierOpen && (
            <form className="supplier-form" onSubmit={createSupplier}>
              <label htmlFor="supplier-name">Nombre del nuevo proveedor</label>
              <input
                id="supplier-name"
                value={supplierName}
                onChange={(e) => setSupplierName(e.target.value)}
                maxLength={150}
                required
                disabled={supplierBusy}
              />
              {supplierError && (
                <p className="error" role="alert">
                  {supplierError}
                </p>
              )}
              <button disabled={supplierBusy}>
                {supplierBusy ? "Guardando…" : "Guardar proveedor"}
              </button>
            </form>
          )}
          <form id="purchase-form" onSubmit={save}>
            <fieldset
              disabled={saving || loading || !!loadError || supplierBusy}
              className="purchase-fields"
            >
              <label htmlFor="purchase-supplier">Proveedor *</label>
              <select
                id="purchase-supplier"
                value={proveedor}
                onChange={(e) => {
                  setProveedor(e.target.value);
                  setSaved(null);
                }}
                required
              >
                <option value="">Selecciona un proveedor</option>
                {proveedores.map((v) => (
                  <option key={v.id_proveedor} value={v.id_proveedor}>
                    {v.nombre}
                  </option>
                ))}
              </select>
              <label htmlFor="purchase-document">Factura o referencia *</label>
              <input
                id="purchase-document"
                value={documento}
                onChange={(e) => {
                  setDocumento(e.target.value);
                  setSaved(null);
                }}
                maxLength={100}
                required
                aria-describedby="reference-help"
              />
              <small id="reference-help" className="muted">
                Usa el número de factura o conserva la referencia generada si no
                tienes documento.
              </small>
              <label htmlFor="purchase-payment">Forma de pago *</label>
              <select
                id="purchase-payment"
                value={pago}
                onChange={(e) => setPago(e.target.value)}
                required
              >
                <option value="">Selecciona una forma de pago</option>
                {pagos.map((p) => (
                  <option key={p.id_forma_pago} value={p.id_forma_pago}>
                    {p.nombre}
                  </option>
                ))}
              </select>
              {credit && (
                <>
                  <label htmlFor="purchase-due">
                    Fecha límite de pago (opcional)
                  </label>
                  <input
                    id="purchase-due"
                    type="date"
                    min={hoyGuatemala()}
                    value={fecha}
                    onChange={(e) => setFecha(e.target.value)}
                  />
                  <small className="muted">
                    Se creará una cuenta por pagar con el total de la compra.
                  </small>
                </>
              )}
            </fieldset>
          </form>
        </div>
        <div className="catalog-card purchase-panel">
          <h2>2. Agrega los productos</h2>
          <form onSubmit={buscar} className="purchase-search">
            <label htmlFor="purchase-search-by">Buscar por</label>
            <select
              id="purchase-search-by"
              value={searchBy}
              onChange={(e) => setSearchBy(e.target.value)}
            >
              <option value="nombre">Nombre</option>
              <option value="codigo_barras">Código de barras exacto</option>
            </select>
            <label htmlFor="purchase-search">Producto</label>
            <div className="search-controls">
              <input
                id="purchase-search"
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                placeholder={
                  searchBy === "nombre"
                    ? "Ej. leche"
                    : "Escanea o escribe el código"
                }
              />
              <button disabled={searching || saving}>Buscar</button>
            </div>
          </form>
          <div aria-live="polite">
            {searching ? (
              <p>Cargando productos…</p>
            ) : searchError ? (
              <p className="error" role="alert">
                {searchError}
              </p>
            ) : results.length === 0 ? (
              <p className="muted">
                No encontramos productos activos con esa búsqueda.
              </p>
            ) : (
              <>
                <p className="footnote">
                  Hasta 20 coincidencias. Afina la búsqueda para encontrar otro
                  producto.
                </p>
                <ul className="purchase-results">
                  {results.map((product) => (
                    <li key={product.id_producto}>
                      <div>
                        <strong>{product.nombre}</strong>
                        <small className="muted">
                          {product.codigo_barras || "Sin código"} ·{" "}
                          {product.controla_lotes ? "Con lotes" : "Sin lotes"}
                        </small>
                      </div>
                      <button
                        type="button"
                        className="secondary"
                        aria-label={`Agregar ${product.nombre} a la compra`}
                        disabled={
                          saving ||
                          lines.some(
                            (line) =>
                              line.producto.id_producto === product.id_producto,
                          )
                        }
                        onClick={() => add(product)}
                      >
                        {lines.some(
                          (line) =>
                            line.producto.id_producto === product.id_producto,
                        )
                          ? "Agregado"
                          : "Agregar"}
                      </button>
                    </li>
                  ))}
                </ul>
              </>
            )}
          </div>
        </div>
      </div>
      <div className="catalog-card purchase-panel purchase-detail">
        <h2>3. Cantidades y costos</h2>
        <p className="muted">
          El costo es por unidad, no el total de la caja o paquete.
        </p>
        {lines.length === 0 ? (
          <p className="state">Agrega productos para preparar la compra.</p>
        ) : (
          lines.map((line) => {
            let subtotal: number | null = null;
            try {
              subtotal =
                (cantidadEntera(line.cantidad) *
                  costoCentavos(line.costo_unitario)) /
                100;
            } catch {
              /* Entrada incompleta. */
            }
            return (
              <fieldset
                className="purchase-line"
                key={line.producto.id_producto}
                disabled={saving}
              >
                <legend>{line.producto.nombre}</legend>
                <div className="purchase-line-grid">
                  <div>
                    <label htmlFor={`qty-${line.producto.id_producto}`}>
                      Cantidad *
                    </label>
                    <input
                      id={`qty-${line.producto.id_producto}`}
                      type="number"
                      min="1"
                      max="2147483647"
                      step="1"
                      value={line.cantidad}
                      onChange={(e) =>
                        update(line.producto.id_producto, {
                          cantidad: e.target.value,
                        })
                      }
                      required
                      form="purchase-form"
                    />
                  </div>
                  <div>
                    <label htmlFor={`cost-${line.producto.id_producto}`}>
                      Costo unitario (Q) *
                    </label>
                    <input
                      id={`cost-${line.producto.id_producto}`}
                      inputMode="decimal"
                      value={line.costo_unitario}
                      onChange={(e) =>
                        update(line.producto.id_producto, {
                          costo_unitario: e.target.value,
                        })
                      }
                      maxLength={20}
                      required
                      form="purchase-form"
                    />
                  </div>
                  <div className="line-subtotal">
                    <span>Subtotal</span>
                    <strong>
                      {subtotal === null ? "Pendiente" : money.format(subtotal)}
                    </strong>
                  </div>
                  <button
                    type="button"
                    className="secondary"
                    onClick={() =>
                      setLines((current) =>
                        current.filter(
                          (l) =>
                            l.producto.id_producto !==
                            line.producto.id_producto,
                        ),
                      )
                    }
                  >
                    Quitar
                  </button>
                </div>
                {line.producto.controla_lotes && (
                  <div className="lots-editor">
                    <h3>Lotes recibidos</h3>
                    <p className="footnote">
                      La suma de las cantidades de los lotes debe coincidir con
                      la cantidad del producto.
                    </p>
                    {line.lotes.map((lote, index) => (
                      <div className="lot-row" key={lote.key}>
                        <div>
                          <label htmlFor={`lot-qty-${lote.key}`}>
                            Cantidad lote {index + 1} *
                          </label>
                          <input
                            id={`lot-qty-${lote.key}`}
                            type="number"
                            min="1"
                            step="1"
                            max="2147483647"
                            value={lote.cantidad}
                            onChange={(e) =>
                              updateLote(line, lote.key, {
                                cantidad: e.target.value,
                              })
                            }
                            required
                            form="purchase-form"
                          />
                        </div>
                        <div>
                          <label htmlFor={`lot-number-${lote.key}`}>
                            Número (opcional)
                          </label>
                          <input
                            id={`lot-number-${lote.key}`}
                            value={lote.numero_lote}
                            onChange={(e) =>
                              updateLote(line, lote.key, {
                                numero_lote: e.target.value,
                              })
                            }
                            maxLength={150}
                          />
                        </div>
                        <div>
                          <label htmlFor={`lot-date-${lote.key}`}>
                            Vencimiento (opcional)
                          </label>
                          <input
                            id={`lot-date-${lote.key}`}
                            type="date"
                            min={hoyGuatemala()}
                            value={lote.fecha_vencimiento}
                            onChange={(e) =>
                              updateLote(line, lote.key, {
                                fecha_vencimiento: e.target.value,
                              })
                            }
                            form="purchase-form"
                          />
                        </div>
                        <button
                          type="button"
                          className="secondary"
                          aria-label={`Quitar lote ${index + 1} de ${line.producto.nombre}`}
                          onClick={() =>
                            update(line.producto.id_producto, {
                              lotes: line.lotes.filter(
                                (l) => l.key !== lote.key,
                              ),
                            })
                          }
                        >
                          Quitar lote
                        </button>
                      </div>
                    ))}
                    <button
                      type="button"
                      className="secondary"
                      onClick={() =>
                        update(line.producto.id_producto, {
                          lotes: [...line.lotes, nuevoLote()],
                        })
                      }
                    >
                      Añadir lote
                    </button>
                  </div>
                )}
              </fieldset>
            );
          })
        )}
        {error && (
          <p className="error" role="alert">
            {error}
          </p>
        )}
        <div className="purchase-summary">
          <div>
            <span>Total de la compra</span>
            <strong>
              {total === null
                ? "Completa cantidades y costos"
                : money.format(total)}
            </strong>
          </div>
          <button
            type="submit"
            form="purchase-form"
            disabled={
              saving || loading || !!loadError || supplierBusy || !lines.length
            }
          >
            {saving ? "Registrando compra…" : "Registrar compra"}
          </button>
        </div>
        <p className="footnote">
          Al registrar se guardarán la compra y las entradas de inventario en
          una sola operación.
        </p>
      </div>
      <section
        className="catalog-card purchase-history"
        aria-labelledby="history-title"
      >
        <div className="purchase-panel">
          <h2 id="history-title">Últimas compras</h2>
          <p className="muted">
            Las 30 más recientes. Revisa la referencia antes de repetir un
            registro.
          </p>
        </div>
        {loading ? (
          <p className="state">Cargando historial…</p>
        ) : loadError ? (
          <p className="state">El historial no se pudo actualizar.</p>
        ) : !history.length ? (
          <p className="state">Todavía no hay compras.</p>
        ) : (
          <div className="table-scroll">
            <table>
              <caption className="sr-only">Últimas compras registradas</caption>
              <thead>
                <tr>
                  <th>Compra / fecha</th>
                  <th>Proveedor</th>
                  <th>Referencia</th>
                  <th>Pago</th>
                  <th className="numeric">Total</th>
                  <th>Estado</th>
                </tr>
              </thead>
              <tbody>
                {history.map((compra) => (
                  <tr key={compra.id_compra}>
                    <td>
                      #{compra.id_compra}
                      <small className="history-date">
                        {dateFormat.format(new Date(compra.fecha))}
                      </small>
                    </td>
                    <td>
                      {proveedores.find(
                        (v) => v.id_proveedor === compra.proveedor_id,
                      )?.nombre ?? `Proveedor #${compra.proveedor_id}`}
                    </td>
                    <td>{compra.numero_documento || "Sin referencia"}</td>
                    <td>
                      {pagos.find(
                        (p) => p.id_forma_pago === compra.forma_pago_id,
                      )?.nombre ?? "—"}
                    </td>
                    <td className="numeric">
                      {money.format(Number(compra.total))}
                    </td>
                    <td>
                      <span
                        className={`badge ${compra.estado === "ANULADA" ? "inactive" : ""}`}
                      >
                        {compra.estado}
                      </span>
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
