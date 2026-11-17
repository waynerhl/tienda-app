-- Ejecutar completo como postgres. No persiste aperturas, cierres ni fixtures.
BEGIN;
SELECT set_config('test.usuario',(SELECT u.id_usuario::text FROM public.usuarios u JOIN public.roles r ON r.id_rol=u.rol_id WHERE u.activo AND r.nombre='ADMINISTRADOR' LIMIT 1),true);
SELECT set_config('request.jwt.claims',json_build_object('sub',current_setting('test.usuario'),'role','authenticated')::text,true);
DO $fixtures$
DECLARE cat integer; prov integer; cli integer; prod integer; fp integer; cr integer; r jsonb;
BEGIN
  ASSERT NOT EXISTS(SELECT 1 FROM public.caja_dias WHERE fecha=(CURRENT_TIMESTAMP AT TIME ZONE 'America/Guatemala')::date),'El día ya tiene caja: usa una base de pruebas antes de ejecutar este archivo.';
  r:=public.obtener_flujo_efectivo((CURRENT_TIMESTAMP AT TIME ZONE 'America/Guatemala')::date,0);
  ASSERT (r->>'inconsistencias_total')::integer=0,'El día tiene incidencias previas; no ejecutar esta prueba en ese estado.';
  PERFORM set_config('test.base',(r->>'variacion'),true);
  INSERT INTO public.categorias(nombre) VALUES('__TEST_CAJA_CAT__') RETURNING id_categoria INTO cat;
  INSERT INTO public.proveedores(nombre) VALUES('__TEST_CAJA_PROV__') RETURNING id_proveedor INTO prov;
  INSERT INTO public.clientes(nombre) VALUES('__TEST_CAJA_CLIENTE__') RETURNING id_cliente INTO cli;
  INSERT INTO public.productos(categoria_id,nombre,precio_venta) VALUES(cat,'__TEST_CAJA_PRODUCTO__',10) RETURNING id_producto INTO prod;
  PERFORM set_config('test.producto',prod::text,true); PERFORM set_config('test.proveedor',prov::text,true); PERFORM set_config('test.cliente',cli::text,true);
  SELECT id_forma_pago INTO fp FROM public.formas_pago WHERE nombre='EFECTIVO';
  SELECT id_forma_pago INTO cr FROM public.formas_pago WHERE nombre='CREDITO';
  r:=public.registrar_compra(prov,fp,'TEST-CAJA-CASH',jsonb_build_array(jsonb_build_object('producto_id',prod,'cantidad',10,'costo_unitario',2)),null);
  r:=public.registrar_compra(prov,cr,'TEST-CAJA-CREDITO',jsonb_build_array(jsonb_build_object('producto_id',prod,'cantidad',10,'costo_unitario',3)),null);
  PERFORM set_config('test.cxp',(SELECT id_cuenta_por_pagar::text FROM public.cuentas_por_pagar WHERE compra_id=(r->>'id_compra')::integer),true);
  r:=public.registrar_venta(cli,fp,jsonb_build_array(jsonb_build_object('producto_id',prod,'cantidad',2)),null);
  r:=public.registrar_venta(cli,cr,jsonb_build_array(jsonb_build_object('producto_id',prod,'cantidad',2)),null);
  PERFORM set_config('test.venta_credito',r->>'id_venta',true);
  PERFORM set_config('test.cxc',(SELECT id_cuenta_por_cobrar::text FROM public.cuentas_por_cobrar WHERE venta_id=(r->>'id_venta')::integer),true);
  r:=public.registrar_abono_cxc(gen_random_uuid(),current_setting('test.cxc')::integer,fp,5);
  PERFORM set_config('test.abono',r->>'id_pago',true);
  PERFORM public.registrar_abono_cxp(gen_random_uuid(),current_setting('test.cxp')::integer,fp,10);
END;
$fixtures$;
SET LOCAL ROLE authenticated;
DO $test$
DECLARE
  dia date:=(CURRENT_TIMESTAMP AT TIME ZONE 'America/Guatemala')::date;
  uuid_apertura uuid:=gen_random_uuid(); uuid_mov uuid:=gen_random_uuid(); uuid_cierre uuid:=gen_random_uuid();
  r jsonb; cierre jsonb; saldo numeric; contado numeric; fp integer; cr integer; tr integer; antes bigint; stock integer;
  producto integer:=current_setting('test.producto')::integer;
