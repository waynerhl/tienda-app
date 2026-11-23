BEGIN;
ALTER TABLE public.compras ADD COLUMN fondo_efectivo text NOT NULL DEFAULT 'CAJA' CHECK(fondo_efectivo IN ('CAJA','RESERVA'));
ALTER TABLE public.pagos_cuentas_por_pagar ADD COLUMN fondo_efectivo text NOT NULL DEFAULT 'CAJA' CHECK(fondo_efectivo IN ('CAJA','RESERVA'));
CREATE TABLE public.reserva_saldo (
  id boolean PRIMARY KEY DEFAULT true CHECK(id),
  inicializada boolean NOT NULL DEFAULT false,
  saldo numeric(12,2) NOT NULL DEFAULT 0 CHECK(saldo>=0 AND saldo<=9999999999.99)
);
INSERT INTO public.reserva_saldo(id) VALUES(true);
CREATE TABLE public.reserva_eventos (
  id_evento bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  fecha timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  usuario_id uuid NOT NULL REFERENCES public.usuarios(id_usuario),
  solicitud_id uuid UNIQUE,
  tipo text NOT NULL CHECK(tipo IN ('INICIAL','APORTE','GASTO','RETIRO_PERSONAL','CAJA_A_RESERVA','RESERVA_A_CAJA','COMPRA','PAGO_PROVEEDOR')),
  monto numeric(12,2) NOT NULL CHECK(monto>=0 AND monto<=9999999999.99),
  reserva_delta numeric(12,2) NOT NULL,
  caja_delta numeric(12,2) NOT NULL DEFAULT 0,
  fecha_caja date REFERENCES public.caja_dias(fecha),
  saldo_posterior numeric(12,2) NOT NULL CHECK(saldo_posterior>=0),
  compra_id integer UNIQUE REFERENCES public.compras(id_compra),
  pago_id integer UNIQUE REFERENCES public.pagos_cuentas_por_pagar(id_pago_cuenta_por_pagar),
  concepto text NOT NULL CHECK(length(trim(concepto)) BETWEEN 1 AND 500),
  parametros jsonb NOT NULL,
  resultado jsonb NOT NULL DEFAULT '{}'::jsonb,
  CHECK((tipo='COMPRA' AND compra_id IS NOT NULL AND pago_id IS NULL AND solicitud_id IS NULL) OR
    (tipo='PAGO_PROVEEDOR' AND pago_id IS NOT NULL AND compra_id IS NULL AND solicitud_id IS NULL) OR
    (tipo NOT IN ('COMPRA','PAGO_PROVEEDOR') AND solicitud_id IS NOT NULL AND compra_id IS NULL AND pago_id IS NULL)),
  CHECK((tipo='CAJA_A_RESERVA' AND monto>0 AND reserva_delta=monto AND caja_delta=-monto AND fecha_caja IS NOT NULL) OR
    (tipo='RESERVA_A_CAJA' AND monto>0 AND reserva_delta=-monto AND caja_delta=monto AND fecha_caja IS NOT NULL) OR
    (tipo IN ('INICIAL','APORTE') AND reserva_delta=monto AND caja_delta=0 AND fecha_caja IS NULL) OR
    (tipo IN ('GASTO','RETIRO_PERSONAL','COMPRA','PAGO_PROVEEDOR') AND reserva_delta=-monto AND caja_delta=0 AND fecha_caja IS NULL)),
  CHECK(tipo IN ('INICIAL','COMPRA') OR monto>0)
);
CREATE INDEX reserva_eventos_usuario_idx ON public.reserva_eventos(usuario_id);
CREATE INDEX reserva_eventos_caja_idx ON public.reserva_eventos(fecha_caja);
CREATE INDEX reserva_eventos_fecha_idx ON public.reserva_eventos(fecha DESC,id_evento DESC);
ALTER TABLE public.reserva_saldo ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reserva_eventos ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.reserva_saldo,public.reserva_eventos FROM anon,authenticated;
GRANT SELECT ON public.reserva_saldo,public.reserva_eventos TO authenticated;
CREATE POLICY reserva_saldo_admin ON public.reserva_saldo FOR SELECT TO authenticated USING(public.fn_tiene_rol(ARRAY['ADMINISTRADOR']));
CREATE POLICY reserva_eventos_admin ON public.reserva_eventos FOR SELECT TO authenticated USING(public.fn_tiene_rol(ARRAY['ADMINISTRADOR']));

-- Solo las funciones privadas de este módulo pueden asentar el libro de Reserva.
CREATE OR REPLACE FUNCTION tienda_privada.asentar_reserva(p_tipo text,p_monto numeric,p_concepto text,p_solicitud uuid DEFAULT NULL,p_params jsonb DEFAULT '{}'::jsonb,p_compra integer DEFAULT NULL,p_pago integer DEFAULT NULL,p_fecha_caja date DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_s public.reserva_saldo%ROWTYPE;v_delta numeric;v_caja numeric:=0;v_nuevo numeric;v_id bigint;v_r jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT public.fn_tiene_rol(ARRAY['ADMINISTRADOR']) THEN RAISE EXCEPTION 'Solo el administrador puede operar Reserva.' USING ERRCODE='42501'; END IF;
  IF p_monto IS NULL OR p_monto<0 OR p_monto>9999999999.99 OR p_monto<>trunc(p_monto,2) OR p_concepto IS NULL OR length(trim(p_concepto)) NOT BETWEEN 1 AND 500 THEN RAISE EXCEPTION 'Revisa el monto y concepto.' USING ERRCODE='22023';END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('efectivo-fondos',0));
  SELECT * INTO STRICT v_s FROM public.reserva_saldo WHERE id FOR UPDATE;
  IF p_tipo='INICIAL' THEN
    IF v_s.inicializada THEN RAISE EXCEPTION 'La reserva ya tiene saldo inicial. Usa un aporte o traslado según el origen real del dinero.' USING ERRCODE='22023';END IF;
  ELSIF NOT v_s.inicializada THEN RAISE EXCEPTION 'Primero registra el saldo inicial de Reserva, incluso si es cero.' USING ERRCODE='22023';END IF;
  v_delta:=CASE WHEN p_tipo IN ('INICIAL','APORTE','CAJA_A_RESERVA') THEN p_monto ELSE -p_monto END;
  IF p_tipo='CAJA_A_RESERVA' THEN v_caja:=-p_monto;ELSIF p_tipo='RESERVA_A_CAJA' THEN v_caja:=p_monto;END IF;
  v_nuevo:=v_s.saldo+v_delta;
  IF v_nuevo<0 OR v_nuevo>9999999999.99 THEN RAISE EXCEPTION 'Saldo insuficiente en Reserva o máximo excedido. Disponible: Q %.',v_s.saldo USING ERRCODE='22023';END IF;
  UPDATE public.reserva_saldo SET saldo=v_nuevo,inicializada=true WHERE id;
  INSERT INTO public.reserva_eventos(usuario_id,solicitud_id,tipo,monto,reserva_delta,caja_delta,fecha_caja,saldo_posterior,compra_id,pago_id,concepto,parametros)
    VALUES(auth.uid(),p_solicitud,p_tipo,p_monto,v_delta,v_caja,p_fecha_caja,v_nuevo,p_compra,p_pago,trim(p_concepto),p_params) RETURNING id_evento INTO v_id;
  v_r:=jsonb_build_object('id_evento',v_id,'tipo',p_tipo,'monto',p_monto,'saldo_posterior',v_nuevo,'repetida',false);
  UPDATE public.reserva_eventos SET resultado=v_r WHERE id_evento=v_id;RETURN v_r;
