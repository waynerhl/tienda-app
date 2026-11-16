-- Prueba transaccional: crea fixtures y revierte TODOS los registros al terminar.
-- Ejecutar desde SQL Editor como postgres. Las secuencias pueden dejar saltos normales.
BEGIN;
SELECT set_config('test.usuario', (SELECT u.id_usuario::text FROM public.usuarios u JOIN public.roles r ON r.id_rol=u.rol_id WHERE u.activo AND r.nombre='ADMINISTRADOR' LIMIT 1), true);
WITH x AS (INSERT INTO public.categorias(nombre) VALUES('__TEST_COMPRAS_CATEGORIA__') RETURNING id_categoria)
SELECT set_config('test.categoria',(SELECT id_categoria::text FROM x),true);
WITH x AS (INSERT INTO public.proveedores(nombre) VALUES('__TEST_COMPRAS_PROVEEDOR__') RETURNING id_proveedor)
SELECT set_config('test.proveedor',(SELECT id_proveedor::text FROM x),true);
WITH x AS (INSERT INTO public.productos(categoria_id,nombre,precio_venta,controla_lotes) VALUES(current_setting('test.categoria')::integer,'__TEST_COMPRAS_SIN_LOTES__',10,false) RETURNING id_producto)
SELECT set_config('test.producto',(SELECT id_producto::text FROM x),true);
WITH x AS (INSERT INTO public.productos(categoria_id,nombre,precio_venta,controla_lotes) VALUES(current_setting('test.categoria')::integer,'__TEST_COMPRAS_CON_LOTES__',10,true) RETURNING id_producto)
SELECT set_config('test.producto_lotes',(SELECT id_producto::text FROM x),true);
SELECT set_config('request.jwt.claims', json_build_object('sub',current_setting('test.usuario'),'role','authenticated')::text,true);
SET LOCAL ROLE authenticated;
DO $test$
DECLARE
  v_proveedor integer:=current_setting('test.proveedor')::integer;
  v_producto integer:=current_setting('test.producto')::integer;
  v_lotes integer:=current_setting('test.producto_lotes')::integer;
  v_efectivo integer;
  v_credito integer;
  v_resp jsonb;
  v_items jsonb;
  v_antes bigint;
BEGIN
  SELECT id_forma_pago INTO STRICT v_efectivo FROM public.formas_pago WHERE nombre='EFECTIVO';
  SELECT id_forma_pago INTO STRICT v_credito FROM public.formas_pago WHERE nombre='CREDITO';
  v_items:=jsonb_build_array(jsonb_build_object('producto_id',v_producto,'cantidad',4,'costo_unitario',2.50));
  v_resp:=public.registrar_compra(v_proveedor,v_efectivo,'TEST-CONTADO',v_items,NULL);
  ASSERT (v_resp->>'total')::numeric=10, 'Total incorrecto';
  ASSERT (SELECT existencia=4 AND ultimo_costo=2.50 FROM public.productos WHERE id_producto=v_producto), 'Stock o costo incorrecto';
  ASSERT (SELECT count(*)=1 FROM public.movimientos_inventario WHERE producto_id=v_producto), 'Movimiento no creado';
  BEGIN
    PERFORM public.registrar_compra(v_proveedor,v_efectivo,'TEST-CONTADO',v_items,NULL);
    RAISE EXCEPTION 'Debió rechazar referencia duplicada';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
  ASSERT (SELECT existencia=4 FROM public.productos WHERE id_producto=v_producto), 'Duplicó existencia';
  v_resp:=public.registrar_compra(v_proveedor,v_credito,'TEST-CREDITO',v_items,(CURRENT_TIMESTAMP AT TIME ZONE 'America/Guatemala')::date+10);
  ASSERT (SELECT saldo_pendiente=10 AND monto_original=10 FROM public.cuentas_por_pagar WHERE compra_id=(v_resp->>'id_compra')::integer), 'Cuenta por pagar incorrecta';
  ASSERT (SELECT existencia=8 FROM public.productos WHERE id_producto=v_producto), 'Stock crédito incorrecto';
  v_items:=jsonb_build_array(jsonb_build_object('producto_id',v_lotes,'cantidad',5,'costo_unitario',3,'lotes',jsonb_build_array(jsonb_build_object('cantidad',2,'numero_lote','A','fecha_vencimiento',(CURRENT_TIMESTAMP AT TIME ZONE 'America/Guatemala')::date+30),jsonb_build_object('cantidad',3,'numero_lote','B','fecha_vencimiento',(CURRENT_TIMESTAMP AT TIME ZONE 'America/Guatemala')::date+60))));
  v_resp:=public.registrar_compra(v_proveedor,v_efectivo,'TEST-LOTES',v_items,NULL);
  ASSERT (SELECT existencia=5 FROM public.productos WHERE id_producto=v_lotes), 'Stock por lotes incorrecto';
  ASSERT (SELECT sum(public.fn_stock_lote(l.id_lote))=5 FROM public.lotes l JOIN public.detalle_compras dc ON dc.id_detalle_compra=l.detalle_compra_id WHERE dc.producto_id=v_lotes), 'Saldo de lotes incorrecto';
  SELECT count(*) INTO v_antes FROM public.compras;
  BEGIN
    PERFORM public.registrar_compra(v_proveedor,v_efectivo,'TEST-ERROR',jsonb_build_array(jsonb_build_object('producto_id',v_lotes,'cantidad',9,'costo_unitario',3,'lotes',jsonb_build_array(jsonb_build_object('cantidad',1)))),NULL);
    RAISE EXCEPTION 'Debió rechazar lotes inconsistentes';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
  ASSERT (SELECT count(*)=v_antes FROM public.compras), 'Dejó encabezado parcial';
  ASSERT (SELECT existencia=5 FROM public.productos WHERE id_producto=v_lotes), 'No revirtió stock';
  BEGIN
    PERFORM public.registrar_compra(v_proveedor,v_efectivo,'TEST-VENCIDO',jsonb_build_array(jsonb_build_object('producto_id',v_lotes,'cantidad',1,'costo_unitario',3,'lotes',jsonb_build_array(jsonb_build_object('cantidad',1,'fecha_vencimiento','2000-01-01')))),NULL);
    RAISE EXCEPTION 'Debió rechazar lote vencido';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
  PERFORM set_config('request.jwt.claims','{"role":"authenticated"}',true);
  BEGIN
    PERFORM public.registrar_compra(v_proveedor,v_efectivo,'TEST-SIN-SESION',v_items,NULL);
    RAISE EXCEPTION 'Debió rechazar usuario sin sesión';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END;
$test$;
ROLLBACK;
SELECT 'OK: contado, crédito, lotes, duplicados, rollback, vencimiento y autenticación. Sin registros de prueba persistentes.' AS resultado;
