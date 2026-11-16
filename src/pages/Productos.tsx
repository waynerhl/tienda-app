import { useEffect, useState } from "react";
import type { FormEvent } from "react";
import { supabase } from "../lib/supabase";
import type { Producto } from "../types/producto";

const pageSize = 25;
const money = new Intl.NumberFormat("es-GT", {
  style: "currency",
  currency: "GTQ",
});

export default function Productos() {
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
          .select(
            "id_producto,nombre,codigo_barras,precio_venta,existencia,existencia_minima,activo",
            { count: "exact" },
          )
          .order("nombre")
          .order("id_producto")
          .range(page * pageSize, (page + 1) * pageSize - 1);
        if (search)
          query = query.ilike(
            "nombre",
            `%${search.replace(/[\\%_]/g, "\\$&")}%`,
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
        <button
          className="secondary"
          onClick={() => setRefresh((v) => v + 1)}
          disabled={loading}
        >
          Actualizar
        </button>
      </div>
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
    </section>
  );
}