END;
$fn$;
REVOKE ALL ON FUNCTION tienda_privada.asentar_reserva(text,numeric,text,uuid,jsonb,integer,integer,date) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION tienda_privada.operar_reserva(p_solicitud_id uuid,p_tipo text,p_monto numeric,p_concepto text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_prev public.reserva_eventos%ROWTYPE;v_params jsonb;v_hoy date:=(CURRENT_TIMESTAMP AT TIME ZONE 'America/Guatemala')::date;v_fecha date;v_caja jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT public.fn_tiene_rol(ARRAY['ADMINISTRADOR']) THEN RAISE EXCEPTION 'Solo el administrador puede operar Reserva.' USING ERRCODE='42501';END IF;
  IF p_solicitud_id IS NULL OR p_tipo IS NULL OR p_tipo NOT IN ('INICIAL','APORTE','GASTO','RETIRO_PERSONAL','CAJA_A_RESERVA','RESERVA_A_CAJA') OR p_monto IS NULL OR p_monto<0 OR (p_tipo<>'INICIAL' AND p_monto=0) OR p_monto>9999999999.99 OR p_monto<>trunc(p_monto,2) OR p_concepto IS NULL OR length(trim(p_concepto)) NOT BETWEEN 1 AND 500 THEN RAISE EXCEPTION 'Revisa operación, monto y concepto.' USING ERRCODE='22023';END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('efectivo-fondos',0));
  v_params:=jsonb_build_object('tipo',p_tipo,'monto',p_monto,'concepto',trim(p_concepto));
  SELECT * INTO v_prev FROM public.reserva_eventos WHERE solicitud_id=p_solicitud_id;
  IF FOUND THEN
    IF v_prev.usuario_id<>auth.uid() OR v_prev.parametros<>v_params THEN RAISE EXCEPTION 'La referencia ya corresponde a otro movimiento.' USING ERRCODE='22023';END IF;
    RETURN v_prev.resultado||jsonb_build_object('repetida',true);
  END IF;
  IF p_tipo IN ('CAJA_A_RESERVA','RESERVA_A_CAJA') THEN
    v_fecha:=v_hoy;
    PERFORM pg_advisory_xact_lock(hashtextextended('caja-dia:'||v_hoy::text,0));
    IF NOT EXISTS(SELECT 1 FROM public.caja_dias WHERE fecha=v_hoy AND estado='ABIERTA') THEN RAISE EXCEPTION 'Abre la caja de hoy antes de trasladar efectivo.' USING ERRCODE='22023';END IF;
    v_caja:=public.obtener_caja_dia(v_hoy);
    IF (v_caja->'automatico'->>'inconsistencias_total')::integer>0 THEN RAISE EXCEPTION 'Revisa las inconsistencias de Caja antes de trasladar.' USING ERRCODE='22023';END IF;
    IF p_tipo='CAJA_A_RESERVA' AND (v_caja->>'saldo_esperado')::numeric<p_monto THEN RAISE EXCEPTION 'No hay suficiente efectivo esperado en Caja para ese traslado.' USING ERRCODE='22023';END IF;
  END IF;
  RETURN tienda_privada.asentar_reserva(p_tipo,p_monto,p_concepto,p_solicitud_id,v_params,NULL,NULL,v_fecha);