BEGIN
  SELECT id_forma_pago INTO fp FROM public.formas_pago WHERE nombre='EFECTIVO';
  SELECT id_forma_pago INTO cr FROM public.formas_pago WHERE nombre='CREDITO';
  SELECT id_forma_pago INTO tr FROM public.formas_pago WHERE nombre='TRANSFERENCIA';
  r:=public.obtener_caja_dia(dia);
  ASSERT r->'caja'='null'::jsonb AND r->'saldo_esperado'='null'::jsonb,'Inventó un fondo sin apertura';
  BEGIN
    PERFORM public.operar_caja(gen_random_uuid(),dia,'GASTO',1,'Sin apertura');
    RAISE EXCEPTION 'Permitió gasto sin apertura';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  PERFORM public.operar_caja(uuid_apertura,dia,'APERTURA',100,'');
  r:=public.operar_caja(uuid_apertura,dia,'APERTURA',100,'');
  ASSERT (r->>'repetida')::boolean,'Duplicó apertura al reintentar';
  BEGIN
    PERFORM public.operar_caja(gen_random_uuid(),dia,'APERTURA',100,'');
    RAISE EXCEPTION 'Permitió segunda apertura';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  PERFORM public.operar_caja(uuid_mov,dia,'GASTO',7,'Bolsas para la tienda');
  PERFORM public.operar_caja(uuid_mov,dia,'GASTO',7,'Bolsas para la tienda');
  BEGIN
    PERFORM public.operar_caja(uuid_mov,dia,'GASTO',8,'Bolsas para la tienda');
    RAISE EXCEPTION 'Permitió cambiar monto al reintentar';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  PERFORM public.operar_caja(gen_random_uuid(),dia,'RETIRO_PERSONAL',10,'Uso personal');
  PERFORM public.operar_caja(gen_random_uuid(),dia,'APORTE',20,'Fondo adicional');
  r:=public.obtener_caja_dia(dia); saldo:=(r->>'saldo_esperado')::numeric;
  ASSERT saldo=98+current_setting('test.base')::numeric,'Saldo de apertura + flujo + manuales incorrecto';
  ASSERT (r->>'gastos')::numeric=7 AND (r->>'retiros')::numeric=10 AND (r->>'aportes')::numeric=20,'Mezcló gastos con retiros';
  BEGIN
    PERFORM public.operar_caja(gen_random_uuid(),dia,'AJUSTE_FONDO',110,'');
    RAISE EXCEPTION 'Permitió corrección del fondo sin motivo';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  PERFORM public.operar_caja(gen_random_uuid(),dia,'AJUSTE_FONDO',110,'Corregir digitación');
  r:=public.obtener_caja_dia(dia); ASSERT (r->>'saldo_esperado')::numeric=saldo+10,'No aplicó corrección de fondo';
  PERFORM public.operar_caja(gen_random_uuid(),dia,'AJUSTE_FONDO',100,'Restaurar fondo de prueba');
  contado:=CASE WHEN saldo=0 THEN 1 ELSE 0 END;
  BEGIN
    PERFORM public.operar_caja(gen_random_uuid(),dia,'CIERRE',contado,'');
    RAISE EXCEPTION 'Permitió diferencia sin observación';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  cierre:=public.operar_caja(uuid_cierre,dia,'CIERRE',contado,'Diferencia de prueba documentada');
  ASSERT (cierre->'datos'->>'diferencia')::numeric=contado-saldo,'Diferencia incorrecta';
  r:=public.operar_caja(uuid_cierre,dia,'CIERRE',contado,'Diferencia de prueba documentada');
  ASSERT (r->>'repetida')::boolean AND r->'datos'=cierre->'datos','Cambió el cierre al reintentar';
  ASSERT (SELECT estado='CERRADA' FROM public.caja_dias WHERE fecha=dia),'No cerró caja';
  SELECT count(*) INTO antes FROM public.ventas;
  SELECT existencia INTO stock FROM public.productos WHERE id_producto=producto;
  BEGIN
    PERFORM public.registrar_venta(null,fp,jsonb_build_array(jsonb_build_object('producto_id',producto,'cantidad',1)),null);
    RAISE EXCEPTION 'Permitió venta en efectivo después del cierre' USING ERRCODE='23514';
  EXCEPTION WHEN raise_exception THEN NULL; END;
  ASSERT (SELECT count(*)=antes FROM public.ventas),'Dejó venta parcial tras rechazo';
  ASSERT (SELECT existencia=stock FROM public.productos WHERE id_producto=producto),'Descontó stock pese a cierre';
  BEGIN
    PERFORM public.registrar_compra(current_setting('test.proveedor')::integer,fp,'TEST-CAJA-CERRADA',jsonb_build_array(jsonb_build_object('producto_id',producto,'cantidad',1,'costo_unitario',2)),null);
    RAISE EXCEPTION 'Permitió compra en efectivo con caja cerrada' USING ERRCODE='23514';
  EXCEPTION WHEN raise_exception THEN NULL; END;
  BEGIN
    PERFORM public.registrar_abono_cxc(gen_random_uuid(),current_setting('test.cxc')::integer,fp,1);
    RAISE EXCEPTION 'Permitió cobro en efectivo con caja cerrada' USING ERRCODE='23514';
  EXCEPTION WHEN raise_exception THEN NULL; END;
  BEGIN
    PERFORM public.registrar_abono_cxp(gen_random_uuid(),current_setting('test.cxp')::integer,fp,1);
    RAISE EXCEPTION 'Permitió pago en efectivo con caja cerrada' USING ERRCODE='23514';
  EXCEPTION WHEN raise_exception THEN NULL; END;
  -- Otras formas de pago no alteran el efectivo cerrado.
  PERFORM public.registrar_venta(current_setting('test.cliente')::integer,cr,jsonb_build_array(jsonb_build_object('producto_id',producto,'cantidad',1)),null);
  PERFORM public.registrar_abono_cxc(gen_random_uuid(),current_setting('test.cxc')::integer,tr,1);
  BEGIN
    PERFORM public.operar_caja(gen_random_uuid(),dia,'GASTO',1,'Caja cerrada');
    RAISE EXCEPTION 'Permitió movimiento manual con caja cerrada';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  BEGIN
    PERFORM public.operar_caja(gen_random_uuid(),dia,'REAPERTURA',null,'');
    RAISE EXCEPTION 'Permitió reapertura sin motivo';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  PERFORM public.operar_caja(gen_random_uuid(),dia,'REAPERTURA',null,'Continuar atención');
  r:=public.obtener_caja_dia(dia);
  ASSERT r->'caja'->>'estado'='ABIERTA' AND r->'caja'->'ultimo_cierre'=cierre->'datos','Perdió cierre anterior al reabrir';
  PERFORM public.registrar_venta(null,fp,jsonb_build_array(jsonb_build_object('producto_id',producto,'cantidad',1)),null);
  r:=public.obtener_caja_dia(dia); ASSERT (r->>'saldo_esperado')::numeric=saldo+10,'No incluyó efectivo tras reapertura';
  PERFORM public.operar_caja(gen_random_uuid(),dia,'CIERRE',contado,'Segundo cierre');
  ASSERT (SELECT count(*)=2 FROM public.caja_eventos WHERE fecha_caja=dia AND tipo='CIERRE'),'No conservó ambos cierres';
  BEGIN
    INSERT INTO public.caja_eventos(fecha_caja,usuario_id,solicitud_id,tipo,monto,concepto,parametros)
    VALUES(dia,auth.uid(),gen_random_uuid(),'APORTE',100,'Falsificado','{}');
    RAISE EXCEPTION 'Permitió escritura directa';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM set_config('request.jwt.claims','{"role":"authenticated"}',true);
  BEGIN
    PERFORM public.obtener_caja_dia(dia);
    RAISE EXCEPTION 'Permitió consulta sin sesión';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    PERFORM public.operar_caja(gen_random_uuid(),dia,'REAPERTURA',null,'Sin sesión');
    RAISE EXCEPTION 'Permitió operar sin sesión';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END;
$test$;
RESET ROLE;
-- Comprueba también los cambios sobre los documentos y pagos ya cerrados.
DO $guardas$
BEGIN
  BEGIN
    UPDATE public.ventas SET estado='ANULADA' WHERE id_venta=current_setting('test.venta_credito')::integer;
    RAISE EXCEPTION 'Permitió modificar crédito con cobro en día cerrado' USING ERRCODE='23514';
  EXCEPTION WHEN raise_exception THEN NULL; END;
  BEGIN
    DELETE FROM public.pagos_cuentas_por_cobrar WHERE id_pago_cuenta_por_cobrar=current_setting('test.abono')::integer;
    RAISE EXCEPTION 'Permitió eliminar abono de día cerrado' USING ERRCODE='23514';
  EXCEPTION WHEN raise_exception THEN NULL; END;
END;
$guardas$;
ROLLBACK;
SELECT 'OK: apertura, gastos, retiros, aportes, cierre, diferencia, bloqueo, reapertura, historial y permisos. Fixtures revertidos.' AS resultado;
