import { useEffect, useRef, useState } from "react";
import type { FormEvent } from "react";
import { supabase } from "../lib/supabase";
import {
  prepararPartida,
  recuperarPartida,
  csvListaCompras,
} from "../services/listaComprasValidation";
import type {
  ItemLista,
  ListaPayload,
} from "../services/listaComprasValidation";
import "./Efectivo.css";
import "./ListaCompras.css";
type DatosLista = {
  fecha: string;
  total_candidatos: number;
  candidatos: ItemLista[];
  lista: ItemLista[];
  partidas: number;
  unidades: number;
  subtotal_con_costo: number;
  sin_costo: number;
};
const dinero = (n: number) =>
  new Intl.NumberFormat("es-GT", { style: "currency", currency: "GTQ" }).format(
    Number(n),
  );
function PartidaForm({
  item,
  bloqueado,
  onPrepare,
  onCancel,
}: {
  item: ItemLista;
  bloqueado: boolean;
  onPrepare: (p: ListaPayload) => void;
  onCancel: () => void;
}) {
  const [cantidad, setCantidad] = useState(() =>
    String(
      item.en_lista
        ? (item.cantidad ?? item.cantidad_lista ?? "")
        : (item.cantidad_sugerida ?? ""),
    ),
  );
  const [nota, setNota] = useState(item.nota ?? item.nota_lista);
  const [error, setError] = useState("");
  function preparar(e: FormEvent) {
    e.preventDefault();
    if (bloqueado) return;
    setError("");
    try {
      onPrepare(prepararPartida(item, cantidad, nota, crypto.randomUUID()));
    } catch (e) {
      setError(e instanceof Error ? e.message : "Revisa los datos.");
    }
  }
  return (
    <section
      id="lista-editor"
      className="catalog-card purchase-panel cobros-section"
    >
      <h2>
        {item.en_lista ? "Editar partida" : "Añadir a la lista"}: {item.nombre}
      </h2>
      <p className="muted">
        Existencia total: {item.existencia} · Disponible según lotes:{" "}
        {item.disponible} · Mínimo: {item.existencia_minima}
      </p>
      <form onSubmit={preparar}>
        <fieldset className="purchase-fields" disabled={bloqueado}>
          <label htmlFor="lista-cantidad">Unidades que quieres comprar</label>
          <input
            id="lista-cantidad"
            required
            inputMode="numeric"
            value={cantidad}
            onChange={(e) => setCantidad(e.target.value)}
          />
          <label htmlFor="lista-nota">Nota (opcional)</label>
          <textarea
            id="lista-nota"
            maxLength={500}
            value={nota}
            onChange={(e) => setNota(e.target.value)}
          />
        </fieldset>
        {error && (
          <p className="error" role="alert">
            {error}
          </p>
        )}
        <div className="form-actions">
          <button
            className="secondary"
            type="button"
            disabled={bloqueado}
            onClick={onCancel}
          >
            Cerrar
          </button>
          <button disabled={bloqueado}>Revisar partida</button>
        </div>
      </form>
    </section>
  );
}
export default function ListaCompras({
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
  const clave = `tienda:lista-compras-pendiente:${userId}`;
  const [recuperado] = useState(() => recuperarPartida(clave));
  const [pendiente, setPendiente] = useState<ListaPayload | null>(
    recuperado.pendiente,
  );
  const [preparada, setPreparada] = useState<ListaPayload | null>(null);
  const [editor, setEditor] = useState<ItemLista | null>(null);
  const [texto, setTexto] = useState("");
  const [modo, setModo] = useState("nombre");
  const [solo, setSolo] = useState(true);
  const [consulta, setConsulta] = useState({
    texto: "",
    modo: "nombre",
    solo: true,
    pagina: 0,
  });
  const [datos, setDatos] = useState<DatosLista | null>(null);
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
          .rpc("obtener_lista_compras", {
            p_busqueda: consulta.texto,
            p_modo: consulta.modo,
            p_solo_reponer: consulta.solo,
            p_pagina: consulta.pagina,
          })
          .abortSignal(controller.signal);
        if (controller.signal.aborted) return;
        if (
          r.error ||
          !Array.isArray(r.data?.lista) ||
          !Array.isArray(r.data?.candidatos)
        )
          throw new Error();
        setDatos(r.data as DatosLista);
      } catch {
        if (!controller.signal.aborted)
          setErrorCarga("No pudimos consultar la lista de compras.");
      } finally {
        if (!controller.signal.aborted) setCargando(false);
      }
    }
    void cargar();
    return () => controller.abort();
  }, [activo, revision, consulta, intento]);
  function abrirEditor(item: ItemLista) {
    setEditor(item);
    setError("");
    setMensaje("");
    setTimeout(
      () =>
        document
          .getElementById("lista-editor")
          ?.scrollIntoView({ behavior: "smooth", block: "center" }),
      0,
    );
  }
  function preparar(p: ListaPayload) {
    setPreparada(p);
    setError("");
    setMensaje("");
    setTimeout(
      () =>
        document
          .getElementById("lista-confirmacion")
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
          "No se pudo guardar la confirmación pendiente. No se envió la operación.",
        );
        return;
      }
      setPendiente(p);
      setPreparada(null);
    }
    bloqueo.current = true;
    setGuardando(true);
    try {
      const r = await supabase.rpc("actualizar_lista_compras", p);
      if (r.error) {
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
          ].includes(r.error.code) &&
          !(esReintento && r.error.code === "42501")
        ) {
          localStorage.removeItem(clave);
          setPendiente(null);
          setEditor(null);
          setIntento((v) => v + 1);
          throw new Error(r.error.message);
        }
        throw new Error(
          "No pudimos confirmar la respuesta. Reintenta la misma confirmación.",
        );
      }
      if (
        r.data?.producto_id !== p.p_producto_id ||
        r.data?.version !== p.p_version_esperada + 1 ||
        r.data?.activo !== (p.p_accion === "GUARDAR")
      )
        throw new Error(
          "No se pudo verificar la respuesta. Reintenta la confirmación.",
        );
      setMensaje(
        p.p_accion === "GUARDAR"
          ? "Partida guardada en la lista compartida."
          : "Partida quitada de la lista.",
      );
      try {
        localStorage.removeItem(clave);
        setPendiente(null);
      } catch {
        setError(
          "La operación está registrada. Reintenta para limpiar el pendiente de este dispositivo.",
        );
      }
      setEditor(null);
      setIntento((v) => v + 1);
      onChanged();
    } catch (e) {
      setError(
        e instanceof Error
          ? e.message
          : "No pudimos confirmar. Reintenta la misma confirmación.",
      );
    } finally {
      bloqueo.current = false;
      setGuardando(false);
    }
  }
  function exportar() {
    if (!datos) return;
    const url = URL.createObjectURL(
      new Blob([csvListaCompras(datos.lista)], {
        type: "text/csv;charset=utf-8",
      }),
    );
    const a = document.createElement("a");
    a.href = url;
    a.download = `lista_compras_${datos.fecha}.csv`;
    document.body.append(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 0);
  }
  const bloqueado =
    guardando || !!preparada || !!pendiente || !!recuperado.error;
  const operacion = pendiente ?? preparada;
  return (
    <>
      <div className="section-heading">
        <div>
          <p className="eyebrow">REABASTECIMIENTO</p>
          <h1>Lista de compras</h1>
          <p className="muted">
            Compartida entre las cuentas de administración e inventario.
          </p>
        </div>
        <button
          className="secondary"
          disabled={guardando}
          onClick={() => {
            setEditor(null);
            setIntento((v) => v + 1);
          }}
        >
          Actualizar lista
        </button>
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
      {error && (
        <p className="error" role="alert">
          {error}
        </p>
      )}
      {operacion && (
        <section
          id="lista-confirmacion"
          className="catalog-card purchase-panel cobros-section"
          aria-label="Confirmación de lista"
        >
          <h2>{pendiente ? "Confirmación pendiente" : "Revisa la partida"}</h2>
          <p>
            {operacion.p_accion === "GUARDAR" ? "Guardar" : "Quitar"} producto #
            {operacion.p_producto_id}
            {operacion.p_cantidad != null && (
              <> · {operacion.p_cantidad} unidades</>
            )}
          </p>
          {operacion.p_nota && (
            <p className="cobros-texto">{operacion.p_nota}</p>
          )}
          <p className="footnote">
            Esta acción modifica la planificación de compras. El inventario se
            actualizará cuando registres la compra en su módulo.
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
                  : "Confirmar lista"}
            </button>
          </div>
        </section>
      )}
      {cargando ? (
        <p className="state" role="status">
          Consultando lista…
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
          <>
            <div className="cash-grid">
              <article className="cash-stat">
                <span>Partidas guardadas</span>
                <strong>{datos.partidas}</strong>
              </article>
              <article className="cash-stat">
                <span>Unidades planificadas</span>
                <strong>{datos.unidades}</strong>
              </article>
              <article className="cash-stat">
                <span>Subtotal estimado con costo conocido</span>
                <strong>{dinero(datos.subtotal_con_costo)}</strong>
                <small>Usa el último costo conocido</small>
              </article>
              <article className="cash-stat">
                <span>Partidas sin costo</span>
                <strong>{datos.sin_costo}</strong>
                <small>Quedan fuera del subtotal estimado</small>
              </article>
            </div>
            <section className="catalog-card cobros-section">
              <div className="purchase-panel">
                <div className="section-heading">
                  <h2>Tu lista guardada</h2>
                  <button
                    className="secondary"
                    disabled={!datos.lista.length || bloqueado}
                    onClick={exportar}
                  >
                    Descargar lista CSV
                  </button>
                </div>
                <p className="muted">
                  Revisa cantidades y precios con el proveedor antes de comprar.
                </p>
              </div>
              {!datos.lista.length ? (
                <p className="state">La lista de compras está vacía.</p>
              ) : (
                <div
                  className="table-scroll"
                  tabIndex={0}
                  role="region"
                  aria-label="Lista de compras guardada"
                >
                  <table>
                    <thead>
                      <tr>
                        <th>Producto / nota</th>
                        <th className="numeric">Unidades</th>
                        <th className="numeric">Costo estimado</th>
                        <th className="numeric">Subtotal estimado</th>
                        <th>Acciones</th>
                      </tr>
                    </thead>
                    <tbody>
                      {datos.lista.map((i) => (
                        <tr key={i.id_producto}>
                          <td>
                            {i.nombre}
                            {!i.activo && (
                              <span className="history-date">
                                Producto inactivo: revisa esta partida
                              </span>
                            )}
                            {i.inconsistente && (
                              <span className="history-date">
                                Revisar existencias y lotes
                              </span>
                            )}
                            <span className="history-date lista-nota">
                              {i.nota}
                            </span>
                          </td>
                          <td className="numeric">{i.cantidad}</td>
                          <td className="numeric">
                            {i.costo_estimado == null
                              ? "Sin costo"
                              : dinero(i.costo_estimado)}
                          </td>
                          <td className="numeric">
                            {i.costo_estimado == null
                              ? "—"
                              : dinero(
                                  Number(i.cantidad) * Number(i.costo_estimado),
                                )}
                          </td>
                          <td>
                            <div className="cobros-acciones">
                              <button
                                className="secondary"
                                disabled={bloqueado || !i.activo}
                                onClick={() => abrirEditor(i)}
                              >
                                Editar partida
                              </button>
                              <button
                                className="secondary"
                                disabled={bloqueado}
                                onClick={() =>
                                  preparar({
                                    p_solicitud_id: crypto.randomUUID(),
                                    p_producto_id: i.id_producto,
                                    p_version_esperada:
                                      i.version ?? i.version_lista,
                                    p_accion: "QUITAR",
                                    p_cantidad: null,
                                    p_nota: "",
                                  })
                                }
                              >
                                Quitar de lista
                              </button>
                            </div>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </section>
            {editor && (
              <PartidaForm
                key={`${editor.id_producto}-${editor.version ?? editor.version_lista}`}
                item={editor}
                bloqueado={bloqueado}
                onPrepare={preparar}
                onCancel={() => setEditor(null)}
              />
            )}
            <section className="catalog-card cobros-section">
              <form
                className="purchase-panel"
                onSubmit={(e) => {
                  e.preventDefault();
                  setConsulta({ texto: texto.trim(), modo, solo, pagina: 0 });
                }}
              >
                <h2>Buscar y preparar reposición</h2>
                <label htmlFor="lista-modo">Buscar por</label>
                <select
                  id="lista-modo"
                  value={modo}
                  onChange={(e) => setModo(e.target.value)}
                >
                  <option value="nombre">Nombre</option>
                  <option value="codigo_barras">Código de barras exacto</option>
                </select>
                <label htmlFor="lista-buscar">Producto</label>
                <div className="search-controls">
                  <input
                    id="lista-buscar"
                    maxLength={150}
                    value={texto}
                    onChange={(e) => setTexto(e.target.value)}
                  />
                  <button>Buscar reposición</button>
                </div>
                <label className="checkbox-row">
                  <input
                    type="checkbox"
                    checked={solo}
                    onChange={(e) => setSolo(e.target.checked)}
                  />
                  Solo productos en mínimo o por debajo
                </label>
                <p className="footnote">
                  La sugerencia busca superar el mínimo por una unidad, usando
                  existencias aptas según los lotes. Ajusta la cantidad a tu
                  demanda y presentación de compra.
                </p>
              </form>
              <div
                className="table-scroll"
                tabIndex={0}
                role="region"
                aria-label="Sugerencias de reposición"
              >
                <table>
                  <thead>
                    <tr>
                      <th>Producto</th>
                      <th className="numeric">Total físico registrado</th>
                      <th className="numeric">Disponible según lotes</th>
                      <th className="numeric">Mínimo</th>
                      <th className="numeric">Sugerencia</th>
                      <th>Acción</th>
                    </tr>
                  </thead>
                  <tbody>
                    {datos.candidatos.map((i) => (
                      <tr key={i.id_producto}>
                        <td>
                          {i.nombre}
                          {Number(i.vencido) > 0 && (
                            <span className="history-date">
                              {i.vencido} unidades vencidas
                            </span>
                          )}
                          {i.inconsistente && (
                            <span className="history-date">
                              Revisar existencias y lotes
                            </span>
                          )}
                        </td>
                        <td className="numeric">{i.existencia}</td>
                        <td className="numeric">{i.disponible}</td>
                        <td className="numeric">{i.existencia_minima}</td>
                        <td className="numeric">
                          {i.cantidad_sugerida ?? "—"}
                        </td>
                        <td>
                          <button
                            className="secondary"
                            disabled={bloqueado || i.inconsistente}
                            onClick={() => abrirEditor(i)}
                          >
                            {i.en_lista ? "Editar partida" : "Añadir a lista"}
                          </button>
                        </td>
                      </tr>
                    ))}
                    {!datos.candidatos.length && (
                      <tr>
                        <td colSpan={6}>
                          No hay productos que coincidan con estos filtros.
                        </td>
                      </tr>
                    )}
                  </tbody>
                </table>
              </div>
              <div className="pagination">
                <span>
                  {datos.total_candidatos} coincidencias · página{" "}
                  {consulta.pagina + 1}
                </span>
                <div>
                  <button
                    className="secondary"
                    disabled={consulta.pagina === 0}
                    onClick={() =>
                      setConsulta((v) => ({ ...v, pagina: v.pagina - 1 }))
                    }
                  >
                    Anterior sugerencia
                  </button>
                  <button
                    className="secondary"
                    disabled={
                      (consulta.pagina + 1) * 20 >= datos.total_candidatos
                    }
                    onClick={() =>
                      setConsulta((v) => ({ ...v, pagina: v.pagina + 1 }))
                    }
                  >
                    Siguiente sugerencia
                  </button>
                </div>
              </div>
            </section>
            <p className="inventory-note">
              La lista no crea compras, deudas ni entradas de inventario.
              Después de recibir los productos, registra la compra y luego
              ajusta o quita la partida de esta lista.
            </p>
          </>
        )
      )}
    </>
  );
}