END;
$fn$;
REVOKE ALL ON FUNCTION tienda_privada.operar_reserva(uuid,text,numeric,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION tienda_privada.operar_reserva(uuid,text,numeric,text) TO authenticated;
CREATE OR REPLACE FUNCTION public.operar_reserva(p_solicitud_id uuid,p_tipo text,p_monto numeric,p_concepto text)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $fn$
 SELECT tienda_privada.operar_reserva(p_solicitud_id,p_tipo,p_monto,p_concepto);
$fn$;
REVOKE ALL ON FUNCTION public.operar_reserva(uuid,text,numeric,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.operar_reserva(uuid,text,numeric,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.obtener_reserva(p_pagina integer DEFAULT 0)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path='' AS $fn$
DECLARE v_r jsonb;
BEGIN
 IF auth.uid() IS NULL OR NOT public.fn_tiene_rol(ARRAY['ADMINISTRADOR']) THEN RAISE EXCEPTION 'Solo el administrador puede consultar Reserva.' USING ERRCODE='42501';END IF;
 IF p_pagina IS NULL OR p_pagina<0 OR p_pagina>1000000 THEN RAISE EXCEPTION 'Página inválida.' USING ERRCODE='22023';END IF;
 SELECT jsonb_build_object('saldo',s.saldo,'inicializada',s.inicializada,'fecha',(CURRENT_TIMESTAMP AT TIME ZONE 'America/Guatemala')::date,
  'total',(SELECT count(*) FROM public.reserva_eventos),'saldo_libro',(SELECT coalesce(sum(reserva_delta),0) FROM public.reserva_eventos),
  'movimientos',coalesce((SELECT jsonb_agg(to_jsonb(e) ORDER BY e.fecha DESC,e.id_evento DESC) FROM (
    SELECT id_evento,fecha,tipo,monto,reserva_delta,caja_delta,fecha_caja,saldo_posterior,compra_id,pago_id,concepto
    FROM public.reserva_eventos ORDER BY fecha DESC,id_evento DESC LIMIT 20 OFFSET p_pagina*20)e),'[]'::jsonb)) INTO v_r FROM public.reserva_saldo s WHERE id;
 RETURN v_r;
END;
$fn$;
REVOKE ALL ON FUNCTION public.obtener_reserva(integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.obtener_reserva(integer) TO authenticated;

CREATE OR REPLACE FUNCTION tienda_privada.proteger_documento_reserva()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_bloqueado boolean;
BEGIN
 IF TG_OP='UPDATE' AND NEW.fondo_efectivo IS DISTINCT FROM OLD.fondo_efectivo THEN RAISE EXCEPTION 'El fondo del pago no se sobrescribe.' USING ERRCODE='22023';END IF;
 IF TG_TABLE_NAME='compras' THEN
  SELECT EXISTS(SELECT 1 FROM public.reserva_eventos WHERE compra_id=OLD.id_compra) OR EXISTS(SELECT 1 FROM public.reserva_eventos e JOIN public.pagos_cuentas_por_pagar p ON p.id_pago_cuenta_por_pagar=e.pago_id JOIN public.cuentas_por_pagar c ON c.id_cuenta_por_pagar=p.cuenta_por_pagar_id WHERE c.compra_id=OLD.id_compra) INTO v_bloqueado;
 ELSE SELECT EXISTS(SELECT 1 FROM public.reserva_eventos WHERE pago_id=OLD.id_pago_cuenta_por_pagar) INTO v_bloqueado;END IF;
 IF v_bloqueado THEN RAISE EXCEPTION 'El documento tiene un pago asentado en Reserva. Conserva el historial; no sobrescribas ni elimines el pago.' USING ERRCODE='22023';END IF;
 IF TG_OP='DELETE' THEN RETURN OLD;ELSE RETURN NEW;END IF;
END;
$fn$;
REVOKE ALL ON FUNCTION tienda_privada.proteger_documento_reserva() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER proteger_compra_reserva BEFORE UPDATE OR DELETE ON public.compras FOR EACH ROW EXECUTE FUNCTION tienda_privada.proteger_documento_reserva();
CREATE TRIGGER proteger_pago_reserva BEFORE UPDATE OR DELETE ON public.pagos_cuentas_por_pagar FOR EACH ROW EXECUTE FUNCTION tienda_privada.proteger_documento_reserva();

-- Definiciones compatibles con el fondo de origen y un orden de bloqueo común.

CREATE OR REPLACE FUNCTION tienda_privada.registrar_compra_fondo(p_proveedor_id integer, p_forma_pago_id integer, p_numero_documento character varying, p_items jsonb, p_fecha_limite date DEFAULT NULL::date, p_fondo text DEFAULT 'CAJA')
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET "TimeZone" TO 'America/Guatemala'
AS $function$
DECLARE
  v_usuario uuid := auth.uid();
  v_documento varchar := nullif(btrim(p_numero_documento), '');
  v_pago text;
  v_tipo integer;
  v_compra integer;
  v_detalle integer;
  v_lote_id integer;
  v_item jsonb;
  v_lote jsonb;
  v_producto public.productos%ROWTYPE;
  v_cantidad integer;
  v_costo numeric(12,2);
  v_total numeric(12,2) := 0;
  v_suma_lotes bigint;
  v_cantidad_lote integer;
  v_fecha date;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('efectivo-fondos',0));
  IF v_usuario IS NULL OR NOT public.fn_tiene_rol(ARRAY['ADMINISTRADOR','INVENTARIO']::text[]) THEN
    RAISE EXCEPTION 'No tienes permiso para registrar compras' USING ERRCODE = '42501';
  END IF;
  IF v_documento IS NULL OR length(v_documento) > 100 THEN
    RAISE EXCEPTION 'Indica un documento o referencia de hasta 100 caracteres' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.proveedores WHERE id_proveedor=p_proveedor_id) THEN
    RAISE EXCEPTION 'Selecciona un proveedor válido' USING ERRCODE = '22023';
  END IF;
  SELECT nombre INTO v_pago FROM public.formas_pago WHERE id_forma_pago=p_forma_pago_id;
  IF v_pago IS NULL THEN
    RAISE EXCEPTION 'Selecciona una forma de pago válida' USING ERRCODE = '22023';
  END IF;
  IF p_fondo IS NULL OR p_fondo NOT IN ('CAJA','RESERVA') OR (p_fondo='RESERVA' AND v_pago<>'EFECTIVO') THEN
    RAISE EXCEPTION 'Reserva solo se usa con pagos en efectivo.' USING ERRCODE='22023';
  END IF;
  IF p_fondo='RESERVA' AND NOT public.fn_tiene_rol(ARRAY['ADMINISTRADOR']) THEN RAISE EXCEPTION 'Solo el administrador puede usar Reserva.' USING ERRCODE='42501'; END IF;
  IF v_pago <> 'CREDITO' AND p_fecha_limite IS NOT NULL THEN
    RAISE EXCEPTION 'Solo una compra a crédito puede tener fecha límite' USING ERRCODE = '22023';
  END IF;
  IF p_fecha_limite < CURRENT_DATE THEN
    RAISE EXCEPTION 'La fecha límite no puede ser anterior a hoy' USING ERRCODE = '22023';
  END IF;
  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' THEN
    RAISE EXCEPTION 'La compra debe contener una lista de productos' USING ERRCODE = '22023';
  END IF;
  IF jsonb_array_length(p_items)=0 THEN
    RAISE EXCEPTION 'Agrega al menos un producto' USING ERRCODE = '22023';
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_items) x WHERE jsonb_typeof(x) <> 'object' OR x->>'producto_id' IS NULL) THEN
    RAISE EXCEPTION 'Cada línea debe indicar un producto' USING ERRCODE = '22023';
  END IF;
  IF (SELECT count(*) FROM jsonb_array_elements(p_items)) <>
     (SELECT count(DISTINCT (x->>'producto_id')::integer) FROM jsonb_array_elements(p_items) x) THEN
    RAISE EXCEPTION 'Un producto no puede aparecer dos veces en la misma compra' USING ERRCODE = '22023';
  END IF;
  SELECT id_tipo_movimiento INTO v_tipo FROM public.tipos_movimientos WHERE nombre='COMPRA' AND factor=1;
  IF v_tipo IS NULL THEN
    RAISE EXCEPTION 'Falta configurar el tipo de movimiento COMPRA';
  END IF;
  INSERT INTO public.compras(proveedor_id,usuario_id,forma_pago_id,numero_documento,total,fondo_efectivo)
  VALUES(p_proveedor_id,v_usuario,p_forma_pago_id,v_documento,0,p_fondo) RETURNING id_compra INTO v_compra;

  -- Se bloquean en un orden estable para reducir interbloqueos entre compras.
  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) ORDER BY (value->>'producto_id')::integer LOOP
    IF (v_item->>'cantidad') IS NULL OR (v_item->>'cantidad') !~ '^[0-9]+$' THEN
      RAISE EXCEPTION 'La cantidad debe ser un entero positivo' USING ERRCODE = '22023';
    END IF;
    v_cantidad := (v_item->>'cantidad')::integer;
    IF v_cantidad <= 0 THEN
      RAISE EXCEPTION 'La cantidad debe ser mayor que cero' USING ERRCODE = '22023';
    END IF;
    IF (v_item->>'costo_unitario') IS NULL OR (v_item->>'costo_unitario') !~ '^[0-9]+(\.[0-9]{1,2})?$' THEN
      RAISE EXCEPTION 'El costo debe ser positivo o cero, con hasta dos decimales' USING ERRCODE = '22023';
    END IF;
    v_costo := (v_item->>'costo_unitario')::numeric(12,2);
    SELECT * INTO v_producto FROM public.productos WHERE id_producto=(v_item->>'producto_id')::integer FOR UPDATE;
    IF NOT FOUND OR NOT v_producto.activo THEN
      RAISE EXCEPTION 'El producto no existe o está inactivo' USING ERRCODE = '22023';
    END IF;
    INSERT INTO public.detalle_compras(compra_id,producto_id,cantidad,costo_unitario)
    VALUES(v_compra,v_producto.id_producto,v_cantidad,v_costo) RETURNING id_detalle_compra INTO v_detalle;
    v_total := v_total + v_cantidad*v_costo;

    IF v_producto.controla_lotes THEN
      IF v_item->'lotes' IS NULL OR jsonb_typeof(v_item->'lotes') <> 'array' THEN
        RAISE EXCEPTION 'Este producto requiere información de lotes' USING ERRCODE = '22023';
      END IF;
      IF jsonb_array_length(v_item->'lotes')=0 THEN
        RAISE EXCEPTION 'Agrega al menos un lote' USING ERRCODE = '22023';
      END IF;
      v_suma_lotes := 0;
      FOR v_lote IN SELECT value FROM jsonb_array_elements(v_item->'lotes') LOOP
        IF jsonb_typeof(v_lote) <> 'object' OR v_lote->>'cantidad' IS NULL OR (v_lote->>'cantidad') !~ '^[0-9]+$' THEN
          RAISE EXCEPTION 'Cada lote debe indicar una cantidad entera positiva' USING ERRCODE = '22023';
        END IF;
        v_cantidad_lote := (v_lote->>'cantidad')::integer;
        IF v_cantidad_lote <= 0 THEN
          RAISE EXCEPTION 'La cantidad del lote debe ser mayor que cero' USING ERRCODE = '22023';
        END IF;
        v_fecha := nullif(v_lote->>'fecha_vencimiento','')::date;
        IF v_fecha < CURRENT_DATE THEN
          RAISE EXCEPTION 'No se permite ingresar un lote ya vencido' USING ERRCODE = '22023';
        END IF;
        INSERT INTO public.lotes(detalle_compra_id,numero_lote,fecha_vencimiento)
        VALUES(v_detalle,nullif(btrim(v_lote->>'numero_lote'),''),v_fecha) RETURNING id_lote INTO v_lote_id;
        INSERT INTO public.movimientos_inventario(producto_id,lote_id,tipo_movimiento_id,detalle_compra_id,cantidad,usuario_id,observacion)
        VALUES(v_producto.id_producto,v_lote_id,v_tipo,v_detalle,v_cantidad_lote,v_usuario,'Compra');
        v_suma_lotes := v_suma_lotes + v_cantidad_lote;
      END LOOP;
      IF v_suma_lotes <> v_cantidad THEN
        RAISE EXCEPTION 'La suma de los lotes debe coincidir con la cantidad comprada' USING ERRCODE = '22023';
      END IF;
    ELSE
      IF v_item ? 'lotes' AND v_item->'lotes' <> '[]'::jsonb THEN
        RAISE EXCEPTION 'Este producto no utiliza lotes' USING ERRCODE = '22023';
      END IF;
      INSERT INTO public.movimientos_inventario(producto_id,tipo_movimiento_id,detalle_compra_id,cantidad,usuario_id,observacion)
      VALUES(v_producto.id_producto,v_tipo,v_detalle,v_cantidad,v_usuario,'Compra');
    END IF;
  END LOOP;
  UPDATE public.compras SET total=v_total WHERE id_compra=v_compra;
  IF v_pago='CREDITO' THEN
    IF v_total=0 THEN
      RAISE EXCEPTION 'Una compra a crédito debe tener un total mayor que cero' USING ERRCODE = '22023';
    END IF;
    INSERT INTO public.cuentas_por_pagar(compra_id,monto_original,saldo_pendiente,fecha_limite)
    VALUES(v_compra,v_total,v_total,p_fecha_limite);
  END IF;
  IF p_fondo='RESERVA' THEN PERFORM tienda_privada.asentar_reserva('COMPRA',v_total,'Compra #'||v_compra,NULL,'{}',v_compra); END IF;
  RETURN jsonb_build_object('fondo_efectivo',p_fondo,'id_compra',v_compra,'total',v_total,'estado','REGISTRADA');
