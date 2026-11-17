-- Ejecutar completo como postgres. Todos los registros de prueba se revierten.
BEGIN;
SELECT set_config('test.usuario',(SELECT u.id_usuario::text FROM public.usuarios u JOIN public.roles r ON r.id_rol=u.rol_id WHERE u.activo AND r.nombre='ADMINISTRADOR' LIMIT 1),true);
SELECT set_config('request.jwt.claims',json_build_object('sub',current_setting('test.usuario'),'role','authenticated')::text,true);
DO $fixtures$
DECLARE
  cat integer; prov integer; cli integer; prod integer;
  efectivo integer; credito integer; tarjeta integer; transferencia integer;
  resp jsonb; venta integer; compra integer; cxc integer; cxp integer; pago integer;
BEGIN
  ASSERT (public.obtener_flujo_efectivo('2001-01-02',0)->>'total_movimientos')::integer=0,'El día de prueba ya tiene registros; usa otro día vacío.';
  SELECT id_forma_pago INTO STRICT efectivo FROM public.formas_pago WHERE nombre='EFECTIVO';
  SELECT id_forma_pago INTO STRICT credito FROM public.formas_pago WHERE nombre='CREDITO';
  SELECT id_forma_pago INTO STRICT tarjeta FROM public.formas_pago WHERE nombre='TARJETA';
  SELECT id_forma_pago INTO STRICT transferencia FROM public.formas_pago WHERE nombre='TRANSFERENCIA';
  INSERT INTO public.categorias(nombre) VALUES('__TEST_EFECTIVO_CAT__') RETURNING id_categoria INTO cat;
  INSERT INTO public.proveedores(nombre) VALUES('__TEST_EFECTIVO_PROV__') RETURNING id_proveedor INTO prov;
  INSERT INTO public.clientes(nombre) VALUES('__TEST_EFECTIVO_CLIENTE__') RETURNING id_cliente INTO cli;
  INSERT INTO public.productos(categoria_id,nombre,precio_venta) VALUES(cat,'__TEST_EFECTIVO_PRODUCTO__',10) RETURNING id_producto INTO prod;
  resp:=public.registrar_compra(prov,efectivo,'TEST-EFECTIVO-CONTADO',jsonb_build_array(jsonb_build_object('producto_id',prod,'cantidad',100,'costo_unitario',0.20)),null);
  UPDATE public.compras SET fecha='2001-01-02T18:00:00Z' WHERE id_compra=(resp->>'id_compra')::integer;
  resp:=public.registrar_compra(prov,efectivo,'TEST-EFECTIVO-SIN-CARGO',jsonb_build_array(jsonb_build_object('producto_id',prod,'cantidad',1,'costo_unitario',0)),null);
  UPDATE public.compras SET fecha='2001-01-02T18:00:00Z' WHERE id_compra=(resp->>'id_compra')::integer;
  resp:=public.registrar_compra(prov,credito,'TEST-EFECTIVO-CREDITO',jsonb_build_array(jsonb_build_object('producto_id',prod,'cantidad',10,'costo_unitario',3)),null);
  compra:=(resp->>'id_compra')::integer;
  UPDATE public.compras SET fecha='2000-12-01T18:00:00Z' WHERE id_compra=compra;
  SELECT id_cuenta_por_pagar INTO STRICT cxp FROM public.cuentas_por_pagar WHERE compra_id=compra;
  resp:=public.registrar_venta(cli,efectivo,jsonb_build_array(jsonb_build_object('producto_id',prod,'cantidad',3)),null);
  UPDATE public.ventas SET fecha='2001-01-02T18:00:00Z' WHERE id_venta=(resp->>'id_venta')::integer;
  resp:=public.registrar_venta(cli,tarjeta,jsonb_build_array(jsonb_build_object('producto_id',prod,'cantidad',1)),null);
  UPDATE public.ventas SET fecha='2001-01-02T18:00:00Z' WHERE id_venta=(resp->>'id_venta')::integer;
  resp:=public.registrar_venta(cli,credito,jsonb_build_array(jsonb_build_object('producto_id',prod,'cantidad',2)),null);
  venta:=(resp->>'id_venta')::integer;
  UPDATE public.ventas SET fecha='2000-12-01T18:00:00Z' WHERE id_venta=venta;
  SELECT id_cuenta_por_cobrar INTO STRICT cxc FROM public.cuentas_por_cobrar WHERE venta_id=venta;
  resp:=public.registrar_abono_cxc(gen_random_uuid(),cxc,efectivo,5);
  pago:=(resp->>'id_pago')::integer;
  UPDATE public.pagos_cuentas_por_cobrar SET fecha='2001-01-02T18:00:00Z' WHERE id_pago_cuenta_por_cobrar=pago;
  resp:=public.registrar_abono_cxc(gen_random_uuid(),cxc,transferencia,2);
  UPDATE public.pagos_cuentas_por_cobrar SET fecha='2001-01-02T18:00:00Z' WHERE id_pago_cuenta_por_cobrar=(resp->>'id_pago')::integer;
  resp:=public.registrar_abono_cxp(gen_random_uuid(),cxp,efectivo,10);
  UPDATE public.pagos_cuentas_por_pagar SET fecha='2001-01-03T05:59:59Z' WHERE id_pago_cuenta_por_pagar=(resp->>'id_pago')::integer;
  resp:=public.registrar_abono_cxp(gen_random_uuid(),cxp,transferencia,1);
  UPDATE public.pagos_cuentas_por_pagar SET fecha='2001-01-02T18:00:00Z' WHERE id_pago_cuenta_por_pagar=(resp->>'id_pago')::integer;
  resp:=public.registrar_abono_cxp(gen_random_uuid(),cxp,efectivo,5);
  UPDATE public.pagos_cuentas_por_pagar SET fecha='2001-01-03T06:00:00Z' WHERE id_pago_cuenta_por_pagar=(resp->>'id_pago')::integer;
  -- Inicio incluido, instante anterior excluido, inicio siguiente excluido.
  resp:=public.registrar_venta(cli,efectivo,jsonb_build_array(jsonb_build_object('producto_id',prod,'cantidad',1)),null);
  UPDATE public.ventas SET fecha='2001-01-02T06:00:00Z' WHERE id_venta=(resp->>'id_venta')::integer;
  resp:=public.registrar_venta(cli,efectivo,jsonb_build_array(jsonb_build_object('producto_id',prod,'cantidad',1)),null);
  UPDATE public.ventas SET fecha='2001-01-02T05:59:59Z' WHERE id_venta=(resp->>'id_venta')::integer;
  resp:=public.registrar_venta(cli,efectivo,jsonb_build_array(jsonb_build_object('producto_id',prod,'cantidad',1)),null);
  UPDATE public.ventas SET fecha='2001-01-03T06:00:00Z' WHERE id_venta=(resp->>'id_venta')::integer;
  FOR i IN 1..21 LOOP
    resp:=public.registrar_venta(cli,efectivo,jsonb_build_array(jsonb_build_object('producto_id',prod,'cantidad',1)),null);
    UPDATE public.ventas SET fecha='2001-01-02T20:00:00Z' WHERE id_venta=(resp->>'id_venta')::integer;
  END LOOP;
  -- Registros heredados incompletos: deben advertirse y excluirse.
  INSERT INTO public.ventas(cliente_id,usuario_id,forma_pago_id,fecha,total,estado)
  VALUES(cli,auth.uid(),efectivo,'2001-01-02T18:00:00Z',99,'REGISTRADA');
  INSERT INTO public.compras(proveedor_id,usuario_id,forma_pago_id,fecha,total,estado)
  VALUES(prov,auth.uid(),efectivo,'2001-01-02T18:00:00Z',77,'REGISTRADA');
  INSERT INTO public.ventas(cliente_id,usuario_id,forma_pago_id,fecha,total,estado)
  VALUES(cli,auth.uid(),efectivo,'2001-01-02T18:00:00Z',50,'ANULADA');
