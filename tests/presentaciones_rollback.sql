BEGIN;
SELECT set_config('test.usuario',(SELECT u.id_usuario::text FROM public.usuarios u JOIN public.roles r ON r.id_rol=u.rol_id WHERE u.activo AND r.nombre='ADMINISTRADOR' LIMIT 1),true);
SELECT set_config('request.jwt.claims',json_build_object('sub',current_setting('test.usuario'),'role','authenticated')::text,true);
DO $fixtures$
DECLARE v_cat integer;v_leche integer;v_huevos integer;v_cliente integer;v_hoy date:=(CURRENT_TIMESTAMP AT TIME ZONE 'America/Guatemala')::date;
BEGIN
 INSERT INTO public.categorias(nombre) VALUES('__TEST_PAQUETES_CAT__') RETURNING id_categoria INTO v_cat;
 INSERT INTO public.productos(categoria_id,nombre,precio_venta,controla_lotes) VALUES(v_cat,'__TEST_PAQUETES_LECHE__',14,true) RETURNING id_producto INTO v_leche;
 INSERT INTO public.productos(categoria_id,nombre,precio_venta) VALUES(v_cat,'__TEST_PAQUETES_HUEVOS__',1.50) RETURNING id_producto INTO v_huevos;
 INSERT INTO public.clientes(nombre) VALUES('__TEST_PAQUETES_CLIENTE__') RETURNING id_cliente INTO v_cliente;
 PERFORM public.registrar_inventario_inicial(gen_random_uuid(),v_leche,jsonb_build_array(jsonb_build_object('numero_lote','L-A','cantidad',50,'costo_unitario','10.00','fecha_vencimiento',v_hoy+10),jsonb_build_object('numero_lote','L-B','cantidad',190,'costo_unitario','11.00','fecha_vencimiento',v_hoy+20)),'Inventario de prueba');
 PERFORM public.registrar_inventario_inicial(gen_random_uuid(),v_huevos,jsonb_build_array(jsonb_build_object('cantidad',240,'costo_unitario','1.00')),'Inventario de prueba');
 PERFORM set_config('test.leche',v_leche::text,true);PERFORM set_config('test.huevos',v_huevos::text,true);PERFORM set_config('test.cliente',v_cliente::text,true);
