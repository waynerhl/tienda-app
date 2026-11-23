import { useState } from "react";
type ProductoCosto = {
  id_producto: number;
  nombre: string;
  activo: boolean;
  ventas_con_costo: number;
  costo: number;
  utilidad_bruta: number;
  lineas_con_costo: number;
  lineas_sin_costo: number;
};
export type Costos = {
  desde: string;
  hasta: string;
  lineas_con_costo: number;
  lineas_sin_costo: number;
  lineas_ultimo_costo: number;
  ventas_con_costo: number;
  ventas_sin_costo: number;
  costo_identificado: number;
  utilidad_bruta_estimada: number;
  margen_bruto_estimado: number | null;
  mayores: ProductoCosto[];
  menores: ProductoCosto[];
};
const dinero = (n: number) =>
  new Intl.NumberFormat("es-GT", { style: "currency", currency: "GTQ" }).format(
    Number(n),
  );
const porcentaje = (n: number | null) =>
  n == null
    ? "—"
    : new Intl.NumberFormat("es-GT", {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
      }).format(Number(n)) + " %";
export default function CostosReporte({ datos }: { datos: Costos }) {
  const [orden, setOrden] = useState<"mayores" | "menores">("mayores");
  return (
    <section
      className="cobros-section"
      aria-label="Costos y utilidad bruta estimada"
    >
      <div className="catalog-card purchase-panel">
        <h2>Costos y utilidad bruta estimada</h2>
        <p className="muted">
          Se calcula sobre las líneas de venta que conservan un costo
          identificado.
        </p>
        <p className="footnote">
          Por lote: costo registrado en la compra o en el inventario inicial de las unidades consumidas. Sin lotes:
          último costo conocido al vender. Los gastos operativos y otras
          pérdidas se analizan por separado.
        </p>
      </div>
      <>
        {Number(datos.lineas_con_costo) + Number(datos.lineas_sin_costo) ===
        0 ? (
          <p className="state">
            No hay líneas de ventas válidas para estimar utilidad en este
            período.
          </p>
        ) : (
          <>
            {datos.lineas_sin_costo > 0 && (
              <p className="inventory-note" role="status">
                {datos.lineas_sin_costo} líneas de venta no tienen costo
                completo identificado, por {dinero(datos.ventas_sin_costo)}.
                Quedan fuera de la estimación de utilidad. Las ventas anteriores
                a esta actualización pueden aparecer aquí.
              </p>
            )}
            <div className="cash-grid cobros-section">
              <article className="cash-stat">
                <span>Ventas con costo identificado</span>
                <strong>{dinero(datos.ventas_con_costo)}</strong>
                <small>{datos.lineas_con_costo} líneas incluidas</small>
              </article>
              <article className="cash-stat">
                <span>Costo registrado de esas ventas</span>
                <strong>
                  {datos.lineas_con_costo
                    ? dinero(datos.costo_identificado)
                    : "—"}
                </strong>
              </article>
              <article className="cash-stat">
                <span>Utilidad bruta estimada</span>
                <strong>
                  {datos.lineas_con_costo
                    ? dinero(datos.utilidad_bruta_estimada)
                    : "—"}
                </strong>
                <small>Sobre la parte con costo identificado</small>
              </article>
              <article className="cash-stat">
                <span>Margen bruto estimado</span>
                <strong>
                  {datos.lineas_con_costo
                    ? porcentaje(datos.margen_bruto_estimado)
                    : "—"}
                </strong>
                <small>Utilidad ÷ ventas con costo × 100</small>
              </article>
            </div>
            <p className="footnote">
              {datos.lineas_ultimo_costo} líneas incluidas usan el último costo
              conocido del producto, conservado al vender. Una compra posterior
              no cambia ese costo guardado.
            </p>
            <section className="catalog-card cobros-section">
              <div className="purchase-panel">
                <h3>Utilidad bruta por producto</h3>
                <label htmlFor="costos-orden">Ordenar estimación</label>
                <select
                  id="costos-orden"
                  value={orden}
                  onChange={(e) =>
                    setOrden(e.target.value as "mayores" | "menores")
                  }
                >
                  <option value="mayores">Mayor utilidad bruta</option>
                  <option value="menores">Menor utilidad bruta</option>
                </select>
                <p className="footnote">
                  Primeros 20 productos con líneas de costo identificado. Las
                  líneas sin costo quedan excluidas.
                </p>
              </div>
              {!datos[orden].length ? (
                <p className="state">
                  Todavía no hay productos con costo identificado en este
                  período.
                </p>
              ) : (
                <div
                  className="table-scroll"
                  tabIndex={0}
                  role="region"
                  aria-label="Utilidad bruta por producto"
                >
                  <table>
                    <thead>
                      <tr>
                        <th>Producto</th>
                        <th className="numeric">Ventas con costo</th>
                        <th className="numeric">Costo registrado</th>
                        <th className="numeric">Utilidad estimada</th>
                        <th className="numeric">Líneas sin costo</th>
                      </tr>
                    </thead>
                    <tbody>
                      {datos[orden].map((p) => (
                        <tr key={p.id_producto}>
                          <td>
                            {p.nombre}
                            {!p.activo && (
                              <span className="history-date">
                                Actualmente inactivo
                              </span>
                            )}
                          </td>
                          <td className="numeric">
                            {dinero(p.ventas_con_costo)}
                          </td>
                          <td className="numeric">{dinero(p.costo)}</td>
                          <td className="numeric">
                            {dinero(p.utilidad_bruta)}
                          </td>
                          <td className="numeric">{p.lineas_sin_costo}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </section>
          </>
        )}
      </>
    </section>
  );
}
