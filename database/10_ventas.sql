-- Copia de las funciones de ventas ya aplicadas en Supabase.
BEGIN;
ALTER TABLE public.ventas ADD COLUMN IF NOT EXISTS solicitud_id uuid;
ALTER TABLE public.ventas ADD COLUMN IF NOT EXISTS solicitud_firma text;
CREATE UNIQUE INDEX IF NOT EXISTS uq_ventas_solicitud ON public.ventas USING btree (solicitud_id) WHERE (solicitud_id IS NOT NULL);
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
 v_cantidad integer; v_restante integer; v_tomar integer; v_lote record;
 v_total numeric(12,2):=0;
BEGIN
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
  IF v_cantidad>v_producto.existencia THEN RAISE EXCEPTION 'Stock insuficiente para %: quedan % unidades',v_producto.nombre,v_producto.existencia USING ERRCODE='22023'; END IF;
  INSERT INTO public.detalle_ventas(venta_id,producto_id,cantidad,precio_unitario)
  VALUES(v_venta,v_producto.id_producto,v_cantidad,v_producto.precio_venta) RETURNING id_detalle_venta INTO v_detalle;
  v_total:=v_total+v_cantidad*v_producto.precio_venta;
  IF v_producto.controla_lotes THEN
   v_restante:=v_cantidad;
   FOR v_lote IN
    SELECT l.id_lote,public.fn_stock_lote(l.id_lote) as stock
    FROM public.lotes l JOIN public.detalle_compras dc ON dc.id_detalle_compra=l.detalle_compra_id
    JOIN public.compras c ON c.id_compra=dc.compra_id
    WHERE dc.producto_id=v_producto.id_producto AND c.estado='REGISTRADA'
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

CREATE OR REPLACE FUNCTION public.registrar_venta_segura(p_solicitud_id uuid, p_cliente_id integer, p_forma_pago_id integer, p_items jsonb, p_fecha_limite date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET "TimeZone" TO 'America/Guatemala'
AS $function$
DECLARE
 v_usuario uuid:=auth.uid(); v_firma text; v_existente public.ventas%ROWTYPE; v_resultado jsonb;
BEGIN
 IF v_usuario IS NULL OR NOT public.fn_tiene_rol(ARRAY['ADMINISTRADOR','CAJERO']::text[]) THEN
  RAISE EXCEPTION 'No tienes permiso para registrar ventas' USING ERRCODE='42501';
 END IF;
 IF p_solicitud_id IS NULL THEN RAISE EXCEPTION 'Falta el identificador de la operación' USING ERRCODE='22023'; END IF;
 v_firma:=encode(sha256(convert_to(jsonb_build_object('cliente',p_cliente_id,'pago',p_forma_pago_id,'items',p_items,'fecha',p_fecha_limite)::text,'UTF8')),'hex');
 PERFORM pg_advisory_xact_lock(hashtextextended(p_solicitud_id::text,0));
 SELECT * INTO v_existente FROM public.ventas WHERE solicitud_id=p_solicitud_id;
 IF FOUND THEN
  IF v_existente.usuario_id<>v_usuario OR v_existente.solicitud_firma IS DISTINCT FROM v_firma THEN
   RAISE EXCEPTION 'La referencia ya corresponde a otra operación. Revisa el historial' USING ERRCODE='22023';
  END IF;
  RETURN jsonb_build_object('id_venta',v_existente.id_venta,'total',v_existente.total,'estado',v_existente.estado,'repetida',true);
 END IF;
 v_resultado:=public.registrar_venta(p_cliente_id,p_forma_pago_id,p_items,p_fecha_limite);
 UPDATE public.ventas SET solicitud_id=p_solicitud_id,solicitud_firma=v_firma WHERE id_venta=(v_resultado->>'id_venta')::integer;
 RETURN v_resultado||jsonb_build_object('repetida',false);
END;
$function$;
REVOKE ALL ON FUNCTION public.registrar_venta(integer,integer,jsonb,date) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.registrar_venta(integer,integer,jsonb,date) TO authenticated;
REVOKE ALL ON FUNCTION public.registrar_venta_segura(uuid,integer,integer,jsonb,date) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.registrar_venta_segura(uuid,integer,integer,jsonb,date) TO authenticated;
COMMIT;