END;
$fixtures$;
SET LOCAL ROLE authenticated;
DO $test$
DECLARE v_l integer:=current_setting('test.leche')::integer;v_h integer:=current_setting('test.huevos')::integer;v_tr integer;v_cr integer;v_r jsonb;v_case record;v_uuid uuid;v_repetir uuid;v_items jsonb;v_total numeric;v_base numeric;v_venta integer;v_hoy date:=(CURRENT_TIMESTAMP AT TIME ZONE 'America/Guatemala')::date;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('efectivo-fondos',0));
 SELECT id_forma_pago INTO v_tr FROM public.formas_pago WHERE nombre='TRANSFERENCIA';SELECT id_forma_pago INTO v_cr FROM public.formas_pago WHERE nombre='CREDITO';
 v_base:=(public.obtener_reporte_ventas(v_hoy,v_hoy)->>'ventas')::numeric;
 v_r:=public.configurar_paquete_producto(v_l,0,'Caja',12,145,false);ASSERT (v_r->>'paquete_version')::integer=1,'No configuró paquete';
 v_r:=public.configurar_paquete_producto(v_l,0,'Caja',12,145,false);ASSERT (v_r->>'paquete_version')::integer=1,'Reintento idéntico incrementó versión';
 PERFORM public.configurar_paquete_producto(v_h,0,'Cartón',30,38,true);
 FOR v_case IN SELECT * FROM (VALUES(1,14::numeric),(12,145),(13,159),(24,290),(25,304),(30,374))t(cantidad,total) LOOP
  v_uuid:=gen_random_uuid();v_items:=jsonb_build_array(jsonb_build_object('producto_id',v_l,'cantidad',v_case.cantidad,'precio_esperado',14,'paquete_version_esperada',1));
  v_r:=public.registrar_venta_segura(v_uuid,null,v_tr,v_items,null);v_venta:=(v_r->>'id_venta')::integer;
  ASSERT (v_r->>'total')::numeric=v_case.total,'Cobro de leche incorrecto';
  ASSERT (SELECT sum(subtotal)=v_case.total FROM public.detalle_ventas WHERE venta_id=v_venta),'Encabezado y detalle no concilian';
  ASSERT (SELECT sum(m.cantidad)=v_case.cantidad FROM public.movimientos_inventario m JOIN public.detalle_ventas d ON d.id_detalle_venta=m.detalle_venta_id WHERE d.venta_id=v_venta),'No descontó unidades base';
  IF v_case.cantidad=13 THEN v_repetir:=v_uuid;END IF;
 END LOOP;
 FOR v_case IN SELECT * FROM (VALUES(1,1.5::numeric),(29,43.5),(30,38),(31,39.5),(32,41),(60,76))t(cantidad,total) LOOP
  v_r:=public.registrar_venta_segura(gen_random_uuid(),null,v_tr,jsonb_build_array(jsonb_build_object('producto_id',v_h,'cantidad',v_case.cantidad,'precio_esperado',1.5,'paquete_version_esperada',1)),null);
  ASSERT (v_r->>'total')::numeric=v_case.total,'Cobro de huevos incorrecto';
 END LOOP;
 ASSERT (public.obtener_reporte_ventas(v_hoy,v_hoy)->>'ventas')::numeric-v_base=1525.5,'Reportes sumaron precio unitario en vez de subtotales';
 ASSERT (SELECT existencia=135 FROM public.productos WHERE id_producto=v_l) AND (SELECT existencia=57 FROM public.productos WHERE id_producto=v_h),'Existencias no concilian con unidades';
 ASSERT (SELECT sum(m.costo_total_venta)=1105 FROM public.movimientos_inventario m WHERE m.producto_id=v_l AND m.detalle_venta_id IS NOT NULL),'Costo FEFO no siguió unidades reales';
 ASSERT EXISTS(SELECT 1 FROM public.lotes_contexto l WHERE l.producto_id=v_l AND l.numero_lote='L-A' AND public.fn_stock_lote(l.id_lote)=0),'No aplicó FEFO';
 PERFORM public.configurar_paquete_producto(v_l,1,'Caja',12,150,false);
 v_r:=public.registrar_venta_segura(v_repetir,null,v_tr,jsonb_build_array(jsonb_build_object('producto_id',v_l,'cantidad',13,'precio_esperado',14,'paquete_version_esperada',1)),null);
 ASSERT (v_r->>'repetida')::boolean AND (v_r->>'total')::numeric=159,'Reintento cambió precio histórico o duplicó venta';
 ASSERT EXISTS(SELECT 1 FROM public.detalle_ventas d JOIN public.ventas v ON v.id_venta=d.venta_id WHERE v.solicitud_id=v_repetir AND d.paquete_precio=145 AND d.precio_unitario=14 AND d.subtotal=159),'No conservó precios de la venta';
 BEGIN PERFORM public.registrar_venta(null,v_tr,jsonb_build_array(jsonb_build_object('producto_id',v_l,'cantidad',12,'precio_esperado',14,'paquete_version_esperada',1)),null);RAISE EXCEPTION 'Aceptó presentación desactualizada';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 BEGIN PERFORM public.registrar_venta(null,v_tr,jsonb_build_array(jsonb_build_object('producto_id',v_l,'cantidad',12,'precio_esperado',14)),null);RAISE EXCEPTION 'Cliente antiguo omitió presentación';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 v_r:=public.registrar_venta(null,v_tr,jsonb_build_array(jsonb_build_object('producto_id',v_l,'cantidad',12,'precio_esperado',14,'paquete_version_esperada',2)),null);ASSERT (v_r->>'total')::numeric=150,'No aplicó precio nuevo';
 PERFORM public.configurar_paquete_producto(v_l,2,null,null,null,false);
 v_r:=public.registrar_venta(null,v_tr,jsonb_build_array(jsonb_build_object('producto_id',v_l,'cantidad',12,'precio_esperado',14,'paquete_version_esperada',3)),null);ASSERT (v_r->>'total')::numeric=168,'Desactivar paquete no volvió al precio unitario';
 v_r:=public.registrar_venta_segura(gen_random_uuid(),current_setting('test.cliente')::integer,v_cr,jsonb_build_array(jsonb_build_object('producto_id',v_h,'cantidad',31,'precio_esperado',1.5,'paquete_version_esperada',1)),null);
 ASSERT (SELECT monto_original=39.5 AND saldo_pendiente=39.5 FROM public.cuentas_por_cobrar WHERE venta_id=(v_r->>'id_venta')::integer),'Cuenta a crédito no usó el importe del cartón y sobrante';
 BEGIN PERFORM public.configurar_paquete_producto(v_h,0,'Cartón',30,37,true);RAISE EXCEPTION 'Sobrescribió versión antigua';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 BEGIN PERFORM public.configurar_paquete_producto(v_h,1,'Cartón',1,38,true);RAISE EXCEPTION 'Aceptó paquete de una unidad';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 BEGIN PERFORM public.configurar_paquete_producto(v_h,1,'Cartón',30,38.001,true);RAISE EXCEPTION 'Aceptó precio con más de dos decimales';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 BEGIN UPDATE public.productos SET paquete_precio=1 WHERE id_producto=v_h;RAISE EXCEPTION 'Permitió cambio directo';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 PERFORM set_config('request.jwt.claims','{"role":"authenticated"}',true);
 BEGIN PERFORM public.configurar_paquete_producto(v_h,1,'Cartón',30,37,true);RAISE EXCEPTION 'Configuró sin sesión';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 ASSERT NOT has_function_privilege('anon','public.configurar_paquete_producto(integer,integer,text,integer,numeric,boolean)','EXECUTE'),'Permitió anon';
END;
$test$;
ROLLBACK;
SELECT 'OK: cajas, cartones, sobrantes, exactitud de centavos, stock por unidades, FEFO, costos, reportes, crédito, versiones y reintentos. Datos revertidos.' AS resultado;