END;
$function$;


REVOKE ALL ON FUNCTION tienda_privada.registrar_compra_fondo(integer,integer,varchar,jsonb,date,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION tienda_privada.registrar_compra_fondo(integer,integer,varchar,jsonb,date,text) TO authenticated;
CREATE OR REPLACE FUNCTION public.registrar_compra_fondo(p_proveedor_id integer,p_forma_pago_id integer,p_numero_documento varchar,p_items jsonb,p_fecha_limite date,p_fondo text)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tienda_privada.registrar_compra_fondo(p_proveedor_id,p_forma_pago_id,p_numero_documento,p_items,p_fecha_limite,p_fondo); $$;
REVOKE ALL ON FUNCTION public.registrar_compra_fondo(integer,integer,varchar,jsonb,date,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.registrar_compra_fondo(integer,integer,varchar,jsonb,date,text) TO authenticated;
CREATE OR REPLACE FUNCTION public.registrar_compra(p_proveedor_id integer,p_forma_pago_id integer,p_numero_documento varchar,p_items jsonb,p_fecha_limite date DEFAULT NULL)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tienda_privada.registrar_compra_fondo(p_proveedor_id,p_forma_pago_id,p_numero_documento,p_items,p_fecha_limite,'CAJA'); $$;

CREATE OR REPLACE FUNCTION tienda_privada.registrar_abono_cxp_fondo(p_solicitud_id uuid, p_cuenta_id integer, p_forma_pago_id integer, p_monto numeric,p_fondo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET "TimeZone" TO 'America/Guatemala'
AS $function$
DECLARE
  v_usuario uuid := auth.uid();
  v_anterior public.pagos_cuentas_por_pagar%ROWTYPE;
  v_cuenta public.cuentas_por_pagar%ROWTYPE;
  v_compra integer;
  v_proveedor integer;
  v_pago integer;
  v_saldo numeric;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('efectivo-fondos',0));
  IF v_usuario IS NULL OR NOT public.fn_tiene_rol(ARRAY['ADMINISTRADOR','INVENTARIO']) THEN
    RAISE EXCEPTION 'No tienes permiso para registrar abonos.' USING ERRCODE='42501';
  END IF;
  IF p_solicitud_id IS NULL OR p_cuenta_id IS NULL OR p_forma_pago_id IS NULL
     OR p_monto IS NULL OR p_monto <= 0 OR p_monto > 9999999999.99
     OR p_monto <> trunc(p_monto,2) THEN
    RAISE EXCEPTION 'Indica una cuenta, una forma de pago y un monto mayor que cero con hasta dos decimales.' USING ERRCODE='22023';
  END IF;
  IF p_fondo IS NULL OR p_fondo NOT IN ('CAJA','RESERVA') OR (p_fondo='RESERVA' AND NOT EXISTS(SELECT 1 FROM public.formas_pago WHERE id_forma_pago=p_forma_pago_id AND nombre='EFECTIVO')) THEN RAISE EXCEPTION 'Reserva solo se usa con pagos en efectivo.' USING ERRCODE='22023'; END IF;
  IF p_fondo='RESERVA' AND NOT public.fn_tiene_rol(ARRAY['ADMINISTRADOR']) THEN RAISE EXCEPTION 'Solo el administrador puede usar Reserva.' USING ERRCODE='42501'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('abono-cxp:' || p_solicitud_id::text,0));
  SELECT * INTO v_anterior FROM public.pagos_cuentas_por_pagar WHERE solicitud_id=p_solicitud_id;
  IF FOUND THEN
    IF v_anterior.usuario_id<>v_usuario OR v_anterior.cuenta_por_pagar_id<>p_cuenta_id
       OR v_anterior.forma_pago_id<>p_forma_pago_id OR v_anterior.monto<>p_monto OR v_anterior.fondo_efectivo<>p_fondo THEN
      RAISE EXCEPTION 'Esta referencia ya corresponde a otro abono.' USING ERRCODE='22023';
    END IF;
    SELECT saldo_pendiente INTO v_saldo FROM public.cuentas_por_pagar WHERE id_cuenta_por_pagar=p_cuenta_id;
    RETURN jsonb_build_object('fondo_efectivo',p_fondo,'id_pago',v_anterior.id_pago_cuenta_por_pagar,'cuenta_id',p_cuenta_id,
      'monto',v_anterior.monto,'saldo_pendiente',v_saldo,'repetida',true);
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.formas_pago WHERE id_forma_pago=p_forma_pago_id AND nombre<>'CREDITO') THEN
    RAISE EXCEPTION 'Selecciona una forma de pago distinta de crédito.' USING ERRCODE='22023';
  END IF;
  SELECT v.id_compra,v.proveedor_id INTO v_compra,v_proveedor
  FROM public.compras v JOIN public.cuentas_por_pagar c ON c.compra_id=v.id_compra
  JOIN public.formas_pago fp ON fp.id_forma_pago=v.forma_pago_id
  WHERE c.id_cuenta_por_pagar=p_cuenta_id AND v.estado='REGISTRADA' AND fp.nombre='CREDITO'
  FOR UPDATE OF v;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'La cuenta no existe o su compra ya no está registrada a crédito.' USING ERRCODE='22023';
  END IF;
  -- Serializa las operaciones de crédito del mismo proveedor con los triggers existentes.
  PERFORM 1 FROM public.proveedores WHERE id_proveedor=v_proveedor FOR UPDATE;
  SELECT * INTO STRICT v_cuenta FROM public.cuentas_por_pagar WHERE id_cuenta_por_pagar=p_cuenta_id FOR UPDATE;
  IF NOT EXISTS(SELECT 1 FROM public.detalle_compras WHERE compra_id=v_compra)
     OR (SELECT coalesce(sum(subtotal),0) FROM public.detalle_compras WHERE compra_id=v_compra)
        <> (SELECT total FROM public.compras WHERE id_compra=v_compra)
     OR v_cuenta.monto_original<>(SELECT total FROM public.compras WHERE id_compra=v_compra)
     OR v_cuenta.saldo_pendiente<>v_cuenta.monto_original-
        (SELECT coalesce(sum(monto),0) FROM public.pagos_cuentas_por_pagar WHERE cuenta_por_pagar_id=p_cuenta_id) THEN
    RAISE EXCEPTION 'La cuenta tiene registros inconsistentes. Revísala antes de pagar.' USING ERRCODE='22023';
  END IF;
  IF p_monto>v_cuenta.saldo_pendiente THEN
    RAISE EXCEPTION 'El abono supera el saldo actual de Q %.',v_cuenta.saldo_pendiente USING ERRCODE='22023';
  END IF;
  INSERT INTO public.pagos_cuentas_por_pagar(cuenta_por_pagar_id,usuario_id,forma_pago_id,monto,solicitud_id,fondo_efectivo)
  VALUES(p_cuenta_id,v_usuario,p_forma_pago_id,p_monto,p_solicitud_id,p_fondo)
  RETURNING id_pago_cuenta_por_pagar INTO v_pago;
  IF p_fondo='RESERVA' THEN PERFORM tienda_privada.asentar_reserva('PAGO_PROVEEDOR',p_monto,'Pago a proveedor #'||v_pago,NULL,'{}',NULL,v_pago); END IF;
  -- Los triggers existentes validan y recalculan el saldo dentro de esta transacción.
  SELECT saldo_pendiente INTO v_saldo FROM public.cuentas_por_pagar WHERE id_cuenta_por_pagar=p_cuenta_id;
  RETURN jsonb_build_object('fondo_efectivo',p_fondo,'id_pago',v_pago,'cuenta_id',p_cuenta_id,'monto',p_monto,
    'saldo_pendiente',v_saldo,'repetida',false);
