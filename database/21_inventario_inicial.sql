BEGIN;
CREATE TABLE public.inventarios_iniciales (
  id_inicial bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  solicitud_id uuid NOT NULL UNIQUE,
  producto_id integer NOT NULL UNIQUE REFERENCES public.productos(id_producto),
  usuario_id uuid NOT NULL REFERENCES public.usuarios(id_usuario),
  fecha timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  parametros jsonb NOT NULL,
  resultado jsonb NOT NULL DEFAULT '{}'::jsonb
);
CREATE INDEX inventarios_iniciales_usuario_idx ON public.inventarios_iniciales(usuario_id);
ALTER TABLE public.inventarios_iniciales ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.inventarios_iniciales FROM anon,authenticated;
GRANT SELECT ON public.inventarios_iniciales TO authenticated;
CREATE POLICY inventarios_iniciales_lectura ON public.inventarios_iniciales FOR SELECT TO authenticated
  USING(public.fn_tiene_rol(ARRAY['ADMINISTRADOR','INVENTARIO']));

ALTER TABLE public.lotes ALTER COLUMN detalle_compra_id DROP NOT NULL;
ALTER TABLE public.lotes ADD COLUMN entrada_inicial_id bigint REFERENCES public.inventarios_iniciales(id_inicial),
  ADD COLUMN costo_inicial numeric(12,2),
  ADD CONSTRAINT lote_origen_unico CHECK (
    (detalle_compra_id IS NOT NULL AND entrada_inicial_id IS NULL AND costo_inicial IS NULL) OR
    (detalle_compra_id IS NULL AND entrada_inicial_id IS NOT NULL AND costo_inicial IS NOT NULL AND costo_inicial>=0 AND costo_inicial<=9999999999.99)
  );
CREATE INDEX lotes_entrada_inicial_idx ON public.lotes(entrada_inicial_id);

-- Esta vista no evita RLS: unifica la procedencia sin crear compras ficticias.
CREATE VIEW public.lotes_contexto WITH(security_invoker=true) AS
SELECT l.id_lote,l.numero_lote,l.fecha_ingreso,l.fecha_vencimiento,l.detalle_compra_id,l.entrada_inicial_id,
  coalesce(d.producto_id,i.producto_id) AS producto_id,
  CASE WHEN l.entrada_inicial_id IS NOT NULL THEN l.costo_inicial ELSE d.costo_unitario END AS costo_unitario,
  CASE WHEN l.entrada_inicial_id IS NOT NULL THEN 'REGISTRADA'::text ELSE c.estado::text END AS estado,
  CASE WHEN l.entrada_inicial_id IS NOT NULL THEN 'LOTE_INICIAL'::text ELSE 'LOTE_COMPRA'::text END AS origen
FROM public.lotes l LEFT JOIN public.detalle_compras d ON d.id_detalle_compra=l.detalle_compra_id
LEFT JOIN public.compras c ON c.id_compra=d.compra_id
LEFT JOIN public.inventarios_iniciales i ON i.id_inicial=l.entrada_inicial_id;
REVOKE ALL ON public.lotes_contexto FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.lotes_contexto TO authenticated;

INSERT INTO public.tipos_movimientos(nombre,factor)
VALUES('INVENTARIO_INICIAL',1) ON CONFLICT(nombre) DO NOTHING;
ALTER TABLE public.movimientos_inventario DROP CONSTRAINT movimiento_costo_venta_valido;
ALTER TABLE public.movimientos_inventario ADD CONSTRAINT movimiento_costo_venta_valido CHECK (
  (costo_unitario_venta IS NULL AND origen_costo_venta IS NULL) OR
  (costo_unitario_venta IS NOT NULL AND costo_unitario_venta>=0 AND costo_unitario_venta<=9999999999.99
    AND origen_costo_venta IS NOT NULL AND origen_costo_venta IN ('LOTE_COMPRA','LOTE_INICIAL','ULTIMO_COSTO'))
);

CREATE OR REPLACE FUNCTION tienda_privada.proteger_origen_lote_inicial()
RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $fn$
BEGIN
  IF TG_OP='DELETE' THEN
    IF OLD.entrada_inicial_id IS NOT NULL THEN RAISE EXCEPTION 'El lote inicial se conserva como historial. Corrige cantidades mediante Inventario.' USING ERRCODE='22023'; END IF;
    RETURN OLD;
  END IF;
  IF OLD.entrada_inicial_id IS DISTINCT FROM NEW.entrada_inicial_id OR
    (OLD.entrada_inicial_id IS NOT NULL AND ROW(OLD.detalle_compra_id,OLD.numero_lote,OLD.fecha_ingreso,OLD.fecha_vencimiento,OLD.costo_inicial) IS DISTINCT FROM ROW(NEW.detalle_compra_id,NEW.numero_lote,NEW.fecha_ingreso,NEW.fecha_vencimiento,NEW.costo_inicial)) THEN
    RAISE EXCEPTION 'El origen y los datos del lote inicial forman parte del historial y no se sobrescriben.' USING ERRCODE='22023';
  END IF;
  RETURN NEW;
END;
$fn$;
REVOKE ALL ON FUNCTION tienda_privada.proteger_origen_lote_inicial() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER proteger_origen_lote_inicial BEFORE UPDATE OR DELETE ON public.lotes
FOR EACH ROW EXECUTE FUNCTION tienda_privada.proteger_origen_lote_inicial();

