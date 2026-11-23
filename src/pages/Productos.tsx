import { patronBusquedaNombre } from "../services/busquedas";
import { useEffect, useState } from "react";
import type { FormEvent } from "react";
import { supabase } from "../lib/supabase";
import PresentacionForm from "../components/PresentacionForm";
import ProductoForm from "../components/ProductoForm";
import { productoColumns } from "../services/productos";
import type { Producto } from "../types/producto";

const pageSize = 25;
const money = new Intl.NumberFormat("es-GT", {
  style: "currency",
  currency: "GTQ",
});

export default function Productos({
  canManage = false,
}: {
  canManage?: boolean;
}) {
  const [editor, setEditor] = useState<{ producto: Producto | null } | null>(
    null,
  );
  const [presentacion,setPresentacion] = useState<Producto|null>(null);
  const [notice, setNotice] = useState("");

  function saved(producto: Producto, editing: boolean) {
    setEditor(null);
    setNotice(
      `${editing ? "Producto actualizado" : "Producto creado"}: ${producto.nombre}.`,
    );
    setDraft("");
    setSearch("");
    setPage(0);
    setRefresh((value) => value + 1);
  }
  const [rows, setRows] = useState<Producto[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(0);
  const [draft, setDraft] = useState("");
  const [search, setSearch] = useState("");
  const [refresh, setRefresh] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  useEffect(() => {
    const controller = new AbortController();
    async function load() {
      if (!supabase) return;
      setLoading(true);
      setError("");
      try {
        let query = supabase
          .from("productos")
          .select(productoColumns, { count: "exact" })
          .order("nombre")
          .order("id_producto")
          .range(page * pageSize, (page + 1) * pageSize - 1);
        if (search)
          query = query.ilike(
            "nombre_busqueda", patronBusquedaNombre(search),
          );
        const { data, count, error } = await query.abortSignal(
          controller.signal,
        );
        if (controller.signal.aborted) return;
        if (error) throw error;
        setRows((data ?? []) as Producto[]);
        setTotal(count ?? 0);
      } catch {
        if (!controller.signal.aborted) {
          setRows([]);
          setTotal(0);
          setError(
            "No pudimos cargar los productos. Revisa tu conexión y vuelve a intentar.",
          );
        }
      } finally {
        if (!controller.signal.aborted) setLoading(false);
      }
    }
    void load();
    return () => controller.abort();
  }, [page, search, refresh]);

  function filter(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setPage(0);
    setSearch(draft.trim());
    setRefresh((value) => value + 1);
  }

  return (
    <section aria-labelledby="productos-title">
      <div className="section-heading">
        <div>
          <p className="eyebrow">CATÁLOGO</p>
          <h1 id="productos-title">Tus productos</h1>
          <p className="muted">
            Consulta precios y existencias registrados en tu tienda.
          </p>
        </div>
        <div className="catalog-actions">
          <button
            className="secondary"
            onClick={() => setRefresh((v) => v + 1)}
            disabled={loading}
          >
            Actualizar
          </button>
          {canManage && (
            <button
              onClick={() => {
                setNotice("");
                setEditor({ producto: null });
              }}
            >
              Agregar producto
            </button>
          )}
        </div>
      </div>
      {notice && (
        <p className="success" role="status">
          {notice}
        </p>
      )}
      <div className="catalog-card">
        <form className="search-form" onSubmit={filter}>
          <label htmlFor="search">Buscar por nombre</label>
          <div className="search-controls">
            <input
              id="search"
              type="search"
              placeholder="Ej. leche"
              value={draft}
              onChange={(e) => setDraft(e.target.value)}
            />
            <button disabled={loading}>Buscar</button>
          </div>
        </form>
        <div aria-live="polite" aria-busy={loading}>
          {loading ? (
            <p className="state">Cargando productos…</p>
          ) : error ? (
            <div className="state">
              <p className="error" role="alert">
                {error}
              </p>
              <button
                className="secondary"
                onClick={() => setRefresh((v) => v + 1)}
              >
                Reintentar
              </button>
            </div>
          ) : rows.length === 0 ? (
            <div className="state">
              <h2>
                {search ? "Sin coincidencias" : "Todavía no hay productos"}
              </h2>
              <p>
                {search
                  ? "Prueba con otro nombre."
                  : "Los productos que registres aparecerán aquí."}
              </p>
            </div>
          ) : (
            <>
              <div className="table-scroll">
                <table>
                  <caption className="sr-only">
                    Productos, precios y existencias
                  </caption>
                  <thead>
                    <tr>
                      <th>Producto</th>
                      <th>Código de barras</th>
                      <th className="numeric">Precio</th>
                      <th className="numeric">Existencia</th>
                      <th className="numeric">Mínimo</th>
                      <th>Estado</th>
                      {canManage && <th>Acciones</th>}
                    </tr>
                  </thead>
                  <tbody>
                    {rows.map((product) => (
                      <tr key={product.id_producto}>
                        <td className="product-name">{product.nombre}</td>
                        <td className="muted">
                          {product.codigo_barras || "Sin código"}
                        </td>
                        <td className="numeric">
                          {money.format(Number(product.precio_venta))}
                          {product.paquete_unidades && <span className="history-date">{product.paquete_nombre} × {product.paquete_unidades}: {money.format(Number(product.paquete_precio))}</span>}
                        </td>
                        <td className="numeric">{product.existencia}</td>
                        <td className="numeric">{product.existencia_minima}</td>
                        <td>
                          <span
                            className={`badge ${!product.activo ? "inactive" : product.existencia <= product.existencia_minima ? "low" : ""}`}
                          >
                            {!product.activo
                              ? "Inactivo"
                              : product.existencia === 0
                                ? "Agotado"
                                : product.existencia <=
                                    product.existencia_minima
                                  ? "Stock bajo"
                                  : "Disponible"}
                          </span>
                        </td>
                        {canManage && (
                          <td>
                            <button
                              className="secondary edit-product"
                              aria-label={`Editar ${product.nombre}`}
                              onClick={() => {
                                setNotice("");
                                setEditor({ producto: product });
                              }}
                            >
                              Editar
                            </button>
                            <button className="secondary" aria-label={`Presentación de ${product.nombre}`} onClick={() => setPresentacion(product)}>Presentación</button>
                          </td>
                        )}
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
              <div className="pagination">
                <span>
                  {page * pageSize + 1}–{Math.min((page + 1) * pageSize, total)}{" "}
                  de {total} productos
                </span>
                <div>
                  <button
                    className="secondary"
                    disabled={page === 0}
                    onClick={() => setPage((p) => p - 1)}
                  >
                    Anterior
                  </button>
                  <button
                    className="secondary"
                    disabled={(page + 1) * pageSize >= total}
                    onClick={() => setPage((p) => p + 1)}
                  >
                    Siguiente
                  </button>
                </div>
              </div>
            </>
          )}
        </div>
      </div>
      <p className="footnote">
        Las existencias se actualizan mediante las operaciones de inventario.
      </p>
      {canManage && presentacion && <PresentacionForm producto={presentacion} onCancel={() => setPresentacion(null)} onSaved={p => {setPresentacion(null);setNotice(`Presentación actualizada: ${p.nombre}. Actualiza los datos de Ventas antes de volver a agregarlo.`);setRefresh(v => v + 1);}} />}
      {canManage && editor && (
        <ProductoForm
          producto={editor.producto}
          onCancel={() => setEditor(null)}
          onSaved={saved}
        />
      )}
    </section>
  );
}