END;
$function$;


REVOKE ALL ON FUNCTION tienda_privada.registrar_abono_cxp_fondo(uuid,integer,integer,numeric,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION tienda_privada.registrar_abono_cxp_fondo(uuid,integer,integer,numeric,text) TO authenticated;
CREATE OR REPLACE FUNCTION public.registrar_abono_cxp_fondo(p_solicitud_id uuid,p_cuenta_id integer,p_forma_pago_id integer,p_monto numeric,p_fondo text)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tienda_privada.registrar_abono_cxp_fondo(p_solicitud_id,p_cuenta_id,p_forma_pago_id,p_monto,p_fondo); $$;
REVOKE ALL ON FUNCTION public.registrar_abono_cxp_fondo(uuid,integer,integer,numeric,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.registrar_abono_cxp_fondo(uuid,integer,integer,numeric,text) TO authenticated;
CREATE OR REPLACE FUNCTION tienda_privada.registrar_abono_cxp(p_solicitud_id uuid,p_cuenta_id integer,p_forma_pago_id integer,p_monto numeric)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tienda_privada.registrar_abono_cxp_fondo(p_solicitud_id,p_cuenta_id,p_forma_pago_id,p_monto,'CAJA'); $$;

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

CREATE OR REPLACE FUNCTION tienda_privada.registrar_abono_cxc(p_solicitud_id uuid, p_cuenta_id integer, p_forma_pago_id integer, p_monto numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET "TimeZone" TO 'America/Guatemala'
AS $function$
DECLARE
  v_usuario uuid := auth.uid();
  v_anterior public.pagos_cuentas_por_cobrar%ROWTYPE;
  v_cuenta public.cuentas_por_cobrar%ROWTYPE;
  v_venta integer;
  v_cliente integer;
  v_pago integer;
  v_saldo numeric;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('efectivo-fondos',0));
  IF v_usuario IS NULL OR NOT public.fn_tiene_rol(ARRAY['ADMINISTRADOR','CAJERO']) THEN
    RAISE EXCEPTION 'No tienes permiso para registrar abonos.' USING ERRCODE='42501';
  END IF;
  IF p_solicitud_id IS NULL OR p_cuenta_id IS NULL OR p_forma_pago_id IS NULL
     OR p_monto IS NULL OR p_monto <= 0 OR p_monto > 9999999999.99
     OR p_monto <> trunc(p_monto,2) THEN
    RAISE EXCEPTION 'Indica una cuenta, una forma de pago y un monto mayor que cero con hasta dos decimales.' USING ERRCODE='22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('abono-cxc:' || p_solicitud_id::text,0));
  SELECT * INTO v_anterior FROM public.pagos_cuentas_por_cobrar WHERE solicitud_id=p_solicitud_id;
  IF FOUND THEN
    IF v_anterior.usuario_id<>v_usuario OR v_anterior.cuenta_por_cobrar_id<>p_cuenta_id
       OR v_anterior.forma_pago_id<>p_forma_pago_id OR v_anterior.monto<>p_monto THEN
      RAISE EXCEPTION 'Esta referencia ya corresponde a otro abono.' USING ERRCODE='22023';
    END IF;
    SELECT saldo_pendiente INTO v_saldo FROM public.cuentas_por_cobrar WHERE id_cuenta_por_cobrar=p_cuenta_id;
    RETURN jsonb_build_object('id_pago',v_anterior.id_pago_cuenta_por_cobrar,'cuenta_id',p_cuenta_id,
      'monto',v_anterior.monto,'saldo_pendiente',v_saldo,'repetida',true);
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.formas_pago WHERE id_forma_pago=p_forma_pago_id AND nombre<>'CREDITO') THEN
    RAISE EXCEPTION 'Selecciona una forma de pago distinta de crédito.' USING ERRCODE='22023';
  END IF;
  SELECT v.id_venta,v.cliente_id INTO v_venta,v_cliente
  FROM public.ventas v JOIN public.cuentas_por_cobrar c ON c.venta_id=v.id_venta
  JOIN public.formas_pago fp ON fp.id_forma_pago=v.forma_pago_id
  WHERE c.id_cuenta_por_cobrar=p_cuenta_id AND v.estado='REGISTRADA' AND fp.nombre='CREDITO'
  FOR UPDATE OF v;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'La cuenta no existe o su venta ya no está registrada a crédito.' USING ERRCODE='22023';
  END IF;
  -- Serializa las operaciones de crédito del mismo cliente con los triggers existentes.
  PERFORM 1 FROM public.clientes WHERE id_cliente=v_cliente FOR UPDATE;
  SELECT * INTO STRICT v_cuenta FROM public.cuentas_por_cobrar WHERE id_cuenta_por_cobrar=p_cuenta_id FOR UPDATE;
  IF NOT EXISTS(SELECT 1 FROM public.detalle_ventas WHERE venta_id=v_venta)
     OR (SELECT coalesce(sum(subtotal),0) FROM public.detalle_ventas WHERE venta_id=v_venta)
        <> (SELECT total FROM public.ventas WHERE id_venta=v_venta)
     OR v_cuenta.monto_original<>(SELECT total FROM public.ventas WHERE id_venta=v_venta)
     OR v_cuenta.saldo_pendiente<>v_cuenta.monto_original-
        (SELECT coalesce(sum(monto),0) FROM public.pagos_cuentas_por_cobrar WHERE cuenta_por_cobrar_id=p_cuenta_id) THEN
    RAISE EXCEPTION 'La cuenta tiene registros inconsistentes. Revísala antes de cobrar.' USING ERRCODE='22023';
  END IF;
  IF p_monto>v_cuenta.saldo_pendiente THEN
    RAISE EXCEPTION 'El abono supera el saldo actual de Q %.',v_cuenta.saldo_pendiente USING ERRCODE='22023';
  END IF;
  INSERT INTO public.pagos_cuentas_por_cobrar(cuenta_por_cobrar_id,usuario_id,forma_pago_id,monto,solicitud_id)
  VALUES(p_cuenta_id,v_usuario,p_forma_pago_id,p_monto,p_solicitud_id)
  RETURNING id_pago_cuenta_por_cobrar INTO v_pago;
  -- Los triggers existentes validan y recalculan el saldo dentro de esta transacción.
  SELECT saldo_pendiente INTO v_saldo FROM public.cuentas_por_cobrar WHERE id_cuenta_por_cobrar=p_cuenta_id;
  RETURN jsonb_build_object('id_pago',v_pago,'cuenta_id',p_cuenta_id,'monto',p_monto,
    'saldo_pendiente',v_saldo,'repetida',false);
END;
$function$;

CREATE OR REPLACE FUNCTION tienda_privada.operar_caja(p_solicitud_id uuid, p_fecha date, p_tipo text, p_monto numeric, p_concepto text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET "TimeZone" TO 'America/Guatemala'
AS $function$
DECLARE
  v_usuario uuid:=auth.uid(); v_params jsonb; v_anterior public.caja_eventos%ROWTYPE;
  v_dia public.caja_dias%ROWTYPE; v_resumen jsonb; v_datos jsonb:='{}'::jsonb;
  v_concepto text:=trim(coalesce(p_concepto,'')); v_id bigint; v_resultado jsonb;
  v_hoy date:=(CURRENT_TIMESTAMP AT TIME ZONE 'America/Guatemala')::date; v_diferencia numeric;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('efectivo-fondos',0));
  IF v_usuario IS NULL OR NOT public.fn_tiene_rol(ARRAY['ADMINISTRADOR']) THEN
    RAISE EXCEPTION 'Solo el administrador puede operar caja.' USING ERRCODE='42501';
  END IF;
  IF p_solicitud_id IS NULL OR p_fecha IS NULL OR p_fecha<'1900-01-01'::date OR p_fecha>v_hoy
     OR p_tipo IS NULL OR p_tipo NOT IN ('APERTURA','AJUSTE_FONDO','GASTO','RETIRO_PERSONAL','APORTE','CIERRE','REAPERTURA')
     OR length(v_concepto)>500 THEN
    RAISE EXCEPTION 'Revisa la fecha, el tipo y el concepto de la operación.' USING ERRCODE='22023';
  END IF;
  IF p_tipo='REAPERTURA' THEN
    IF p_monto IS NOT NULL OR v_concepto='' THEN
      RAISE EXCEPTION 'La reapertura requiere un motivo y no lleva monto.' USING ERRCODE='22023';
    END IF;
  ELSE
    IF p_monto IS NULL OR p_monto<0 OR p_monto>9999999999.99 OR p_monto<>trunc(p_monto,2)
       OR (p_tipo IN ('GASTO','RETIRO_PERSONAL','APORTE') AND (p_monto=0 OR v_concepto=''))
       OR (p_tipo='AJUSTE_FONDO' AND v_concepto='') THEN
      RAISE EXCEPTION 'Indica un monto válido con hasta dos decimales y el concepto cuando corresponda.' USING ERRCODE='22023';
    END IF;
  END IF;
  v_params:=jsonb_build_object('fecha',p_fecha,'tipo',p_tipo,'monto',p_monto,'concepto',v_concepto);
  PERFORM pg_advisory_xact_lock(hashtextextended('caja-solicitud:'||p_solicitud_id::text,0));
  SELECT * INTO v_anterior FROM public.caja_eventos WHERE solicitud_id=p_solicitud_id;
  IF FOUND THEN
    IF v_anterior.usuario_id<>v_usuario OR v_anterior.parametros<>v_params THEN
      RAISE EXCEPTION 'La referencia ya corresponde a otra operación de caja.' USING ERRCODE='22023';
    END IF;
    RETURN v_anterior.resultado||jsonb_build_object('repetida',true);
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('caja-dia:'||p_fecha::text,0));
  SELECT * INTO v_dia FROM public.caja_dias WHERE fecha=p_fecha FOR UPDATE;
  IF p_tipo='APERTURA' THEN
    IF FOUND THEN RAISE EXCEPTION 'Esta fecha ya tiene apertura. Consulta su estado.' USING ERRCODE='22023'; END IF;
    INSERT INTO public.caja_dias(fecha,efectivo_inicial,estado,usuario_apertura) VALUES(p_fecha,p_monto,'ABIERTA',v_usuario);
  ELSE
    IF NOT FOUND THEN RAISE EXCEPTION 'Primero registra la apertura de esa fecha.' USING ERRCODE='22023'; END IF;
    IF p_tipo='REAPERTURA' THEN
      IF v_dia.estado<>'CERRADA' THEN RAISE EXCEPTION 'La caja ya está abierta.' USING ERRCODE='22023'; END IF;
      v_datos:=jsonb_build_object('cierre_anterior',v_dia.ultimo_cierre);
      UPDATE public.caja_dias SET estado='ABIERTA' WHERE fecha=p_fecha;
    ELSE
      IF v_dia.estado<>'ABIERTA' THEN RAISE EXCEPTION 'La caja está cerrada. Reábrela con un motivo antes de operar.' USING ERRCODE='22023'; END IF;
      IF p_tipo='AJUSTE_FONDO' THEN
        v_datos:=jsonb_build_object('fondo_anterior',v_dia.efectivo_inicial,'fondo_corregido',p_monto);
        UPDATE public.caja_dias SET efectivo_inicial=p_monto WHERE fecha=p_fecha;
      ELSIF p_tipo='CIERRE' THEN
        v_resumen:=public.obtener_caja_dia(p_fecha);
        IF (v_resumen->'automatico'->>'inconsistencias_total')::integer>0 THEN
          RAISE EXCEPTION 'Hay movimientos inconsistentes en Efectivo. Revísalos antes de cerrar caja.' USING ERRCODE='22023';
        END IF;
        v_diferencia:=p_monto-(v_resumen->>'saldo_esperado')::numeric;
        IF v_diferencia<>0 AND v_concepto='' THEN
          RAISE EXCEPTION 'Hay una diferencia de caja. Escribe una observación para conservarla en el cierre.' USING ERRCODE='22023';
        END IF;
        v_datos:=jsonb_build_object('fecha',p_fecha,'fecha_cierre',CURRENT_TIMESTAMP,
          'efectivo_inicial',v_dia.efectivo_inicial,'entradas_automaticas',v_resumen->'automatico'->'entradas',
          'salidas_automaticas',v_resumen->'automatico'->'salidas','aportes',v_resumen->'aportes','gastos',v_resumen->'gastos','retiros',v_resumen->'retiros',
          'traslados_entrada',v_resumen->'traslados_entrada','traslados_salida',v_resumen->'traslados_salida','saldo_esperado',v_resumen->'saldo_esperado','efectivo_contado',p_monto,'diferencia',v_diferencia,'observacion',v_concepto);
      END IF;
    END IF;
  END IF;
  INSERT INTO public.caja_eventos(fecha_caja,usuario_id,solicitud_id,tipo,monto,concepto,parametros,datos)
  VALUES(p_fecha,v_usuario,p_solicitud_id,p_tipo,p_monto,v_concepto,v_params,v_datos) RETURNING id_evento INTO v_id;
  IF p_tipo='CIERRE' THEN
    v_datos:=v_datos||jsonb_build_object('id_evento',v_id);
    UPDATE public.caja_dias SET estado='CERRADA',ultimo_cierre=v_datos WHERE fecha=p_fecha;
    UPDATE public.caja_eventos SET datos=v_datos WHERE id_evento=v_id;
  END IF;
  v_resultado:=jsonb_build_object('id_evento',v_id,'fecha',p_fecha,'tipo',p_tipo,'monto',p_monto,'datos',v_datos,'repetida',false);
  UPDATE public.caja_eventos SET resultado=v_resultado WHERE id_evento=v_id;
  RETURN v_resultado;
