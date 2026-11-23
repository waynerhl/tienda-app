-- Ejecutar completo como postgres. Fixtures y costos de prueba se revierten.
BEGIN;
SELECT set_config('test.usuario',(SELECT u.id_usuario::text FROM public.usuarios u JOIN public.roles r ON r.id_rol=u.rol_id WHERE u.activo AND r.nombre='ADMINISTRADOR' LIMIT 1),true);
SELECT set_config('request.jwt.claims',json_build_object('sub',current_setting('test.usuario'),'role','authenticated')::text,true);
DO $fixtures$
DECLARE v_cat integer;v_prov integer;v_normal integer;v_lotes integer;v_sin integer;v_gratis integer;v_tr integer;v_r jsonb;v_primera integer;v_legacy integer;v_lotventa integer;v_hoy date:=(CURRENT_TIMESTAMP AT TIME ZONE 'America/Guatemala')::date;
BEGIN
  ASSERT (public.obtener_reporte_ventas('2001-04-01','2001-04-03')->>'transacciones')::integer=0,'El período de prueba ya tiene ventas.';
  INSERT INTO public.categorias(nombre) VALUES('__TEST_COSTO_CAT__') RETURNING id_categoria INTO v_cat;
  INSERT INTO public.proveedores(nombre) VALUES('__TEST_COSTO_PROV__') RETURNING id_proveedor INTO v_prov;
  INSERT INTO public.productos(categoria_id,nombre,precio_venta) VALUES(v_cat,'__TEST_COSTO_NORMAL__',10) RETURNING id_producto INTO v_normal;
  INSERT INTO public.productos(categoria_id,nombre,precio_venta,controla_lotes) VALUES(v_cat,'__TEST_COSTO_LOTES__',10,true) RETURNING id_producto INTO v_lotes;
  INSERT INTO public.productos(categoria_id,nombre,precio_venta) VALUES(v_cat,'__TEST_COSTO_SIN__',8) RETURNING id_producto INTO v_sin;
  INSERT INTO public.productos(categoria_id,nombre,precio_venta) VALUES(v_cat,'__TEST_COSTO_GRATIS__',5) RETURNING id_producto INTO v_gratis;
  SELECT id_forma_pago INTO v_tr FROM public.formas_pago WHERE nombre='TRANSFERENCIA';
  PERFORM public.registrar_compra(v_prov,v_tr,'TEST-COSTO-GRATIS',jsonb_build_array(jsonb_build_object('producto_id',v_gratis,'cantidad',1,'costo_unitario',0)),null);
  v_r:=public.registrar_venta(null,v_tr,jsonb_build_array(jsonb_build_object('producto_id',v_gratis,'cantidad',1)),null);
  UPDATE public.ventas SET fecha='2001-04-04T18:00:00Z' WHERE id_venta=(v_r->>'id_venta')::integer;
  PERFORM public.registrar_compra(v_prov,v_tr,'TEST-COSTO-N1',jsonb_build_array(jsonb_build_object('producto_id',v_normal,'cantidad',10,'costo_unitario',2)),null);
  v_r:=public.registrar_venta(null,v_tr,jsonb_build_array(jsonb_build_object('producto_id',v_normal,'cantidad',2)),null);v_primera:=(v_r->>'id_venta')::integer;
  UPDATE public.ventas SET fecha='2001-04-01T18:00:00Z' WHERE id_venta=v_primera;
  PERFORM public.registrar_compra(v_prov,v_tr,'TEST-COSTO-N2',jsonb_build_array(jsonb_build_object('producto_id',v_normal,'cantidad',5,'costo_unitario',6)),null);
  ASSERT (SELECT sum(m.costo_total_venta)=4 FROM public.movimientos_inventario m JOIN public.detalle_ventas d ON d.id_detalle_venta=m.detalle_venta_id WHERE d.venta_id=v_primera),'Reescribió costo tras otra compra';
  v_r:=public.registrar_venta(null,v_tr,jsonb_build_array(jsonb_build_object('producto_id',v_normal,'cantidad',1)),null);
  UPDATE public.ventas SET fecha='2001-04-01T18:00:00Z' WHERE id_venta=(v_r->>'id_venta')::integer;
  PERFORM public.registrar_compra(v_prov,v_tr,'TEST-COSTO-L1',jsonb_build_array(jsonb_build_object('producto_id',v_lotes,'cantidad',3,'costo_unitario',2,'lotes',jsonb_build_array(jsonb_build_object('cantidad',3,'numero_lote','A','fecha_vencimiento',v_hoy+10)))),null);
  PERFORM public.registrar_compra(v_prov,v_tr,'TEST-COSTO-L2',jsonb_build_array(jsonb_build_object('producto_id',v_lotes,'cantidad',3,'costo_unitario',5,'lotes',jsonb_build_array(jsonb_build_object('cantidad',3,'numero_lote','B','fecha_vencimiento',v_hoy+20)))),null);
  PERFORM public.registrar_compra(v_prov,v_tr,'TEST-COSTO-LV',jsonb_build_array(jsonb_build_object('producto_id',v_lotes,'cantidad',2,'costo_unitario',1,'lotes',jsonb_build_array(jsonb_build_object('cantidad',2,'numero_lote','V','fecha_vencimiento',v_hoy+30)))),null);
  UPDATE public.lotes SET fecha_ingreso=v_hoy-10,fecha_vencimiento=v_hoy-1 WHERE numero_lote='V' AND detalle_compra_id IN(SELECT id_detalle_compra FROM public.detalle_compras WHERE producto_id=v_lotes);
  v_r:=public.registrar_venta(null,v_tr,jsonb_build_array(jsonb_build_object('producto_id',v_lotes,'cantidad',4)),null);v_lotventa:=(v_r->>'id_venta')::integer;
  UPDATE public.ventas SET fecha='2001-04-01T18:00:00Z' WHERE id_venta=v_lotventa;
  ASSERT (SELECT sum(m.costo_total_venta)=11 AND count(*)=2 AND bool_and(m.origen_costo_venta='LOTE_COMPRA') FROM public.movimientos_inventario m JOIN public.detalle_ventas d ON d.id_detalle_venta=m.detalle_venta_id WHERE d.venta_id=v_lotventa),'No usó costos de los lotes FEFO reales';
  PERFORM public.registrar_ajuste_inventario(gen_random_uuid(),v_sin,null,'AJUSTE_POSITIVO',2,0,'Unidades sin costo histórico conocido');
  v_r:=public.registrar_venta(null,v_tr,jsonb_build_array(jsonb_build_object('producto_id',v_sin,'cantidad',1)),null);
  UPDATE public.ventas SET fecha='2001-04-01T18:00:00Z' WHERE id_venta=(v_r->>'id_venta')::integer;
  -- Simula un movimiento anterior a esta actualización, con sus costos desconocidos.
  v_r:=public.registrar_venta(null,v_tr,jsonb_build_array(jsonb_build_object('producto_id',v_normal,'cantidad',1)),null);v_legacy:=(v_r->>'id_venta')::integer;
  UPDATE public.ventas SET fecha='2001-04-01T18:00:00Z' WHERE id_venta=v_legacy;
  UPDATE public.movimientos_inventario SET costo_unitario_venta=null,origen_costo_venta=null WHERE detalle_venta_id IN(SELECT id_detalle_venta FROM public.detalle_ventas WHERE venta_id=v_legacy);
  UPDATE public.productos SET precio_venta=0 WHERE id_producto=v_normal;
  v_r:=public.registrar_venta(null,v_tr,jsonb_build_array(jsonb_build_object('producto_id',v_normal,'cantidad',1)),null);
  UPDATE public.ventas SET fecha='2001-04-02T18:00:00Z' WHERE id_venta=(v_r->>'id_venta')::integer;
  UPDATE public.productos SET precio_venta=1 WHERE id_producto=v_normal;
  v_r:=public.registrar_venta(null,v_tr,jsonb_build_array(jsonb_build_object('producto_id',v_normal,'cantidad',1)),null);
  UPDATE public.ventas SET fecha='2001-04-03T18:00:00Z' WHERE id_venta=(v_r->>'id_venta')::integer;
  PERFORM set_config('test.venta_lotes',v_lotventa::text,true);
