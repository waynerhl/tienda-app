import { useEffect, useRef, useState } from "react";
import type { FormEvent } from "react";
import { supabase } from "../lib/supabase";
import { guardarProducto } from "../services/productos";
import type {
  Categoria,
  Producto,
  ProductoFormValues,
} from "../types/producto";

interface Props {
  producto: Producto | null;
  onCancel: () => void;
  onSaved: (producto: Producto, editing: boolean) => void;
}

export default function ProductoForm({ producto, onCancel, onSaved }: Props) {
  const dialog = useRef<HTMLDialogElement>(null);
  const saveLock = useRef(false);
  const [values, setValues] = useState<ProductoFormValues>({
    nombre: producto?.nombre ?? "",
    categoria_id: producto ? String(producto.categoria_id) : "",
    codigo_barras: producto?.codigo_barras ?? "",
    precio_venta: producto ? Number(producto.precio_venta).toFixed(2) : "",
    existencia_minima: String(producto?.existencia_minima ?? 0),
    activo: producto?.activo ?? true,
    controla_lotes: producto?.controla_lotes ?? false,
  });
  const [categorias, setCategorias] = useState<Categoria[]>([]);
  const [loading, setLoading] = useState(true);
  const [categoryError, setCategoryError] = useState("");
  const [retry, setRetry] = useState(0);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    const element = dialog.current;
    element?.showModal();
    return () => element?.close();
  }, []);

  useEffect(() => {
    const controller = new AbortController();
    async function load() {
      if (!supabase) return;
      setLoading(true);
      setCategoryError("");
      try {
        const { data, error } = await supabase
          .from("categorias")
          .select("id_categoria,nombre")
          .order("nombre")
          .abortSignal(controller.signal);
        if (controller.signal.aborted) return;
        if (error) throw error;
        setCategorias(data ?? []);
      } catch {
        if (!controller.signal.aborted)
          setCategoryError(
            "No pudimos cargar las categorías. Inténtalo de nuevo.",
          );
      } finally {
        if (!controller.signal.aborted) setLoading(false);
      }
    }
    void load();
    return () => controller.abort();
  }, [retry]);

  function field<K extends keyof ProductoFormValues>(
    key: K,
    value: ProductoFormValues[K],
  ) {
    setValues((current) => ({ ...current, [key]: value }));
    setError("");
  }

  async function save(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (saveLock.current || loading || categoryError || categorias.length === 0)
      return;
    setError("");
    if (
      !categorias.some(
        (category) => String(category.id_categoria) === values.categoria_id,
      )
    ) {
      setError("Selecciona una categoría disponible.");
      return;
    }
    saveLock.current = true;
    setSaving(true);
    try {
      const saved = await guardarProducto(values, producto?.id_producto);
      onSaved(saved, producto !== null);
    } catch (error) {
      setError(
        error instanceof Error
          ? error.message
          : "No pudimos guardar el producto. Inténtalo de nuevo.",
      );
    } finally {
      saveLock.current = false;
      setSaving(false);
    }
  }

  return (
    <dialog
      className="product-dialog"
      ref={dialog}
      aria-labelledby="product-form-title"
      aria-describedby="product-form-description"
      onCancel={(event) => {
        event.preventDefault();
        if (!saveLock.current) onCancel();
      }}
    >
      <div className="form-heading">
        <div>
          <p className="eyebrow">CATÁLOGO</p>
          <h2 id="product-form-title">
            {producto ? "Editar producto" : "Agregar producto"}
          </h2>
        </div>
        <button
          type="button"
          className="secondary close-dialog"
          aria-label="Cerrar formulario"
          onClick={onCancel}
          disabled={saving}
        >
          ×
        </button>
      </div>
      <p id="product-form-description" className="muted">
        {producto
          ? "Actualiza los datos del producto."
          : "Crea un producto y registra su entrada de mercadería después."}
      </p>
      <form onSubmit={save}>
        <fieldset disabled={saving}>
          <label htmlFor="product-name">
            Nombre del producto <span aria-hidden="true">*</span>
          </label>
          <input
            id="product-name"
            value={values.nombre}
            onChange={(e) => field("nombre", e.target.value)}
            maxLength={150}
            required
            autoFocus
          />
          <label htmlFor="product-category">
            Categoría <span aria-hidden="true">*</span>
          </label>
          <select
            id="product-category"
            value={values.categoria_id}
            onChange={(e) => field("categoria_id", e.target.value)}
            disabled={loading || !!categoryError}
            required
          >
            <option value="">
              {loading ? "Cargando categorías…" : "Selecciona una categoría"}
            </option>
            {categorias.map((category) => (
              <option key={category.id_categoria} value={category.id_categoria}>
                {category.nombre}
              </option>
            ))}
          </select>
          {categoryError && (
            <div className="category-error">
              <p className="error" role="alert">
                {categoryError}
              </p>
              <button
                type="button"
                className="secondary"
                onClick={() => setRetry((value) => value + 1)}
              >
                Reintentar categorías
              </button>
            </div>
          )}
          {!loading && !categoryError && categorias.length === 0 && (
            <p className="error" role="alert">
              Primero registra al menos una categoría en Supabase.
            </p>
          )}
          <label htmlFor="product-barcode">
            Código de barras <span className="optional">(opcional)</span>
          </label>
          <input
            id="product-barcode"
            type="text"
            value={values.codigo_barras}
            onChange={(e) => field("codigo_barras", e.target.value)}
            maxLength={50}
            autoComplete="off"
            aria-describedby="barcode-help"
          />
          <small id="barcode-help" className="muted">
            Se conserva como texto, incluidos los ceros iniciales.
          </small>
          <div className="form-grid">
            <div>
              <label htmlFor="product-price">
                Precio de venta (Q) <span aria-hidden="true">*</span>
              </label>
              <input
                id="product-price"
                type="text"
                inputMode="decimal"
                value={values.precio_venta}
                onChange={(e) => field("precio_venta", e.target.value)}
                required
                placeholder="0.00"
                maxLength={20}
              />
            </div>
            <div>
              <label htmlFor="product-minimum">
                Existencia mínima <span aria-hidden="true">*</span>
              </label>
              <input
                id="product-minimum"
                type="number"
                min="0"
                max="2147483647"
                step="1"
                value={values.existencia_minima}
                onChange={(e) => field("existencia_minima", e.target.value)}
                required
              />
            </div>
          </div>
          <label className="checkbox-row">
            <input
              type="checkbox"
              checked={values.activo}
              onChange={(e) => field("activo", e.target.checked)}
            />
            Producto activo
          </label>
          <label className="checkbox-row">
            <input
              type="checkbox"
              checked={values.controla_lotes}
              disabled={producto !== null}
              onChange={(e) => field("controla_lotes", e.target.checked)}
              aria-describedby="lots-help"
            />
            Controlar por lotes
          </label>
          <small id="lots-help" className="muted">
            {producto
              ? "El control por lotes se define al crear el producto y no se cambia desde este formulario."
              : "Actívalo para registrar lotes y sus vencimientos al comprar mercadería."}
          </small>
        </fieldset>
        <p className="inventory-note">
          {producto
            ? `Existencia actual: ${producto.existencia} unidades.`
            : "La existencia inicial será de 0 unidades."}{" "}
          Las entradas y salidas se registran mediante operaciones de
          inventario.
        </p>
        {error && (
          <p className="error" role="alert">
            {error}
          </p>
        )}
        <div className="form-actions">
          <button
            type="button"
            className="secondary"
            disabled={saving}
            onClick={onCancel}
          >
            Cancelar
          </button>
          <button
            type="submit"
            disabled={
              saving || loading || !!categoryError || categorias.length === 0
            }
          >
            {saving
              ? "Guardando…"
              : producto
                ? "Guardar cambios"
                : "Crear producto"}
          </button>
        </div>
      </form>
    </dialog>
  );
}