END;
$function$;

CREATE OR REPLACE FUNCTION public.obtener_flujo_efectivo(p_fecha date, p_pagina integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE
  v_inicio timestamptz; v_fin timestamptz; v_resultado jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT public.fn_tiene_rol(ARRAY['ADMINISTRADOR']) THEN
    RAISE EXCEPTION 'Solo el administrador puede consultar el flujo completo de efectivo.' USING ERRCODE='42501';
  END IF;
  IF p_fecha IS NULL OR p_fecha<'1900-01-01'::date OR p_fecha>'2100-12-31'::date
     OR p_pagina IS NULL OR p_pagina<0 OR p_pagina>1000000 THEN
    RAISE EXCEPTION 'Revisa la fecha o la página seleccionada.' USING ERRCODE='22023';
  END IF;
  v_inicio:=p_fecha::timestamp AT TIME ZONE 'America/Guatemala';
  v_fin:=(p_fecha+1)::timestamp AT TIME ZONE 'America/Guatemala';
  WITH candidatos AS (
    SELECT 'VENTA'::text AS tipo,v.id_venta AS id,v.id_venta AS documento_id,v.fecha,
      coalesce(c.nombre,'Consumidor final')::text AS contraparte,
      ('Venta #'||v.id_venta)::text AS referencia,v.total AS entrada,0::numeric AS salida,
      true AS es_venta,true AS cuenta_consistente,v.total AS total_documento
    FROM public.ventas v JOIN public.formas_pago fp ON fp.id_forma_pago=v.forma_pago_id
    LEFT JOIN public.clientes c ON c.id_cliente=v.cliente_id
    WHERE v.estado='REGISTRADA' AND fp.nombre='EFECTIVO' AND v.fecha>=v_inicio AND v.fecha<v_fin
    UNION ALL
    SELECT 'COBRO_CLIENTE',p.id_pago_cuenta_por_cobrar,v.id_venta,p.fecha,coalesce(c.nombre,'Cliente'),
      'Abono #'||p.id_pago_cuenta_por_cobrar||' · Venta #'||v.id_venta,p.monto,0,true,
      fpv.nombre='CREDITO' AND cc.monto_original=v.total
        AND cc.saldo_pendiente=cc.monto_original-(SELECT coalesce(sum(pp.monto),0) FROM public.pagos_cuentas_por_cobrar pp WHERE pp.cuenta_por_cobrar_id=cc.id_cuenta_por_cobrar),
      v.total
    FROM public.pagos_cuentas_por_cobrar p JOIN public.formas_pago fp ON fp.id_forma_pago=p.forma_pago_id
    JOIN public.cuentas_por_cobrar cc ON cc.id_cuenta_por_cobrar=p.cuenta_por_cobrar_id
    JOIN public.ventas v ON v.id_venta=cc.venta_id JOIN public.formas_pago fpv ON fpv.id_forma_pago=v.forma_pago_id
    LEFT JOIN public.clientes c ON c.id_cliente=v.cliente_id
    WHERE v.estado='REGISTRADA' AND fp.nombre='EFECTIVO' AND p.monto>0 AND p.fecha>=v_inicio AND p.fecha<v_fin
    UNION ALL
    SELECT 'COMPRA',co.id_compra,co.id_compra,co.fecha,pr.nombre,
      'Compra #'||co.id_compra||coalesce(' · '||co.numero_documento,''),0,co.total,false,true,co.total
    FROM public.compras co JOIN public.formas_pago fp ON fp.id_forma_pago=co.forma_pago_id
    JOIN public.proveedores pr ON pr.id_proveedor=co.proveedor_id
    WHERE co.estado='REGISTRADA' AND fp.nombre='EFECTIVO' AND co.fondo_efectivo='CAJA' AND co.fecha>=v_inicio AND co.fecha<v_fin
    UNION ALL
    SELECT 'PAGO_PROVEEDOR',p.id_pago_cuenta_por_pagar,co.id_compra,p.fecha,pr.nombre,
      'Pago #'||p.id_pago_cuenta_por_pagar||' · Compra #'||co.id_compra,0,p.monto,false,
      fpc.nombre='CREDITO' AND cp.monto_original=co.total
        AND cp.saldo_pendiente=cp.monto_original-(SELECT coalesce(sum(pp.monto),0) FROM public.pagos_cuentas_por_pagar pp WHERE pp.cuenta_por_pagar_id=cp.id_cuenta_por_pagar),
      co.total
    FROM public.pagos_cuentas_por_pagar p JOIN public.formas_pago fp ON fp.id_forma_pago=p.forma_pago_id
    JOIN public.cuentas_por_pagar cp ON cp.id_cuenta_por_pagar=p.cuenta_por_pagar_id
    JOIN public.compras co ON co.id_compra=cp.compra_id JOIN public.formas_pago fpc ON fpc.id_forma_pago=co.forma_pago_id
    JOIN public.proveedores pr ON pr.id_proveedor=co.proveedor_id
    WHERE co.estado='REGISTRADA' AND fp.nombre='EFECTIVO' AND p.fondo_efectivo='CAJA' AND p.monto>0 AND p.fecha>=v_inicio AND p.fecha<v_fin
  ), comprobados AS (
    SELECT ca.*,ca.cuenta_consistente AND CASE WHEN ca.es_venta THEN
      EXISTS(SELECT 1 FROM public.detalle_ventas d WHERE d.venta_id=ca.documento_id)
      AND ca.total_documento=(SELECT coalesce(sum(d.subtotal),0) FROM public.detalle_ventas d WHERE d.venta_id=ca.documento_id)
      ELSE EXISTS(SELECT 1 FROM public.detalle_compras d WHERE d.compra_id=ca.documento_id)
      AND ca.total_documento=(SELECT coalesce(sum(d.subtotal),0) FROM public.detalle_compras d WHERE d.compra_id=ca.documento_id)
      END AS consistente
    FROM candidatos ca
  ), validos AS (
    SELECT tipo,id,fecha,contraparte,referencia,entrada,salida FROM comprobados WHERE consistente AND (entrada>0 OR salida>0)
  ), pagina AS (
    SELECT * FROM validos ORDER BY fecha DESC,tipo,id DESC LIMIT 20 OFFSET p_pagina*20
  ), problemas AS (
    SELECT tipo,id,referencia FROM comprobados WHERE NOT consistente ORDER BY fecha DESC,tipo,id DESC LIMIT 20
  )
  SELECT jsonb_build_object('fecha',p_fecha,'actualizado',CURRENT_TIMESTAMP,
    'entradas',coalesce(sum(entrada),0),'salidas',coalesce(sum(salida),0),
    'variacion',coalesce(sum(entrada-salida),0),'total_movimientos',count(*),
    'ventas_efectivo',coalesce(sum(entrada) FILTER(WHERE tipo='VENTA'),0),
    'cobros_clientes',coalesce(sum(entrada) FILTER(WHERE tipo='COBRO_CLIENTE'),0),
    'compras_efectivo',coalesce(sum(salida) FILTER(WHERE tipo='COMPRA'),0),
    'pagos_proveedores',coalesce(sum(salida) FILTER(WHERE tipo='PAGO_PROVEEDOR'),0),
    'movimientos',coalesce((SELECT jsonb_agg(to_jsonb(p) ORDER BY p.fecha DESC,p.tipo,p.id DESC) FROM pagina p),'[]'::jsonb),
    'inconsistencias_total',(SELECT count(*) FROM comprobados WHERE NOT consistente),
    'inconsistencias',coalesce((SELECT jsonb_agg(to_jsonb(p)) FROM problemas p),'[]'::jsonb)) INTO v_resultado FROM validos;
  RETURN v_resultado;
END;
$function$;

CREATE OR REPLACE FUNCTION public.obtener_caja_dia(p_fecha date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE v_dia jsonb; v_flujo jsonb; v_gastos numeric; v_retiros numeric; v_aportes numeric; v_eventos jsonb; v_entrada numeric; v_salida numeric;
BEGIN
  IF auth.uid() IS NULL OR NOT public.fn_tiene_rol(ARRAY['ADMINISTRADOR']) THEN
    RAISE EXCEPTION 'Solo el administrador puede consultar caja.' USING ERRCODE='42501';
  END IF;
  v_flujo:=public.obtener_flujo_efectivo(p_fecha,0);
  SELECT to_jsonb(d) INTO v_dia FROM public.caja_dias d WHERE fecha=p_fecha;
  SELECT coalesce(sum(monto) FILTER(WHERE tipo='GASTO'),0),coalesce(sum(monto) FILTER(WHERE tipo='RETIRO_PERSONAL'),0),coalesce(sum(monto) FILTER(WHERE tipo='APORTE'),0)
  INTO v_gastos,v_retiros,v_aportes FROM public.caja_eventos WHERE fecha_caja=p_fecha;
  SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.fecha DESC,x.id_evento DESC),'[]'::jsonb) INTO v_eventos
  FROM (SELECT e.id_evento,e.fecha,e.tipo,e.monto,e.concepto,e.datos,u.nombre AS usuario
        FROM public.caja_eventos e JOIN public.usuarios u ON u.id_usuario=e.usuario_id
        WHERE e.fecha_caja=p_fecha ORDER BY e.fecha DESC,e.id_evento DESC LIMIT 30)x;
  SELECT coalesce(sum(caja_delta) FILTER(WHERE caja_delta>0),0),coalesce(sum(-caja_delta) FILTER(WHERE caja_delta<0),0) INTO v_entrada,v_salida FROM public.reserva_eventos WHERE fecha_caja=p_fecha;
  RETURN jsonb_build_object('traslados_entrada',v_entrada,'traslados_salida',v_salida,'fecha',p_fecha,'caja',v_dia,'automatico',v_flujo,
    'gastos',v_gastos,'retiros',v_retiros,'aportes',v_aportes,
    'saldo_esperado',CASE WHEN v_dia IS NULL THEN NULL ELSE (v_dia->>'efectivo_inicial')::numeric+(v_flujo->>'variacion')::numeric+v_aportes-v_gastos-v_retiros+v_entrada-v_salida END,
    'eventos',v_eventos);