CREATE OR REPLACE FUNCTION tienda_privada.registrar_inventario_inicial(p_solicitud_id uuid,p_producto_id integer,p_partidas jsonb,p_motivo text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' SET timezone='America/Guatemala' AS $fn$
DECLARE
  v_usuario uuid:=auth.uid(); v_producto public.productos%ROWTYPE;v_anterior public.inventarios_iniciales%ROWTYPE;
  v_params jsonb;v_resultado jsonb;v_partida jsonb;v_cantidad integer;v_total bigint:=0;v_costo numeric;
  v_valor numeric:=0;v_fecha date;v_numero text;v_id bigint;v_lote integer;v_mov integer;v_tipo integer;
  v_lotes jsonb:='[]'::jsonb;v_hoy date:=(CURRENT_TIMESTAMP AT TIME ZONE 'America/Guatemala')::date;
BEGIN
  IF v_usuario IS NULL OR NOT public.fn_tiene_rol(ARRAY['ADMINISTRADOR']) THEN RAISE EXCEPTION 'Solo el administrador puede registrar inventario inicial.' USING ERRCODE='42501'; END IF;
  IF p_solicitud_id IS NULL OR p_producto_id IS NULL OR p_motivo IS NULL OR length(trim(p_motivo)) NOT BETWEEN 1 AND 500
    OR p_partidas IS NULL OR jsonb_typeof(p_partidas)<>'array' THEN RAISE EXCEPTION 'Revisa producto, partidas y motivo.' USING ERRCODE='22023'; END IF;
  IF jsonb_array_length(p_partidas) NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'Registra de 1 a 100 partidas en la carga inicial.' USING ERRCODE='22023'; END IF;
  v_params:=jsonb_build_object('producto',p_producto_id,'partidas',p_partidas,'motivo',trim(p_motivo));
  PERFORM pg_advisory_xact_lock(hashtextextended('inventario-inicial:'||p_solicitud_id::text,0));
  SELECT * INTO v_anterior FROM public.inventarios_iniciales WHERE solicitud_id=p_solicitud_id;
  IF FOUND THEN
    IF v_anterior.usuario_id<>v_usuario OR v_anterior.parametros<>v_params THEN RAISE EXCEPTION 'La referencia ya corresponde a otra carga inicial.' USING ERRCODE='22023'; END IF;
    RETURN v_anterior.resultado||jsonb_build_object('repetida',true);
  END IF;
  SELECT * INTO v_producto FROM public.productos WHERE id_producto=p_producto_id FOR UPDATE;
  IF NOT FOUND OR NOT v_producto.activo THEN RAISE EXCEPTION 'Selecciona un producto activo.' USING ERRCODE='22023'; END IF;
  IF v_producto.existencia<>0 OR EXISTS(SELECT 1 FROM public.inventarios_iniciales WHERE producto_id=p_producto_id)
    OR EXISTS(SELECT 1 FROM public.movimientos_inventario WHERE producto_id=p_producto_id)
    OR EXISTS(SELECT 1 FROM public.detalle_compras WHERE producto_id=p_producto_id)
    OR EXISTS(SELECT 1 FROM public.detalle_ventas WHERE producto_id=p_producto_id) THEN
    RAISE EXCEPTION 'Este producto ya tiene existencias o historial. La carga inicial solo se admite antes de operar; no borres movimientos para repetirla.' USING ERRCODE='22023';
  END IF;
  IF NOT v_producto.controla_lotes AND jsonb_array_length(p_partidas)<>1 THEN RAISE EXCEPTION 'Un producto sin lotes requiere una sola partida.' USING ERRCODE='22023'; END IF;
  SELECT id_tipo_movimiento INTO v_tipo FROM public.tipos_movimientos WHERE nombre='INVENTARIO_INICIAL' AND factor=1;
  IF NOT FOUND THEN RAISE EXCEPTION 'Falta configurar el movimiento de inventario inicial.'; END IF;
  -- Validar todo antes de crear el comprobante. Cero costo es explícito; un costo desconocido no se convierte en cero.
  FOR v_partida IN SELECT value FROM jsonb_array_elements(p_partidas) LOOP
    IF jsonb_typeof(v_partida)<>'object' OR coalesce(v_partida->>'cantidad','')!~'^[0-9]{1,10}$'
      OR coalesce(v_partida->>'costo_unitario','')!~'^[0-9]{1,10}(\.[0-9]{1,2})?$' THEN RAISE EXCEPTION 'Cada partida requiere cantidad entera positiva y costo de hasta dos decimales.' USING ERRCODE='22023'; END IF;
    IF (v_partida->>'cantidad')::bigint NOT BETWEEN 1 AND 2147483647 THEN RAISE EXCEPTION 'Cantidad fuera de rango.' USING ERRCODE='22023'; END IF;
    v_cantidad:=(v_partida->>'cantidad')::integer;v_costo:=(v_partida->>'costo_unitario')::numeric;
    IF v_costo>9999999999.99 THEN RAISE EXCEPTION 'Costo fuera de rango.' USING ERRCODE='22023'; END IF;
    v_total:=v_total+v_cantidad;v_valor:=v_valor+v_cantidad::numeric*v_costo;
    IF v_total>2147483647 THEN RAISE EXCEPTION 'El total de unidades supera el máximo permitido.' USING ERRCODE='22023'; END IF;
    IF v_producto.controla_lotes THEN
      IF jsonb_typeof(v_partida->'numero_lote') IS DISTINCT FROM 'string' OR length(trim(v_partida->>'numero_lote')) NOT BETWEEN 1 AND 50 THEN RAISE EXCEPTION 'Identifica cada lote con 1 a 50 caracteres; puedes usar una referencia interna si el empaque no lo indica.' USING ERRCODE='22023'; END IF;
      IF v_partida->>'fecha_vencimiento' IS NOT NULL THEN
        IF v_partida->>'fecha_vencimiento'!~'^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN RAISE EXCEPTION 'Fecha de vencimiento inválida.' USING ERRCODE='22023'; END IF;
        v_fecha:=(v_partida->>'fecha_vencimiento')::date;
        IF v_fecha<v_hoy THEN RAISE EXCEPTION 'Aparta los productos ya vencidos; no los cargues como inventario inicial vendible.' USING ERRCODE='22023'; END IF;
      END IF;
    ELSIF v_partida->>'numero_lote' IS NOT NULL OR v_partida->>'fecha_vencimiento' IS NOT NULL THEN RAISE EXCEPTION 'Este producto no usa lotes.' USING ERRCODE='22023';
    END IF;
  END LOOP;
  IF v_producto.controla_lotes AND (SELECT count(*)<>count(DISTINCT (trim(x->>'numero_lote'),coalesce(x->>'fecha_vencimiento',''))) FROM jsonb_array_elements(p_partidas)x) THEN
    RAISE EXCEPTION 'Hay un lote y vencimiento repetidos; reúne sus unidades en una sola partida.' USING ERRCODE='22023';
  END IF;
  INSERT INTO public.inventarios_iniciales(solicitud_id,producto_id,usuario_id,parametros)
    VALUES(p_solicitud_id,p_producto_id,v_usuario,v_params) RETURNING id_inicial INTO v_id;
  FOR v_partida IN SELECT value FROM jsonb_array_elements(p_partidas) LOOP
    v_lote:=NULL;v_cantidad:=(v_partida->>'cantidad')::integer;v_costo:=(v_partida->>'costo_unitario')::numeric;
    IF v_producto.controla_lotes THEN
      v_numero:=trim(v_partida->>'numero_lote');v_fecha:=(v_partida->>'fecha_vencimiento')::date;
      INSERT INTO public.lotes(entrada_inicial_id,costo_inicial,numero_lote,fecha_ingreso,fecha_vencimiento)
        VALUES(v_id,v_costo,v_numero,v_hoy,v_fecha) RETURNING id_lote INTO v_lote;
    END IF;
    INSERT INTO public.movimientos_inventario(producto_id,lote_id,tipo_movimiento_id,cantidad,usuario_id,observacion)
      VALUES(p_producto_id,v_lote,v_tipo,v_cantidad,v_usuario,'Inventario inicial: '||left(trim(p_motivo),450)) RETURNING id_movimiento_inventario INTO v_mov;
    v_lotes:=v_lotes||jsonb_build_array(jsonb_build_object('lote_id',v_lote,'numero_lote',v_partida->>'numero_lote','fecha_vencimiento',v_partida->>'fecha_vencimiento','cantidad',v_cantidad,'costo_unitario',v_costo,'movimiento_id',v_mov));
  END LOOP;
  -- Referencia para presupuestos futuros; las ventas por lote conservarán su costo propio.
  UPDATE public.productos SET ultimo_costo=round(v_valor/v_total,2) WHERE id_producto=p_producto_id;
  v_resultado:=jsonb_build_object('id_inicial',v_id,'producto_id',p_producto_id,'cantidad',v_total,'valor_inicial',v_valor,'partidas',v_lotes,'repetida',false);
  UPDATE public.inventarios_iniciales SET resultado=v_resultado WHERE id_inicial=v_id;
  RETURN v_resultado;
END;
$fn$;
REVOKE ALL ON FUNCTION tienda_privada.registrar_inventario_inicial(uuid,integer,jsonb,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION tienda_privada.registrar_inventario_inicial(uuid,integer,jsonb,text) TO authenticated;
CREATE OR REPLACE FUNCTION public.registrar_inventario_inicial(p_solicitud_id uuid,p_producto_id integer,p_partidas jsonb,p_motivo text)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $fn$
  SELECT tienda_privada.registrar_inventario_inicial(p_solicitud_id,p_producto_id,p_partidas,p_motivo);
$fn$;
REVOKE ALL ON FUNCTION public.registrar_inventario_inicial(uuid,integer,jsonb,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.registrar_inventario_inicial(uuid,integer,jsonb,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.obtener_productos_inicial(p_busqueda text DEFAULT '',p_modo text DEFAULT 'nombre')
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path='' AS $fn$
DECLARE v_resultado jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT public.fn_tiene_rol(ARRAY['ADMINISTRADOR']) THEN RAISE EXCEPTION 'Solo el administrador puede preparar inventario inicial.' USING ERRCODE='42501'; END IF;
  IF p_busqueda IS NULL OR length(p_busqueda)>150 OR p_modo IS NULL OR p_modo NOT IN ('nombre','codigo_barras') THEN RAISE EXCEPTION 'Revisa la búsqueda.' USING ERRCODE='22023'; END IF;
  SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.nombre,t.id_producto),'[]'::jsonb) INTO v_resultado FROM (
    SELECT p.id_producto,p.nombre,p.codigo_barras,p.existencia,p.controla_lotes,p.activo,i.resultado AS inicial,
      p.activo AND p.existencia=0 AND i.id_inicial IS NULL
        AND NOT EXISTS(SELECT 1 FROM public.movimientos_inventario m WHERE m.producto_id=p.id_producto)
        AND NOT EXISTS(SELECT 1 FROM public.detalle_compras d WHERE d.producto_id=p.id_producto)
        AND NOT EXISTS(SELECT 1 FROM public.detalle_ventas d WHERE d.producto_id=p.id_producto) AS disponible_inicial
    FROM public.productos p LEFT JOIN public.inventarios_iniciales i ON i.producto_id=p.id_producto
    WHERE trim(p_busqueda)='' OR CASE WHEN p_modo='codigo_barras' THEN p.codigo_barras=trim(p_busqueda) ELSE strpos(lower(p.nombre),lower(trim(p_busqueda)))>0 END
    ORDER BY p.nombre,p.id_producto LIMIT 20
  )t;
  RETURN v_resultado;
END;
$fn$;
REVOKE ALL ON FUNCTION public.obtener_productos_inicial(text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.obtener_productos_inicial(text,text) TO authenticated;

-- Las definiciones compatibles de ventas, ajustes, alertas y reportes siguen abajo.

CREATE OR REPLACE FUNCTION public.fn_validar_movimiento_inventario()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE
    v_producto_lote INTEGER;
    v_producto_compra INTEGER;
    v_producto_venta INTEGER;
BEGIN

    /* ============================================
       VALIDAR LOTE
       ============================================ */

    IF NEW.lote_id IS NOT NULL THEN

        SELECT l.producto_id INTO v_producto_lote FROM public.lotes_contexto l
        WHERE l.id_lote = NEW.lote_id;

        IF v_producto_lote IS DISTINCT FROM NEW.producto_id THEN
            RAISE EXCEPTION
                'El lote % no pertenece al producto %',
                NEW.lote_id,
                NEW.producto_id;
        END IF;

    END IF;


    /* ============================================
       VALIDAR DETALLE DE COMPRA
       ============================================ */

    IF NEW.detalle_compra_id IS NOT NULL THEN

        SELECT producto_id
        INTO v_producto_compra
        FROM public.detalle_compras
        WHERE id_detalle_compra = NEW.detalle_compra_id;

        IF v_producto_compra <> NEW.producto_id THEN
            RAISE EXCEPTION
                'El detalle de compra % no corresponde al producto %',
                NEW.detalle_compra_id,
                NEW.producto_id;
        END IF;

    END IF;


    /* ============================================
       VALIDAR DETALLE DE VENTA
       ============================================ */

    IF NEW.detalle_venta_id IS NOT NULL THEN

        SELECT producto_id
        INTO v_producto_venta
        FROM public.detalle_ventas
        WHERE id_detalle_venta = NEW.detalle_venta_id;

        IF v_producto_venta <> NEW.producto_id THEN
            RAISE EXCEPTION
                'El detalle de venta % no corresponde al producto %',
                NEW.detalle_venta_id,
                NEW.producto_id;
        END IF;

    END IF;


    RETURN NEW;
END;
$function$;

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

CREATE OR REPLACE FUNCTION public.obtener_dashboard()
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE
 v_hoy date:=(CURRENT_TIMESTAMP AT TIME ZONE 'America/Guatemala')::date;
 v_resultado jsonb;
BEGIN
 IF auth.uid() IS NULL OR NOT public.fn_tiene_rol(ARRAY['ADMINISTRADOR']::text[]) THEN
  RAISE EXCEPTION 'El dashboard está disponible para el administrador activo' USING ERRCODE='42501';
 END IF;
 WITH detalles AS (
  SELECT venta_id,sum(subtotal) total_detalles,count(*) lineas FROM public.detalle_ventas GROUP BY venta_id
 ), revisadas AS (
  SELECT v.*,coalesce(d.total_detalles,0) total_detalles,
   (coalesce(d.lineas,0)>0 AND v.total=d.total_detalles) consistente
  FROM public.ventas v LEFT JOIN detalles d ON d.venta_id=v.id_venta WHERE v.estado='REGISTRADA'
 ), validas AS (
  SELECT * FROM revisadas WHERE consistente
 ), hoy AS (
  SELECT * FROM validas WHERE fecha>=(v_hoy::timestamp AT TIME ZONE 'America/Guatemala')
   AND fecha<((v_hoy+1)::timestamp AT TIME ZONE 'America/Guatemala')
 ), inventario AS (
  SELECT * FROM public.productos WHERE activo
 ), lotes_stock AS (
  SELECT l.id_lote,l.numero_lote,l.fecha_vencimiento,p.nombre producto,
   public.fn_stock_lote(l.id_lote) existencia
  FROM public.lotes_contexto l
  JOIN public.productos p ON p.id_producto=l.producto_id
  WHERE p.activo AND l.estado='REGISTRADA' AND l.fecha_vencimiento IS NOT NULL
 ), lotes AS (
  SELECT *,fecha_vencimiento-v_hoy dias FROM lotes_stock WHERE existencia>0
 ), dias AS (
  SELECT v_hoy-6+n dia FROM generate_series(0,6) AS serie(n)
 ), serie AS (
  SELECT d.dia,coalesce(sum(v.total),0) total,count(v.id_venta) transacciones
  FROM dias d LEFT JOIN validas v
   ON v.fecha>=(d.dia::timestamp AT TIME ZONE 'America/Guatemala')
    AND v.fecha<((d.dia+1)::timestamp AT TIME ZONE 'America/Guatemala')
  GROUP BY d.dia
 ), cobrar AS (
  SELECT c.* FROM public.cuentas_por_cobrar c JOIN public.ventas v ON v.id_venta=c.venta_id
  WHERE v.estado='REGISTRADA' AND c.saldo_pendiente>0
 ), pagar AS (
  SELECT c.* FROM public.cuentas_por_pagar c JOIN public.compras p ON p.id_compra=c.compra_id
  WHERE p.estado='REGISTRADA' AND c.saldo_pendiente>0
 )
 SELECT jsonb_build_object(
  'fecha',v_hoy,'actualizado',CURRENT_TIMESTAMP,
  'ventas_hoy',coalesce((SELECT sum(total) FROM hoy),0),
  'transacciones_hoy',(SELECT count(*) FROM hoy),
  'ticket_promedio',coalesce((SELECT avg(total) FROM hoy),0),
  'productos_activos',(SELECT count(*) FROM inventario),
  'agotados',(SELECT count(*) FROM inventario WHERE existencia=0),
  'bajo_minimo',(SELECT count(*) FROM inventario WHERE existencia>0 AND existencia<=existencia_minima),
  'lotes_proximos',(SELECT count(*) FROM lotes WHERE dias BETWEEN 0 AND 30),
  'lotes_vencidos',(SELECT count(*) FROM lotes WHERE dias<0),
  'por_cobrar',coalesce((SELECT sum(saldo_pendiente) FROM cobrar),0),
  'por_cobrar_vencido',coalesce((SELECT sum(saldo_pendiente) FROM cobrar WHERE fecha_limite<v_hoy),0),
  'por_pagar',coalesce((SELECT sum(saldo_pendiente) FROM pagar),0),
  'por_pagar_vencido',coalesce((SELECT sum(saldo_pendiente) FROM pagar WHERE fecha_limite<v_hoy),0),
  'ventas_inconsistentes',(SELECT count(*) FROM revisadas WHERE NOT consistente),
  'inconsistencias',coalesce((SELECT jsonb_agg(to_jsonb(x)) FROM (
   SELECT id_venta,total,total_detalles FROM revisadas WHERE NOT consistente ORDER BY id_venta LIMIT 20
  )x),'[]'::jsonb),
  'serie',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.dia) FROM serie x),'[]'::jsonb),
  'reponer',coalesce((SELECT jsonb_agg(to_jsonb(x)) FROM (
   SELECT id_producto,nombre,existencia,existencia_minima FROM inventario
   WHERE existencia<=existencia_minima ORDER BY existencia,nombre,id_producto LIMIT 20
  )x),'[]'::jsonb),
  'vencimientos',coalesce((SELECT jsonb_agg(to_jsonb(x)) FROM (
   SELECT id_lote,numero_lote,producto,fecha_vencimiento,existencia,dias FROM lotes
   WHERE dias<=30 ORDER BY fecha_vencimiento,id_lote LIMIT 20
  )x),'[]'::jsonb)
 ) INTO v_resultado;
 RETURN v_resultado;
