BEGIN;
ALTER TABLE public.productos
  ADD COLUMN paquete_nombre varchar(50),
  ADD COLUMN paquete_unidades integer,
  ADD COLUMN paquete_precio numeric(12,2),
  ADD COLUMN paquete_predeterminado boolean NOT NULL DEFAULT false,
  ADD COLUMN paquete_version integer NOT NULL DEFAULT 0 CHECK(paquete_version>=0),
  ADD CONSTRAINT producto_paquete_valido CHECK (
    (paquete_nombre IS NULL AND paquete_unidades IS NULL AND paquete_precio IS NULL AND NOT paquete_predeterminado) OR
    (paquete_nombre IS NOT NULL AND length(trim(paquete_nombre)) BETWEEN 1 AND 50 AND paquete_unidades IS NOT NULL AND paquete_unidades BETWEEN 2 AND 2147483647 AND paquete_precio IS NOT NULL AND paquete_precio>=0 AND paquete_precio<=9999999999.99)
  );
ALTER TABLE public.detalle_ventas
  ADD COLUMN paquete_nombre varchar(50),
  ADD COLUMN paquete_unidades integer,
  ADD COLUMN paquete_precio numeric(12,2),
  ADD CONSTRAINT detalle_paquete_valido CHECK (
    (paquete_nombre IS NULL AND paquete_unidades IS NULL AND paquete_precio IS NULL) OR
    (paquete_nombre IS NOT NULL AND length(trim(paquete_nombre)) BETWEEN 1 AND 50 AND paquete_unidades IS NOT NULL AND paquete_unidades>=2 AND paquete_precio IS NOT NULL AND paquete_precio>=0 AND paquete_precio<=9999999999.99)
  );
-- PostgreSQL 17 permite cambiar la expresión conservando la columna y sus dependencias.
-- Los detalles históricos tienen los nuevos campos nulos y conservan su importe anterior.
ALTER TABLE public.detalle_ventas ALTER COLUMN subtotal SET EXPRESSION AS (
  CASE WHEN paquete_unidades IS NULL THEN cantidad::numeric*precio_unitario
  ELSE (cantidad/paquete_unidades)::numeric*paquete_precio + (cantidad%paquete_unidades)::numeric*precio_unitario END
);