END;
$function$;

CREATE OR REPLACE FUNCTION tienda_privada.proteger_cierre_caja()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_dias date[]:=ARRAY[]::date[]; v_dia date; v_extra date[];
BEGIN
  IF TG_OP<>'INSERT' THEN
    IF EXISTS(SELECT 1 FROM public.formas_pago WHERE id_forma_pago=OLD.forma_pago_id AND nombre='EFECTIVO') AND coalesce(to_jsonb(OLD)->>'fondo_efectivo','CAJA')='CAJA' THEN
      v_dias:=array_append(v_dias,(OLD.fecha AT TIME ZONE 'America/Guatemala')::date);
    END IF;
    -- Cambiar una venta/compra a crédito también afectaría sus abonos en efectivo.
    IF TG_TABLE_NAME='ventas' THEN
      SELECT array_agg((p.fecha AT TIME ZONE 'America/Guatemala')::date) INTO v_extra
      FROM public.pagos_cuentas_por_cobrar p JOIN public.cuentas_por_cobrar c ON c.id_cuenta_por_cobrar=p.cuenta_por_cobrar_id
      JOIN public.formas_pago f ON f.id_forma_pago=p.forma_pago_id WHERE c.venta_id=OLD.id_venta AND f.nombre='EFECTIVO';
      v_dias:=v_dias||coalesce(v_extra,ARRAY[]::date[]);
    ELSIF TG_TABLE_NAME='compras' THEN
      SELECT array_agg((p.fecha AT TIME ZONE 'America/Guatemala')::date) INTO v_extra
      FROM public.pagos_cuentas_por_pagar p JOIN public.cuentas_por_pagar c ON c.id_cuenta_por_pagar=p.cuenta_por_pagar_id
      JOIN public.formas_pago f ON f.id_forma_pago=p.forma_pago_id WHERE c.compra_id=OLD.id_compra AND f.nombre='EFECTIVO' AND p.fondo_efectivo='CAJA';
      v_dias:=v_dias||coalesce(v_extra,ARRAY[]::date[]);
    END IF;
  END IF;
  IF TG_OP<>'DELETE' AND EXISTS(SELECT 1 FROM public.formas_pago WHERE id_forma_pago=NEW.forma_pago_id AND nombre='EFECTIVO') AND coalesce(to_jsonb(NEW)->>'fondo_efectivo','CAJA')='CAJA' THEN
    v_dias:=array_append(v_dias,(NEW.fecha AT TIME ZONE 'America/Guatemala')::date);
  END IF;
  FOR v_dia IN SELECT DISTINCT d FROM unnest(v_dias) d WHERE d IS NOT NULL ORDER BY d LOOP
    PERFORM pg_advisory_xact_lock(hashtextextended('caja-dia:'||v_dia::text,0));
    IF EXISTS(SELECT 1 FROM public.caja_dias WHERE fecha=v_dia AND estado='CERRADA') THEN
      RAISE EXCEPTION 'La caja del % está cerrada. El administrador debe reabrirla para registrar o modificar efectivo de esa fecha.',v_dia USING ERRCODE='P0001';
    END IF;
  END LOOP;
  IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END;
$function$;

COMMIT;