END;
$fixtures$;
SET LOCAL ROLE authenticated;
DO $test$
DECLARE v_r jsonb;
BEGIN
  v_r:=public.obtener_reporte_costos('2001-04-01','2001-04-01');
  ASSERT (v_r->>'lineas_con_costo')::integer=3 AND (v_r->>'lineas_sin_costo')::integer=2,'Cobertura de costos incorrecta';
  ASSERT (v_r->>'ventas_con_costo')::numeric=70 AND (v_r->>'ventas_sin_costo')::numeric=18,'Trató costos desconocidos como cero';
  ASSERT (v_r->>'costo_identificado')::numeric=21 AND (v_r->>'utilidad_bruta_estimada')::numeric=49 AND (v_r->>'margen_bruto_estimado')::numeric=70,'Costo, utilidad o margen incorrectos';
  ASSERT (v_r->>'lineas_ultimo_costo')::integer=2,'Método de último costo incorrecto';
  ASSERT (v_r->'mayores'->0->>'utilidad_bruta')::numeric=29 AND (v_r->'menores'->0->>'utilidad_bruta')::numeric=20,'Rankings de utilidad incorrectos';
  v_r:=public.obtener_reporte_ventas_costos('2001-04-01','2001-04-01');
  ASSERT (v_r->>'ventas')::numeric=88 AND (v_r->'costos'->>'ventas_con_costo')::numeric+(v_r->'costos'->>'ventas_sin_costo')::numeric=88,'Ventas y costos no concilian en el reporte combinado';
  v_r:=public.obtener_reporte_costos('2001-04-02','2001-04-02');
  ASSERT (v_r->>'ventas_con_costo')::numeric=0 AND (v_r->>'costo_identificado')::numeric=6 AND (v_r->>'utilidad_bruta_estimada')::numeric=-6 AND v_r->'margen_bruto_estimado'='null'::jsonb,'Venta sin cargo produjo margen inválido';
  v_r:=public.obtener_reporte_costos('2001-04-03','2001-04-03');
  ASSERT (v_r->>'utilidad_bruta_estimada')::numeric=-5 AND (v_r->>'margen_bruto_estimado')::numeric=-500,'Ocultó pérdida bruta';
  v_r:=public.obtener_reporte_costos('2001-04-04','2001-04-04');
  ASSERT (v_r->>'lineas_con_costo')::integer=1 AND (v_r->>'costo_identificado')::numeric=0 AND (v_r->>'utilidad_bruta_estimada')::numeric=5 AND (v_r->>'margen_bruto_estimado')::numeric=100,'Confundió costo cero con costo desconocido';
  v_r:=public.obtener_reporte_costos('2001-05-01','2001-05-01');
  ASSERT (v_r->>'lineas_con_costo')::integer=0 AND (v_r->>'lineas_sin_costo')::integer=0 AND jsonb_array_length(v_r->'mayores')=0,'Período vacío incorrecto';
  BEGIN
    PERFORM public.obtener_reporte_costos('2001-04-03','2001-04-01');RAISE EXCEPTION 'Aceptó fechas invertidas';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
  PERFORM set_config('request.jwt.claims','{"role":"authenticated"}',true);
  BEGIN
    PERFORM public.obtener_reporte_costos('2001-04-01','2001-04-01');RAISE EXCEPTION 'Permitió consultar sin sesión';
  EXCEPTION WHEN insufficient_privilege THEN NULL;END;
  ASSERT NOT has_function_privilege('anon','public.obtener_reporte_costos(date,date)','EXECUTE'),'Consulta pública para anon';
END;
$test$;
RESET ROLE;
SELECT set_config('request.jwt.claims',json_build_object('sub',current_setting('test.usuario'),'role','authenticated')::text,true);
DO $parcial$
DECLARE v_r jsonb;
BEGIN
  UPDATE public.movimientos_inventario SET costo_unitario_venta=null,origen_costo_venta=null
  WHERE id_movimiento_inventario=(SELECT m.id_movimiento_inventario FROM public.movimientos_inventario m JOIN public.detalle_ventas d ON d.id_detalle_venta=m.detalle_venta_id WHERE d.venta_id=current_setting('test.venta_lotes')::integer ORDER BY m.id_movimiento_inventario DESC LIMIT 1);
  v_r:=public.obtener_reporte_costos('2001-04-01','2001-04-01');
  ASSERT (v_r->>'ventas_con_costo')::numeric=30 AND (v_r->>'costo_identificado')::numeric=10 AND (v_r->>'utilidad_bruta_estimada')::numeric=20,'Sumó utilidad de una línea solo parcialmente costeada';
END;
$parcial$;
ROLLBACK;
SELECT 'OK: costo conservado, FEFO, último costo, costos desconocidos, margen, pérdidas y acceso. Fixtures revertidos.' AS resultado;