CREATE OR REPLACE FUNCTION tienda_privada.configurar_paquete_producto(
 p_producto_id integer,p_version_esperada integer,p_nombre text,p_unidades integer,p_precio numeric,p_predeterminado boolean
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_producto public.productos%ROWTYPE;v_nombre text:=nullif(trim(p_nombre),'');
BEGIN
 IF auth.uid() IS NULL OR NOT public.fn_tiene_rol(ARRAY['ADMINISTRADOR','INVENTARIO']) THEN RAISE EXCEPTION 'No tienes permiso para configurar presentaciones.' USING ERRCODE='42501';END IF;
 IF p_producto_id IS NULL OR p_version_esperada IS NULL OR p_version_esperada<0 OR p_predeterminado IS NULL THEN RAISE EXCEPTION 'Revisa producto y versión consultada.' USING ERRCODE='22023';END IF;
 IF (p_unidades IS NULL AND (v_nombre IS NOT NULL OR p_precio IS NOT NULL OR p_predeterminado)) OR
   (p_unidades IS NOT NULL AND (p_unidades<2 OR v_nombre IS NULL OR length(v_nombre)>50 OR p_precio IS NULL OR p_precio<0 OR p_precio>9999999999.99 OR p_precio<>trunc(p_precio,2))) THEN
   RAISE EXCEPTION 'Indica nombre, al menos dos unidades y precio total del paquete con hasta dos decimales. Para desactivarlo elimina sus datos.' USING ERRCODE='22023';END IF;
 SELECT * INTO v_producto FROM public.productos WHERE id_producto=p_producto_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Producto no encontrado.' USING ERRCODE='22023';END IF;
 -- Un reintento idéntico no incrementa la versión ni reescribe el catálogo.
 IF ROW(v_producto.paquete_nombre,v_producto.paquete_unidades,v_producto.paquete_precio,v_producto.paquete_predeterminado)
    IS NOT DISTINCT FROM ROW(v_nombre,p_unidades,p_precio,p_predeterminado) THEN RETURN to_jsonb(v_producto);END IF;
 IF v_producto.paquete_version<>p_version_esperada THEN RAISE EXCEPTION 'La presentación cambió en otro dispositivo. Actualiza el producto antes de editar.' USING ERRCODE='22023';END IF;
 IF v_producto.paquete_version=2147483647 THEN RAISE EXCEPTION 'La versión del producto requiere revisión.' USING ERRCODE='22023';END IF;
 UPDATE public.productos SET paquete_nombre=v_nombre,paquete_unidades=p_unidades,paquete_precio=p_precio,
   paquete_predeterminado=p_predeterminado,paquete_version=paquete_version+1 WHERE id_producto=p_producto_id RETURNING * INTO v_producto;
 RETURN to_jsonb(v_producto);
END;
$fn$;
REVOKE ALL ON FUNCTION tienda_privada.configurar_paquete_producto(integer,integer,text,integer,numeric,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION tienda_privada.configurar_paquete_producto(integer,integer,text,integer,numeric,boolean) TO authenticated;
CREATE OR REPLACE FUNCTION public.configurar_paquete_producto(p_producto_id integer,p_version_esperada integer,p_nombre text,p_unidades integer,p_precio numeric,p_predeterminado boolean)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $fn$
 SELECT tienda_privada.configurar_paquete_producto(p_producto_id,p_version_esperada,p_nombre,p_unidades,p_precio,p_predeterminado);
$fn$;
REVOKE ALL ON FUNCTION public.configurar_paquete_producto(integer,integer,text,integer,numeric,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.configurar_paquete_producto(integer,integer,text,integer,numeric,boolean) TO authenticated;

-- Registrar ventas conserva la presentación y calcula los importes en la base.

CREATE OR REPLACE FUNCTION public.registrar_venta(p_cliente_id integer, p_forma_pago_id integer, p_items jsonb, p_fecha_limite date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET "TimeZone" TO 'America/Guatemala'
AS $function$
DECLARE
 v_usuario uuid:=auth.uid(); v_pago text; v_tipo integer; v_venta integer;
 v_detalle integer; v_item jsonb; v_producto public.productos%ROWTYPE;
 v_subtotal numeric; v_cantidad integer; v_restante integer; v_tomar integer; v_lote record;
 v_total numeric(12,2):=0;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('efectivo-fondos',0));
 IF v_usuario IS NULL OR NOT public.fn_tiene_rol(ARRAY['ADMINISTRADOR','CAJERO']::text[]) THEN
  RAISE EXCEPTION 'No tienes permiso para registrar ventas' USING ERRCODE='42501';
 END IF;
 SELECT nombre INTO v_pago FROM public.formas_pago WHERE id_forma_pago=p_forma_pago_id;
 IF v_pago IS NULL THEN RAISE EXCEPTION 'Selecciona una forma de pago válida' USING ERRCODE='22023'; END IF;
 IF p_cliente_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.clientes WHERE id_cliente=p_cliente_id) THEN
  RAISE EXCEPTION 'El cliente no existe' USING ERRCODE='22023';
 END IF;
 IF v_pago='CREDITO' AND p_cliente_id IS NULL THEN RAISE EXCEPTION 'Una venta a crédito requiere un cliente' USING ERRCODE='22023'; END IF;
 IF v_pago<>'CREDITO' AND p_fecha_limite IS NOT NULL THEN RAISE EXCEPTION 'Solo el crédito admite fecha límite' USING ERRCODE='22023'; END IF;
 IF p_fecha_limite<CURRENT_DATE THEN RAISE EXCEPTION 'La fecha límite no puede ser anterior a hoy' USING ERRCODE='22023'; END IF;
 IF p_items IS NULL OR jsonb_typeof(p_items)<>'array' THEN RAISE EXCEPTION 'La venta debe contener una lista de productos' USING ERRCODE='22023'; END IF;
 IF jsonb_array_length(p_items)=0 THEN RAISE EXCEPTION 'Agrega al menos un producto' USING ERRCODE='22023'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_items) x WHERE jsonb_typeof(x)<>'object' OR x->>'producto_id' IS NULL) THEN
  RAISE EXCEPTION 'Cada línea debe indicar un producto' USING ERRCODE='22023';
 END IF;
 IF (SELECT count(*) FROM jsonb_array_elements(p_items))<>(SELECT count(DISTINCT (x->>'producto_id')::integer) FROM jsonb_array_elements(p_items) x) THEN
  RAISE EXCEPTION 'Cada producto debe aparecer una sola vez' USING ERRCODE='22023';
 END IF;
 SELECT id_tipo_movimiento INTO v_tipo FROM public.tipos_movimientos WHERE nombre='VENTA' AND factor=-1;
 IF v_tipo IS NULL THEN RAISE EXCEPTION 'Falta configurar el movimiento VENTA'; END IF;
 INSERT INTO public.ventas(cliente_id,usuario_id,forma_pago_id,total)
 VALUES(p_cliente_id,v_usuario,p_forma_pago_id,0) RETURNING id_venta INTO v_venta;
 FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) ORDER BY (value->>'producto_id')::integer LOOP
  IF v_item->>'cantidad' IS NULL OR (v_item->>'cantidad')!~'^[0-9]+$' THEN
   RAISE EXCEPTION 'La cantidad debe ser un entero positivo' USING ERRCODE='22023';
  END IF;
  v_cantidad:=(v_item->>'cantidad')::integer;
  IF v_cantidad<1 THEN RAISE EXCEPTION 'La cantidad debe ser mayor que cero' USING ERRCODE='22023'; END IF;
  SELECT * INTO v_producto FROM public.productos WHERE id_producto=(v_item->>'producto_id')::integer FOR UPDATE;
  IF NOT FOUND OR NOT v_producto.activo THEN RAISE EXCEPTION 'El producto no existe o está inactivo' USING ERRCODE='22023'; END IF;
  IF v_producto.precio_venta<0 OR v_producto.precio_venta>9999999999.99 THEN RAISE EXCEPTION 'El precio del producto no es válido' USING ERRCODE='22023'; END IF;
  IF v_item ? 'precio_esperado' AND (v_item->>'precio_esperado')::numeric IS DISTINCT FROM v_producto.precio_venta THEN
   RAISE EXCEPTION 'Cambió el precio de %. Actualiza el carrito antes de cobrar',v_producto.nombre USING ERRCODE='22023';
  END IF;
  IF v_item ? 'paquete_version_esperada' THEN
    IF coalesce(v_item->>'paquete_version_esperada','') !~ '^[0-9]{1,10}$' OR (v_item->>'paquete_version_esperada')::bigint<>v_producto.paquete_version THEN
      RAISE EXCEPTION 'Cambió la presentación de %. Actualiza los datos y vuelve a agregar el producto al carrito.',v_producto.nombre USING ERRCODE='22023';
    END IF;
  ELSIF v_producto.paquete_unidades IS NOT NULL THEN
    RAISE EXCEPTION 'Este producto tiene precio por paquete. Actualiza la aplicación y vuelve a agregarlo al carrito.' USING ERRCODE='22023';
  END IF;
  IF v_cantidad>v_producto.existencia THEN RAISE EXCEPTION 'Stock insuficiente para %: quedan % unidades',v_producto.nombre,v_producto.existencia USING ERRCODE='22023'; END IF;
  INSERT INTO public.detalle_ventas(venta_id,producto_id,cantidad,precio_unitario,paquete_nombre,paquete_unidades,paquete_precio)
  VALUES(v_venta,v_producto.id_producto,v_cantidad,v_producto.precio_venta,v_producto.paquete_nombre,v_producto.paquete_unidades,v_producto.paquete_precio)
  RETURNING id_detalle_venta,subtotal INTO v_detalle,v_subtotal;
  v_total:=v_total+v_subtotal;
  IF v_producto.controla_lotes THEN
   v_restante:=v_cantidad;
   FOR v_lote IN
    SELECT l.id_lote,public.fn_stock_lote(l.id_lote) as stock
    FROM public.lotes_contexto l
    WHERE l.producto_id=v_producto.id_producto AND l.estado='REGISTRADA'
     AND (l.fecha_vencimiento IS NULL OR l.fecha_vencimiento>=CURRENT_DATE)
     AND public.fn_stock_lote(l.id_lote)>0
    ORDER BY l.fecha_vencimiento ASC NULLS LAST,l.fecha_ingreso,l.id_lote
   LOOP
    EXIT WHEN v_restante=0;
    v_tomar:=least(v_restante,v_lote.stock);
    INSERT INTO public.movimientos_inventario(producto_id,lote_id,tipo_movimiento_id,detalle_venta_id,cantidad,usuario_id,observacion)
    VALUES(v_producto.id_producto,v_lote.id_lote,v_tipo,v_detalle,v_tomar,v_usuario,'Venta');
    v_restante:=v_restante-v_tomar;
   END LOOP;
   IF v_restante>0 THEN RAISE EXCEPTION 'No hay suficientes unidades en lotes vigentes de %',v_producto.nombre USING ERRCODE='22023'; END IF;
  ELSE
   INSERT INTO public.movimientos_inventario(producto_id,tipo_movimiento_id,detalle_venta_id,cantidad,usuario_id,observacion)
   VALUES(v_producto.id_producto,v_tipo,v_detalle,v_cantidad,v_usuario,'Venta');
  END IF;
 END LOOP;
 UPDATE public.ventas SET total=v_total WHERE id_venta=v_venta;
 IF v_pago='CREDITO' THEN
  IF v_total=0 THEN RAISE EXCEPTION 'Una venta a crédito debe tener un total mayor que cero' USING ERRCODE='22023'; END IF;
  INSERT INTO public.cuentas_por_cobrar(venta_id,monto_original,saldo_pendiente,fecha_limite)
  VALUES(v_venta,v_total,v_total,p_fecha_limite);
 END IF;
 RETURN jsonb_build_object('id_venta',v_venta,'total',v_total,'estado','REGISTRADA');
END;
$function$;
ANALYZE public.detalle_ventas;
COMMIT;