END;
$function$;

CREATE OR REPLACE FUNCTION tienda_privada.registrar_ajuste_inventario(p_solicitud_id uuid, p_producto_id integer, p_lote_id integer, p_tipo text, p_cantidad integer, p_existencia_esperada integer, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET "TimeZone" TO 'America/Guatemala'
AS $function$
DECLARE
  v_usuario uuid:=auth.uid(); v_producto public.productos%ROWTYPE; v_lote public.lotes%ROWTYPE;
  v_anterior public.ajustes_inventario%ROWTYPE; v_params jsonb; v_resultado jsonb;
  v_stock integer; v_delta bigint; v_nuevo bigint; v_tipo text; v_tipo_id integer; v_mov integer; v_id bigint;
  v_hoy date:=(CURRENT_TIMESTAMP AT TIME ZONE 'America/Guatemala')::date;
BEGIN
  IF v_usuario IS NULL OR NOT public.fn_tiene_rol(ARRAY['ADMINISTRADOR','INVENTARIO']) THEN
    RAISE EXCEPTION 'No tienes permiso para ajustar inventario.' USING ERRCODE='42501';
  END IF;
  IF p_solicitud_id IS NULL OR p_producto_id IS NULL OR p_tipo IS NULL
     OR p_tipo NOT IN ('CONTEO','PERDIDA','VENCIMIENTO','AJUSTE_POSITIVO','AJUSTE_NEGATIVO')
     OR p_cantidad IS NULL OR p_cantidad<0 OR (p_tipo<>'CONTEO' AND p_cantidad=0)
     OR p_existencia_esperada IS NULL OR p_existencia_esperada<0
     OR p_motivo IS NULL OR length(trim(p_motivo)) NOT BETWEEN 1 AND 500 THEN
    RAISE EXCEPTION 'Revisa producto, cantidad, existencia vista y motivo.' USING ERRCODE='22023';
  END IF;
  v_params:=jsonb_build_object('producto',p_producto_id,'lote',p_lote_id,'tipo',p_tipo,'cantidad',p_cantidad,'esperada',p_existencia_esperada,'motivo',trim(p_motivo));
  PERFORM pg_advisory_xact_lock(hashtextextended('ajuste-inventario:'||p_solicitud_id::text,0));
  SELECT * INTO v_anterior FROM public.ajustes_inventario WHERE solicitud_id=p_solicitud_id;
  IF FOUND THEN
    IF v_anterior.usuario_id<>v_usuario OR v_anterior.parametros<>v_params THEN
      RAISE EXCEPTION 'La referencia ya corresponde a otro ajuste.' USING ERRCODE='22023';
    END IF;
    RETURN v_anterior.resultado||jsonb_build_object('repetida',true);
  END IF;
  SELECT * INTO v_producto FROM public.productos WHERE id_producto=p_producto_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Producto no encontrado.' USING ERRCODE='22023'; END IF;
  IF v_producto.controla_lotes THEN
    IF p_lote_id IS NULL THEN RAISE EXCEPTION 'Selecciona el lote físico que estás ajustando.' USING ERRCODE='22023'; END IF;
    SELECT l.* INTO v_lote FROM public.lotes l JOIN public.lotes_contexto d ON d.id_lote=l.id_lote
      WHERE l.id_lote=p_lote_id AND d.producto_id=p_producto_id AND d.estado='REGISTRADA' FOR UPDATE OF l;
    IF NOT FOUND THEN RAISE EXCEPTION 'El lote no pertenece a este producto o su compra no está registrada.' USING ERRCODE='22023'; END IF;
    IF v_producto.existencia<>(SELECT coalesce(sum(public.fn_stock_lote(l.id_lote)),0) FROM public.lotes_contexto l WHERE l.producto_id=p_producto_id) THEN
      RAISE EXCEPTION 'La existencia del producto no coincide con la suma de sus lotes. Revisa el historial antes de ajustar.' USING ERRCODE='22023';
    END IF;
    v_stock:=public.fn_stock_lote(p_lote_id);
  ELSE
    IF p_lote_id IS NOT NULL THEN RAISE EXCEPTION 'Este producto no usa lotes.' USING ERRCODE='22023'; END IF;
    v_stock:=v_producto.existencia;
  END IF;
  IF v_stock<0 THEN RAISE EXCEPTION 'El lote tiene una existencia inconsistente.' USING ERRCODE='22023'; END IF;
  IF v_stock<>p_existencia_esperada THEN
    RAISE EXCEPTION 'La existencia cambió desde tu consulta: ahora es %. Actualiza, revisa el conteo y prepara otra confirmación.',v_stock USING ERRCODE='22023';
  END IF;
  IF p_tipo='VENCIMIENTO' AND (p_lote_id IS NULL OR v_lote.fecha_vencimiento IS NULL OR v_lote.fecha_vencimiento>=v_hoy) THEN
    RAISE EXCEPTION 'Vencimiento solo permite retirar unidades de un lote con fecha anterior a hoy.' USING ERRCODE='22023';
  END IF;
  v_delta:=CASE WHEN p_tipo='CONTEO' THEN p_cantidad::bigint-v_stock WHEN p_tipo='AJUSTE_POSITIVO' THEN p_cantidad::bigint ELSE -p_cantidad::bigint END;
  v_nuevo:=v_producto.existencia::bigint+v_delta;
  IF v_stock::bigint+v_delta<0 OR v_nuevo<0 OR v_nuevo>2147483647 THEN
    RAISE EXCEPTION 'La cantidad supera la existencia disponible o el máximo permitido.' USING ERRCODE='22023';
  END IF;
  IF v_delta<>0 THEN
    v_tipo:=CASE WHEN p_tipo='CONTEO' THEN CASE WHEN v_delta>0 THEN 'AJUSTE_POSITIVO' ELSE 'AJUSTE_NEGATIVO' END ELSE p_tipo END;
    SELECT id_tipo_movimiento INTO v_tipo_id FROM public.tipos_movimientos WHERE nombre=v_tipo AND factor=CASE WHEN v_delta>0 THEN 1 ELSE -1 END;
    IF NOT FOUND THEN RAISE EXCEPTION 'El catálogo de movimientos requiere revisión.' USING ERRCODE='22023'; END IF;
    INSERT INTO public.movimientos_inventario(producto_id,lote_id,tipo_movimiento_id,cantidad,usuario_id,observacion)
    VALUES(p_producto_id,p_lote_id,v_tipo_id,abs(v_delta)::integer,v_usuario,trim(p_motivo)) RETURNING id_movimiento_inventario INTO v_mov;
  END IF;
  v_resultado:=jsonb_build_object('producto_id',p_producto_id,'lote_id',p_lote_id,'tipo',p_tipo,
    'existencia_anterior',v_stock,'existencia_nueva',v_stock::bigint+v_delta,'variacion',v_delta,
    'producto_anterior',v_producto.existencia,'producto_nuevo',v_nuevo,'movimiento_id',v_mov,'repetida',false);
  INSERT INTO public.ajustes_inventario(solicitud_id,producto_id,lote_id,movimiento_id,usuario_id,tipo,motivo,parametros,resultado)
  VALUES(p_solicitud_id,p_producto_id,p_lote_id,v_mov,v_usuario,p_tipo,trim(p_motivo),v_params,v_resultado) RETURNING id_ajuste INTO v_id;
  v_resultado:=v_resultado||jsonb_build_object('id_ajuste',v_id);
  UPDATE public.ajustes_inventario SET resultado=v_resultado WHERE id_ajuste=v_id;
  RETURN v_resultado;
END;
$function$;

CREATE OR REPLACE FUNCTION tienda_privada.capturar_costo_venta()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_costo numeric; v_tipo text; v_origen text;
BEGIN
  NEW.costo_unitario_venta:=NULL;NEW.origen_costo_venta:=NULL;
  SELECT nombre INTO v_tipo FROM public.tipos_movimientos WHERE id_tipo_movimiento=NEW.tipo_movimiento_id;
  IF v_tipo<>'VENTA' OR NEW.detalle_venta_id IS NULL THEN RETURN NEW; END IF;
  IF NEW.lote_id IS NOT NULL THEN
    SELECT l.costo_unitario,l.origen INTO v_costo,v_origen FROM public.lotes_contexto l
    WHERE l.id_lote=NEW.lote_id AND l.producto_id=NEW.producto_id AND l.estado='REGISTRADA';
    IF v_costo IS NOT NULL AND v_costo>=0 AND v_costo<=9999999999.99 THEN
      NEW.costo_unitario_venta:=v_costo;NEW.origen_costo_venta:=v_origen;
    END IF;
  ELSE
    SELECT ultimo_costo INTO v_costo FROM public.productos WHERE id_producto=NEW.producto_id FOR UPDATE;
    IF v_costo IS NOT NULL AND v_costo>=0 AND v_costo<=9999999999.99 THEN
      NEW.costo_unitario_venta:=v_costo;NEW.origen_costo_venta:='ULTIMO_COSTO';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.obtener_inventario_producto(p_producto_id integer, p_pagina_lotes integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE v_resultado jsonb; v_hoy date:=(CURRENT_TIMESTAMP AT TIME ZONE 'America/Guatemala')::date;
BEGIN
  IF auth.uid() IS NULL OR NOT public.fn_tiene_rol(ARRAY['ADMINISTRADOR','INVENTARIO']) THEN
    RAISE EXCEPTION 'No tienes permiso para consultar ajustes de inventario.' USING ERRCODE='42501';
  END IF;
  IF p_pagina_lotes IS NULL OR p_pagina_lotes<0 OR p_pagina_lotes>1000000 THEN RAISE EXCEPTION 'Página inválida.' USING ERRCODE='22023'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.productos WHERE id_producto=p_producto_id) THEN RAISE EXCEPTION 'Producto no encontrado.' USING ERRCODE='22023'; END IF;
  WITH lotes_validos AS (
    SELECT l.id_lote,l.numero_lote,l.fecha_ingreso,l.fecha_vencimiento,l.origen,public.fn_stock_lote(l.id_lote) AS existencia,
      coalesce(l.fecha_vencimiento<v_hoy,false) AS vencido
    FROM public.lotes_contexto l
    WHERE l.producto_id=p_producto_id AND l.estado='REGISTRADA'
  ), pagina AS (
    SELECT * FROM lotes_validos ORDER BY fecha_vencimiento ASC NULLS LAST,id_lote LIMIT 20 OFFSET p_pagina_lotes*20
  ), ajustes AS (
    SELECT id_ajuste,fecha,tipo,lote_id,motivo,resultado FROM public.ajustes_inventario WHERE producto_id=p_producto_id ORDER BY fecha DESC,id_ajuste DESC LIMIT 20
  ), movimientos AS (
    SELECT m.id_movimiento_inventario,m.fecha,t.nombre AS tipo,m.cantidad,t.factor,m.lote_id,m.observacion
    FROM public.movimientos_inventario m JOIN public.tipos_movimientos t ON t.id_tipo_movimiento=m.tipo_movimiento_id
    WHERE m.producto_id=p_producto_id ORDER BY m.fecha DESC,m.id_movimiento_inventario DESC LIMIT 30
  )
  SELECT jsonb_build_object('producto',(SELECT jsonb_build_object('id_producto',p.id_producto,'nombre',p.nombre,'codigo_barras',p.codigo_barras,'existencia',p.existencia,'controla_lotes',p.controla_lotes,'activo',p.activo) FROM public.productos p WHERE id_producto=p_producto_id),
    'total_lotes',(SELECT count(*) FROM lotes_validos),
    'suma_lotes',(SELECT coalesce(sum(public.fn_stock_lote(l.id_lote)),0) FROM public.lotes_contexto l WHERE l.producto_id=p_producto_id),
    'lotes',coalesce((SELECT jsonb_agg(to_jsonb(p) ORDER BY p.fecha_vencimiento ASC NULLS LAST,p.id_lote) FROM pagina p),'[]'::jsonb),
    'ajustes',coalesce((SELECT jsonb_agg(to_jsonb(a) ORDER BY a.fecha DESC,a.id_ajuste DESC) FROM ajustes a),'[]'::jsonb),
    'movimientos',coalesce((SELECT jsonb_agg(to_jsonb(m) ORDER BY m.fecha DESC,m.id_movimiento_inventario DESC) FROM movimientos m),'[]'::jsonb)) INTO v_resultado;
  RETURN v_resultado;
END;
$function$;

CREATE OR REPLACE FUNCTION public.obtener_lista_compras(p_busqueda text DEFAULT ''::text, p_modo text DEFAULT 'nombre'::text, p_solo_reponer boolean DEFAULT true, p_pagina integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
DECLARE v_hoy date:=(CURRENT_TIMESTAMP AT TIME ZONE 'America/Guatemala')::date;v_resultado jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT public.fn_tiene_rol(ARRAY['ADMINISTRADOR','INVENTARIO']) THEN RAISE EXCEPTION 'No tienes permiso para consultar la lista.' USING ERRCODE='42501';END IF;
  IF p_busqueda IS NULL OR length(p_busqueda)>150 OR p_modo IS NULL OR p_modo NOT IN ('nombre','codigo_barras') OR p_solo_reponer IS NULL OR p_pagina IS NULL OR p_pagina<0 OR p_pagina>1000000 THEN RAISE EXCEPTION 'Revisa la búsqueda o la página.' USING ERRCODE='22023';END IF;
  WITH stocks AS (
    SELECT l.producto_id,sum(public.fn_stock_lote(l.id_lote)) AS total,
      coalesce(sum(public.fn_stock_lote(l.id_lote)) FILTER(WHERE l.estado='REGISTRADA'),0) AS registrado,
      coalesce(sum(public.fn_stock_lote(l.id_lote)) FILTER(WHERE l.estado='REGISTRADA' AND (l.fecha_vencimiento IS NULL OR l.fecha_vencimiento>=v_hoy)),0) AS apto,
      coalesce(sum(public.fn_stock_lote(l.id_lote)) FILTER(WHERE l.estado='REGISTRADA' AND l.fecha_vencimiento<v_hoy),0) AS vencido,
      bool_or(public.fn_stock_lote(l.id_lote)<0) AS negativo
    FROM public.lotes_contexto l GROUP BY l.producto_id
  ), catalogo AS (
    SELECT p.id_producto,p.nombre,p.codigo_barras,p.activo,p.existencia,p.existencia_minima,p.controla_lotes,
      CASE WHEN p.controla_lotes THEN coalesce(s.apto,0) ELSE p.existencia END AS disponible,
      CASE WHEN p.controla_lotes THEN coalesce(s.vencido,0) ELSE 0 END AS vencido,
      p.controla_lotes AND (coalesce(s.total,0)<>p.existencia OR coalesce(s.registrado,0)<>p.existencia OR coalesce(s.negativo,false)) AS inconsistente,
      CASE WHEN p.ultimo_costo>=0 AND p.ultimo_costo<=9999999999.99 THEN p.ultimo_costo ELSE NULL END AS costo_estimado,
      coalesce(l.version,0) AS version_lista,coalesce(l.activo,false) AS en_lista,l.cantidad AS cantidad_lista,coalesce(l.nota,'') AS nota_lista
    FROM public.productos p LEFT JOIN stocks s ON s.producto_id=p.id_producto LEFT JOIN public.lista_compras l ON l.producto_id=p.id_producto
  ), candidatos AS (
    SELECT c.*,CASE WHEN inconsistente THEN NULL ELSE greatest(least(existencia_minima::bigint+1,2147483647)-disponible,0) END AS cantidad_sugerida
    FROM catalogo c WHERE activo AND (trim(p_busqueda)='' OR CASE WHEN p_modo='codigo_barras' THEN codigo_barras=trim(p_busqueda) ELSE strpos(lower(nombre),lower(trim(p_busqueda)))>0 END)
      AND (NOT p_solo_reponer OR disponible<=existencia_minima OR inconsistente)
  ), pagina AS (
    SELECT * FROM candidatos ORDER BY (disponible=0) DESC,disponible,nombre,id_producto LIMIT 20 OFFSET p_pagina*20
  ), lista AS (
    SELECT c.*,l.cantidad,l.nota,l.version,l.actualizado,CASE WHEN c.costo_estimado IS NULL THEN NULL ELSE l.cantidad::numeric*c.costo_estimado END AS subtotal_estimado
    FROM public.lista_compras l JOIN catalogo c ON c.id_producto=l.producto_id WHERE l.activo
  )
  SELECT jsonb_build_object('fecha',v_hoy,'total_candidatos',(SELECT count(*) FROM candidatos),
    'candidatos',coalesce((SELECT jsonb_agg(to_jsonb(p) ORDER BY (p.disponible=0) DESC,p.disponible,p.nombre,p.id_producto) FROM pagina p),'[]'::jsonb),
    'lista',coalesce((SELECT jsonb_agg(to_jsonb(l) ORDER BY l.nombre,l.id_producto) FROM lista l),'[]'::jsonb),
    'partidas',(SELECT count(*) FROM lista),'unidades',(SELECT coalesce(sum(cantidad),0) FROM lista),
    'subtotal_con_costo',(SELECT coalesce(sum(subtotal_estimado),0) FROM lista),'sin_costo',(SELECT count(*) FROM lista WHERE costo_estimado IS NULL)) INTO v_resultado;
  RETURN v_resultado;
END;
$function$;

CREATE OR REPLACE FUNCTION public.obtener_rotacion_productos(p_desde date, p_hasta date, p_objetivo integer DEFAULT 7, p_busqueda text DEFAULT ''::text, p_filtro text DEFAULT 'todos'::text, p_orden text DEFAULT 'reponer'::text, p_pagina integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
DECLARE
  v_hoy date := (CURRENT_TIMESTAMP AT TIME ZONE 'America/Guatemala')::date;
  v_dias integer; v_inicio timestamptz; v_fin timestamptz; v_resultado jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT public.fn_tiene_rol(ARRAY['ADMINISTRADOR']) THEN
    RAISE EXCEPTION 'Solo el administrador puede consultar la rotación.' USING ERRCODE='42501';
  END IF;
  IF p_desde IS NULL OR p_hasta IS NULL OR p_desde<'1900-01-01'::date OR p_desde>p_hasta OR p_hasta>v_hoy OR p_hasta-p_desde>365 THEN
    RAISE EXCEPTION 'Selecciona un período válido de hasta 366 días, sin fechas futuras.' USING ERRCODE='22023';
  END IF;
  IF p_objetivo IS NULL OR p_objetivo<1 OR p_objetivo>90 OR p_busqueda IS NULL OR length(p_busqueda)>150
    OR p_filtro IS NULL OR p_filtro NOT IN ('todos','reponer','sin_ventas','revisar')
    OR p_orden IS NULL OR p_orden NOT IN ('reponer','mas','menos')
    OR p_pagina IS NULL OR p_pagina<0 OR p_pagina>1000000 THEN
    RAISE EXCEPTION 'Revisa el objetivo, los filtros o la página.' USING ERRCODE='22023';
  END IF;
  v_dias:=p_hasta-p_desde+1;
  v_inicio:=p_desde::timestamp AT TIME ZONE 'America/Guatemala';
  v_fin:=(p_hasta+1)::timestamp AT TIME ZONE 'America/Guatemala';
  WITH candidatas AS (
    SELECT id_venta,total FROM public.ventas
    WHERE estado='REGISTRADA' AND fecha>=v_inicio AND fecha<v_fin
  ), revisadas AS (
    SELECT v.id_venta, count(d.id_detalle_venta)>0 AND v.total=coalesce(sum(d.subtotal),0) AS valida
    FROM candidatas v LEFT JOIN public.detalle_ventas d ON d.venta_id=v.id_venta GROUP BY v.id_venta,v.total
  ), vendido AS (
    SELECT d.producto_id,sum(d.cantidad) AS unidades,sum(d.subtotal) AS importe
    FROM public.detalle_ventas d JOIN revisadas v ON v.id_venta=d.venta_id AND v.valida GROUP BY d.producto_id
  ), lotes_stock AS MATERIALIZED (
    SELECT l.producto_id,l.estado,l.fecha_vencimiento,public.fn_stock_lote(l.id_lote) AS stock
    FROM public.lotes_contexto l
  ), stocks AS (
    SELECT producto_id,sum(stock) AS total,
      coalesce(sum(stock) FILTER(WHERE estado='REGISTRADA'),0) AS registrado,
      coalesce(sum(stock) FILTER(WHERE estado='REGISTRADA' AND (fecha_vencimiento IS NULL OR fecha_vencimiento>=v_hoy)),0) AS apto,
      coalesce(sum(stock) FILTER(WHERE estado='REGISTRADA' AND fecha_vencimiento<v_hoy),0) AS vencido,
      bool_or(stock<0) AS negativo
    FROM lotes_stock GROUP BY producto_id
  ), base AS (
    SELECT p.id_producto,p.nombre,p.codigo_barras,p.existencia,p.existencia_minima,
      coalesce(v.unidades,0) AS unidades,coalesce(v.importe,0) AS importe,
      CASE WHEN p.controla_lotes THEN coalesce(s.apto,0) ELSE p.existencia END AS disponible,
      CASE WHEN p.controla_lotes THEN coalesce(s.vencido,0) ELSE 0 END AS vencido,
      p.controla_lotes AND (coalesce(s.total,0)<>p.existencia OR coalesce(s.registrado,0)<>p.existencia OR coalesce(s.negativo,false)) AS inconsistente
    FROM public.productos p LEFT JOIN vendido v ON v.producto_id=p.id_producto LEFT JOIN stocks s ON s.producto_id=p.id_producto
    WHERE p.activo
  ), calculada AS (
    SELECT b.*,round(unidades::numeric/v_dias,4) AS promedio_diario,
      CASE WHEN unidades>0 AND NOT inconsistente THEN round(disponible::numeric*v_dias/unidades,2) END AS cobertura_dias,
      CASE WHEN unidades>0 AND NOT inconsistente THEN
        greatest(greatest(ceil(unidades::numeric*p_objetivo/v_dias),existencia_minima::numeric+1)-disponible,0)
      END AS sugerencia,
      NOT inconsistente AND disponible<=existencia_minima AS bajo_minimo
    FROM base b
  ), clasificada AS (
    SELECT c.*,CASE WHEN inconsistente THEN 'REVISAR' WHEN unidades=0 THEN 'SIN_VENTAS'
      WHEN sugerencia>0 THEN 'REPONER' ELSE 'SUFICIENTE' END AS estado
    FROM calculada c
  ), filtrada AS (
    SELECT * FROM clasificada WHERE (trim(p_busqueda)='' OR strpos(lower(nombre),lower(trim(p_busqueda)))>0 OR codigo_barras=trim(p_busqueda))
      AND (p_filtro='todos' OR p_filtro='reponer' AND estado='REPONER' OR p_filtro='sin_ventas' AND estado='SIN_VENTAS' OR p_filtro='revisar' AND estado='REVISAR')
  ), ordenada AS (
    SELECT f.*,row_number() OVER(ORDER BY
      CASE WHEN p_orden='reponer' THEN CASE estado WHEN 'REVISAR' THEN 0 WHEN 'REPONER' THEN 1 WHEN 'SIN_VENTAS' THEN 3 ELSE 2 END END,
      CASE WHEN p_orden='reponer' AND estado='REPONER' THEN disponible::numeric*v_dias/nullif(unidades,0) END ASC NULLS LAST,
      CASE WHEN p_orden='mas' THEN unidades END DESC,
      CASE WHEN p_orden='menos' THEN unidades END ASC,
      nombre,id_producto) AS posicion
    FROM filtrada f
  ), pagina AS (SELECT * FROM ordenada ORDER BY posicion LIMIT 20 OFFSET p_pagina*20)
  SELECT jsonb_build_object('desde',p_desde,'hasta',p_hasta,'dias',v_dias,'objetivo',p_objetivo,
    'fecha_stock',v_hoy,'actualizado',CURRENT_TIMESTAMP,'total',(SELECT count(*) FROM filtrada),
    'activos',(SELECT count(*) FROM clasificada),'con_ventas',(SELECT count(*) FROM clasificada WHERE unidades>0),
    'sin_ventas',(SELECT count(*) FROM clasificada WHERE unidades=0),'reponer',(SELECT count(*) FROM clasificada WHERE estado='REPONER'),
    'revisar',(SELECT count(*) FROM clasificada WHERE inconsistente),'bajo_minimo',(SELECT count(*) FROM clasificada WHERE bajo_minimo),
    'ventas_excluidas',(SELECT count(*) FROM revisadas WHERE NOT valida),
    'productos',coalesce((SELECT jsonb_agg(to_jsonb(p)-'posicion' ORDER BY p.posicion) FROM pagina p),'[]'::jsonb)) INTO v_resultado;
  RETURN v_resultado;
END;
$function$;


COMMIT;