END;
$fixtures$;
SET LOCAL ROLE authenticated;
DO $test$
DECLARE r jsonb; siguiente jsonb;
BEGIN
  r:=public.obtener_flujo_efectivo('2001-01-02',0);
  ASSERT (r->>'entradas')::numeric=255 AND (r->>'salidas')::numeric=30 AND (r->>'variacion')::numeric=225,'Totales de efectivo incorrectos';
  ASSERT (r->>'ventas_efectivo')::numeric=250 AND (r->>'cobros_clientes')::numeric=5,'Contó tarjeta, crédito o transferencia como entradas en efectivo';
  ASSERT (r->>'compras_efectivo')::numeric=20 AND (r->>'pagos_proveedores')::numeric=10,'Salidas incorrectas';
  ASSERT (r->>'total_movimientos')::integer=26 AND jsonb_array_length(r->'movimientos')=20,'Primera página incorrecta';
  ASSERT (r->>'inconsistencias_total')::integer=2,'No advirtió los documentos incompletos';
  siguiente:=public.obtener_flujo_efectivo('2001-01-02',1);
  ASSERT (siguiente->>'total_movimientos')::integer=26 AND jsonb_array_length(siguiente->'movimientos')=6,'Segunda página incorrecta';
  ASSERT (siguiente->>'entradas')::numeric=255 AND (siguiente->>'salidas')::numeric=30,'Los totales dependieron de la página';
  r:=public.obtener_flujo_efectivo('2001-01-03',0);
  ASSERT (r->>'entradas')::numeric=10 AND (r->>'salidas')::numeric=5,'Límite del día siguiente incorrecto';
  r:=public.obtener_flujo_efectivo('2000-12-01',0);
  ASSERT (r->>'total_movimientos')::integer=0 AND (r->>'entradas')::numeric=0 AND (r->>'salidas')::numeric=0,'Contó operaciones a crédito como efectivo';
  BEGIN
    PERFORM public.obtener_flujo_efectivo(null,0);
    RAISE EXCEPTION 'Aceptó fecha vacía';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  BEGIN
    PERFORM public.obtener_flujo_efectivo('2001-01-02',-1);
    RAISE EXCEPTION 'Aceptó página negativa';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  PERFORM set_config('request.jwt.claims',json_build_object('sub',gen_random_uuid(),'role','authenticated')::text,true);
  BEGIN
    PERFORM public.obtener_flujo_efectivo('2001-01-02',0);
    RAISE EXCEPTION 'Aceptó usuario sin perfil';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM set_config('request.jwt.claims','{"role":"authenticated"}',true);
  BEGIN
    PERFORM public.obtener_flujo_efectivo('2001-01-02',0);
    RAISE EXCEPTION 'Aceptó usuario sin sesión';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  ASSERT NOT has_function_privilege('anon','public.obtener_flujo_efectivo(date,integer)','EXECUTE'),'RPC accesible a anon';
END;
$test$;
ROLLBACK;
SELECT 'OK: efectivo, crédito, tarjeta, transferencia, fechas, paginación, inconsistencias y permisos. Fixtures revertidos.' AS resultado;
