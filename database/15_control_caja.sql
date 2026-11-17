-- Caja única por fecha de Guatemala. Eventos inmutables desde la aplicación.
BEGIN;
CREATE TABLE public.caja_dias (
  fecha date PRIMARY KEY,
  efectivo_inicial numeric(12,2) NOT NULL CHECK(efectivo_inicial>=0 AND efectivo_inicial<=9999999999.99),
  estado text NOT NULL CHECK(estado IN ('ABIERTA','CERRADA')),
  usuario_apertura uuid NOT NULL REFERENCES public.usuarios(id_usuario),
  fecha_apertura timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  ultimo_cierre jsonb
);
CREATE TABLE public.caja_eventos (
  id_evento bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  fecha_caja date NOT NULL REFERENCES public.caja_dias(fecha),
  fecha timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  usuario_id uuid NOT NULL REFERENCES public.usuarios(id_usuario),
  solicitud_id uuid NOT NULL UNIQUE,
  tipo text NOT NULL CHECK(tipo IN ('APERTURA','AJUSTE_FONDO','GASTO','RETIRO_PERSONAL','APORTE','CIERRE','REAPERTURA')),
  monto numeric(12,2),
  concepto text NOT NULL CHECK(length(concepto)<=500),
  parametros jsonb NOT NULL,
  resultado jsonb NOT NULL DEFAULT '{}'::jsonb,
  datos jsonb NOT NULL DEFAULT '{}'::jsonb,
  CHECK((tipo='REAPERTURA' AND monto IS NULL) OR
        (tipo IN ('APERTURA','AJUSTE_FONDO','CIERRE') AND monto IS NOT NULL AND monto>=0 AND monto<=9999999999.99) OR
        (tipo IN ('GASTO','RETIRO_PERSONAL','APORTE') AND monto IS NOT NULL AND monto>0 AND monto<=9999999999.99))
);
CREATE INDEX caja_eventos_dia_fecha_idx ON public.caja_eventos(fecha_caja,fecha DESC,id_evento DESC);
CREATE INDEX caja_dias_usuario_idx ON public.caja_dias(usuario_apertura);
CREATE INDEX caja_eventos_usuario_idx ON public.caja_eventos(usuario_id);
ALTER TABLE public.caja_dias ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.caja_eventos ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.caja_dias,public.caja_eventos FROM anon,authenticated;
GRANT SELECT ON public.caja_dias,public.caja_eventos TO authenticated;
CREATE POLICY caja_dias_admin_select ON public.caja_dias FOR SELECT TO authenticated USING(public.fn_tiene_rol(ARRAY['ADMINISTRADOR']));
CREATE POLICY caja_eventos_admin_select ON public.caja_eventos FOR SELECT TO authenticated USING(public.fn_tiene_rol(ARRAY['ADMINISTRADOR']));

CREATE OR REPLACE FUNCTION public.obtener_caja_dia(p_fecha date)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $fn$
DECLARE v_dia jsonb; v_flujo jsonb; v_gastos numeric; v_retiros numeric; v_aportes numeric; v_eventos jsonb;
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
  RETURN jsonb_build_object('fecha',p_fecha,'caja',v_dia,'automatico',v_flujo,
    'gastos',v_gastos,'retiros',v_retiros,'aportes',v_aportes,
    'saldo_esperado',CASE WHEN v_dia IS NULL THEN NULL ELSE (v_dia->>'efectivo_inicial')::numeric+(v_flujo->>'variacion')::numeric+v_aportes-v_gastos-v_retiros END,
    'eventos',v_eventos);
END;
$fn$;
REVOKE ALL ON FUNCTION public.obtener_caja_dia(date) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.obtener_caja_dia(date) TO authenticated;

CREATE OR REPLACE FUNCTION tienda_privada.operar_caja(p_solicitud_id uuid,p_fecha date,p_tipo text,p_monto numeric,p_concepto text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' SET timezone='America/Guatemala' AS $fn$
DECLARE
  v_usuario uuid:=auth.uid(); v_params jsonb; v_anterior public.caja_eventos%ROWTYPE;
  v_dia public.caja_dias%ROWTYPE; v_resumen jsonb; v_datos jsonb:='{}'::jsonb;
  v_concepto text:=trim(coalesce(p_concepto,'')); v_id bigint; v_resultado jsonb;
  v_hoy date:=(CURRENT_TIMESTAMP AT TIME ZONE 'America/Guatemala')::date; v_diferencia numeric;
BEGIN
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
          'saldo_esperado',v_resumen->'saldo_esperado','efectivo_contado',p_monto,'diferencia',v_diferencia,'observacion',v_concepto);
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
$fn$;
REVOKE ALL ON FUNCTION tienda_privada.operar_caja(uuid,date,text,numeric,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION tienda_privada.operar_caja(uuid,date,text,numeric,text) TO authenticated;
CREATE OR REPLACE FUNCTION public.operar_caja(p_solicitud_id uuid,p_fecha date,p_tipo text,p_monto numeric DEFAULT NULL,p_concepto text DEFAULT '')
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $fn$
  SELECT tienda_privada.operar_caja(p_solicitud_id,p_fecha,p_tipo,p_monto,p_concepto);
$fn$;
REVOKE ALL ON FUNCTION public.operar_caja(uuid,date,text,numeric,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.operar_caja(uuid,date,text,numeric,text) TO authenticated;

-- Los cuatro orígenes de efectivo usan el mismo candado diario que el cierre.
-- Los días sin apertura conservan el comportamiento anterior de la aplicación.
CREATE OR REPLACE FUNCTION tienda_privada.proteger_cierre_caja()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_dias date[]:=ARRAY[]::date[]; v_dia date; v_extra date[];
BEGIN
  IF TG_OP<>'INSERT' THEN
    IF EXISTS(SELECT 1 FROM public.formas_pago WHERE id_forma_pago=OLD.forma_pago_id AND nombre='EFECTIVO') THEN
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
      JOIN public.formas_pago f ON f.id_forma_pago=p.forma_pago_id WHERE c.compra_id=OLD.id_compra AND f.nombre='EFECTIVO';
      v_dias:=v_dias||coalesce(v_extra,ARRAY[]::date[]);
    END IF;
  END IF;
  IF TG_OP<>'DELETE' AND EXISTS(SELECT 1 FROM public.formas_pago WHERE id_forma_pago=NEW.forma_pago_id AND nombre='EFECTIVO') THEN
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
$fn$;
REVOKE ALL ON FUNCTION tienda_privada.proteger_cierre_caja() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER trg_00_caja_guard BEFORE INSERT OR UPDATE OR DELETE ON public.ventas FOR EACH ROW EXECUTE FUNCTION tienda_privada.proteger_cierre_caja();
CREATE TRIGGER trg_00_caja_guard BEFORE INSERT OR UPDATE OR DELETE ON public.compras FOR EACH ROW EXECUTE FUNCTION tienda_privada.proteger_cierre_caja();
CREATE TRIGGER trg_00_caja_guard BEFORE INSERT OR UPDATE OR DELETE ON public.pagos_cuentas_por_cobrar FOR EACH ROW EXECUTE FUNCTION tienda_privada.proteger_cierre_caja();
CREATE TRIGGER trg_00_caja_guard BEFORE INSERT OR UPDATE OR DELETE ON public.pagos_cuentas_por_pagar FOR EACH ROW EXECUTE FUNCTION tienda_privada.proteger_cierre_caja();
COMMIT;
