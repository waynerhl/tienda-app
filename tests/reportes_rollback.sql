-- Ejecutar completo como postgres. Fixtures revertidos al terminar.
BEGIN;
SELECT set_config('test.usuario',(SELECT u.id_usuario::text FROM public.usuarios u JOIN public.roles r ON r.id_rol=u.rol_id WHERE u.activo AND r.nombre='ADMINISTRADOR' LIMIT 1),true);
SELECT set_config('request.jwt.claims',json_build_object('sub',current_setting('test.usuario'),'role','authenticated')::text,true);
DO $fixtures$
DECLARE v_cat integer;v_prov integer;v_cli integer;v_a integer;v_b integer;v_d integer;v_e integer;v_tr integer;v_cr integer;v_ta integer;v_r jsonb;
BEGIN
  ASSERT (public.obtener_reporte_ventas('2001-01-02','2001-01-04')->>'transacciones')::integer=0,'El período de prueba ya tiene ventas.';
  PERFORM set_config('test.activos',(SELECT count(*)::text FROM public.productos WHERE activo),true);
  INSERT INTO public.categorias(nombre) VALUES('__TEST_REP_CAT__') RETURNING id_categoria INTO v_cat;
  INSERT INTO public.proveedores(nombre) VALUES('__TEST_REP_PROV__') RETURNING id_proveedor INTO v_prov;
  INSERT INTO public.clientes(nombre) VALUES('__TEST_REP_CLIENTE__') RETURNING id_cliente INTO v_cli;
  INSERT INTO public.productos(categoria_id,nombre,precio_venta) VALUES(v_cat,'__TEST_REP_A__',10) RETURNING id_producto INTO v_a;
  INSERT INTO public.productos(categoria_id,nombre,precio_venta) VALUES(v_cat,'__TEST_REP_B__',20) RETURNING id_producto INTO v_b;
  INSERT INTO public.productos(categoria_id,nombre,precio_venta) VALUES(v_cat,'__TEST_REP_C__',5);
  INSERT INTO public.productos(categoria_id,nombre,precio_venta) VALUES(v_cat,'__TEST_REP_D__',5) RETURNING id_producto INTO v_d;
  INSERT INTO public.productos(categoria_id,nombre,precio_venta) VALUES(v_cat,'__TEST_REP_E__',0) RETURNING id_producto INTO v_e;
  SELECT id_forma_pago INTO v_tr FROM public.formas_pago WHERE nombre='TRANSFERENCIA';
  SELECT id_forma_pago INTO v_cr FROM public.formas_pago WHERE nombre='CREDITO';
  SELECT id_forma_pago INTO v_ta FROM public.formas_pago WHERE nombre='TARJETA';
  PERFORM public.registrar_compra(v_prov,v_tr,'TEST-REP-COMPRA',jsonb_build_array(jsonb_build_object('producto_id',v_a,'cantidad',20,'costo_unitario',1),jsonb_build_object('producto_id',v_b,'cantidad',20,'costo_unitario',1),jsonb_build_object('producto_id',v_d,'cantidad',20,'costo_unitario',1),jsonb_build_object('producto_id',v_e,'cantidad',1,'costo_unitario',0)),null);
  v_r:=public.registrar_venta(null,v_tr,jsonb_build_array(jsonb_build_object('producto_id',v_a,'cantidad',4),jsonb_build_object('producto_id',v_b,'cantidad',1)),null);
  UPDATE public.ventas SET fecha='2001-01-02T18:00:00Z' WHERE id_venta=(v_r->>'id_venta')::integer;
  v_r:=public.registrar_venta(v_cli,v_cr,jsonb_build_array(jsonb_build_object('producto_id',v_a,'cantidad',1)),null);
  UPDATE public.ventas SET fecha='2001-01-03T06:00:00Z' WHERE id_venta=(v_r->>'id_venta')::integer;
  v_r:=public.registrar_venta(null,v_ta,jsonb_build_array(jsonb_build_object('producto_id',v_b,'cantidad',2)),null);
  UPDATE public.ventas SET fecha='2001-01-04T05:59:59Z' WHERE id_venta=(v_r->>'id_venta')::integer;
  v_r:=public.registrar_venta(null,v_tr,jsonb_build_array(jsonb_build_object('producto_id',v_d,'cantidad',1)),null);
  UPDATE public.ventas SET fecha='2001-01-02T06:00:00Z' WHERE id_venta=(v_r->>'id_venta')::integer;
  UPDATE public.productos SET activo=false WHERE id_producto=v_d;
  v_r:=public.registrar_venta(null,v_tr,jsonb_build_array(jsonb_build_object('producto_id',v_a,'cantidad',1)),null);
  UPDATE public.ventas SET fecha='2001-01-02T05:59:59Z' WHERE id_venta=(v_r->>'id_venta')::integer;
  v_r:=public.registrar_venta(null,v_tr,jsonb_build_array(jsonb_build_object('producto_id',v_a,'cantidad',1)),null);
  UPDATE public.ventas SET fecha='2001-01-05T06:00:00Z' WHERE id_venta=(v_r->>'id_venta')::integer;
  v_r:=public.registrar_venta(null,v_tr,jsonb_build_array(jsonb_build_object('producto_id',v_a,'cantidad',1)),null);
  UPDATE public.ventas SET fecha='2001-01-03T18:00:00Z',total=99 WHERE id_venta=(v_r->>'id_venta')::integer;
  INSERT INTO public.ventas(usuario_id,forma_pago_id,fecha,total,estado) VALUES(auth.uid(),v_tr,'2001-01-03T18:00:00Z',123,'REGISTRADA');
  INSERT INTO public.ventas(usuario_id,forma_pago_id,fecha,total,estado) VALUES(auth.uid(),v_tr,'2001-01-03T18:00:00Z',200,'ANULADA');
  v_r:=public.registrar_venta(null,v_tr,jsonb_build_array(jsonb_build_object('producto_id',v_e,'cantidad',1)),null);
  UPDATE public.ventas SET fecha='2001-01-08T18:00:00Z' WHERE id_venta=(v_r->>'id_venta')::integer;
  PERFORM set_config('test.a',v_a::text,true);PERFORM set_config('test.b',v_b::text,true);PERFORM set_config('test.d',v_d::text,true);
END;
$fixtures$;
SET LOCAL ROLE authenticated;
DO $test$
DECLARE v_r jsonb;
BEGIN
  v_r:=public.obtener_reporte_ventas('2001-01-02','2001-01-04');
  ASSERT (v_r->>'ventas')::numeric=115 AND (v_r->>'transacciones')::integer=4 AND (v_r->>'ticket_promedio')::numeric=28.75,'Totales o ticket duplicados por detalles';
  ASSERT (v_r->>'unidades')::integer=9 AND (v_r->>'productos_vendidos')::integer=3,'Unidades incorrectas';
  ASSERT (v_r->>'ventas_credito')::numeric=10 AND (v_r->>'ventas_sin_credito')::numeric=105,'Clasificación de pago incorrecta';
  ASSERT (v_r->>'inconsistencias_total')::integer=2,'No advirtió documentos incompletos';
  ASSERT jsonb_array_length(v_r->'serie')=3 AND (v_r->'serie'->0->>'total')::numeric=65 AND (v_r->'serie'->1->>'total')::numeric=50 AND (v_r->'serie'->2->>'total')::numeric=0,'Serie o límites horarios incorrectos';
  ASSERT (v_r->'top_unidades'->0->>'id_producto')::integer=current_setting('test.a')::integer,'Ranking por unidades incorrecto';
  ASSERT (v_r->'top_importe'->0->>'id_producto')::integer=current_setting('test.b')::integer,'Ranking por importe incorrecto';
  ASSERT (v_r->>'activos_sin_ventas')::integer=current_setting('test.activos')::integer+2,'Catálogo activo sin ventas incorrecto';
  ASSERT EXISTS(SELECT 1 FROM jsonb_array_elements(v_r->'top_unidades')x WHERE (x->>'id_producto')::integer=current_setting('test.d')::integer AND NOT (x->>'activo')::boolean),'Omitió producto vendido actualmente inactivo';
  ASSERT (SELECT sum((x->>'total')::numeric)=115 FROM jsonb_array_elements(v_r->'por_pago')x),'Formas de pago no concilian';
  v_r:=public.obtener_reporte_ventas('2001-01-08','2001-01-08');
  ASSERT (v_r->>'ventas')::numeric=0 AND (v_r->>'transacciones')::integer=1 AND (v_r->>'unidades')::integer=1 AND (v_r->>'ticket_promedio')::numeric=0,'Venta sin cargo incorrecta';
  v_r:=public.obtener_reporte_ventas('2001-02-01','2001-02-02');
  ASSERT (v_r->>'ventas')::numeric=0 AND (v_r->>'transacciones')::integer=0 AND jsonb_array_length(v_r->'serie')=2 AND jsonb_array_length(v_r->'top_unidades')=0,'Período sin ventas incorrecto';
  BEGIN
    PERFORM public.obtener_reporte_ventas('2001-01-04','2001-01-02');RAISE EXCEPTION 'Aceptó fechas invertidas';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
  BEGIN
    PERFORM public.obtener_reporte_ventas('2000-01-01','2001-01-01');RAISE EXCEPTION 'Aceptó más de 366 días';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
  BEGIN
    PERFORM public.obtener_reporte_ventas(null,'2001-01-02');RAISE EXCEPTION 'Aceptó fecha vacía';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
  PERFORM set_config('request.jwt.claims',json_build_object('sub',gen_random_uuid(),'role','authenticated')::text,true);
  BEGIN
    PERFORM public.obtener_reporte_ventas('2001-01-02','2001-01-04');RAISE EXCEPTION 'Aceptó usuario sin perfil';
  EXCEPTION WHEN insufficient_privilege THEN NULL;END;
  PERFORM set_config('request.jwt.claims','{"role":"authenticated"}',true);
  BEGIN
    PERFORM public.obtener_reporte_ventas('2001-01-02','2001-01-04');RAISE EXCEPTION 'Aceptó usuario sin sesión';
  EXCEPTION WHEN insufficient_privilege THEN NULL;END;
  ASSERT NOT has_function_privilege('anon','public.obtener_reporte_ventas(date,date)','EXECUTE'),'RPC pública para anon';
END;
$test$;
ROLLBACK;
SELECT 'OK: totales, detalles, rankings, crédito, catálogo actual, fechas, días sin ventas y permisos. Fixtures revertidos.' AS resultado;
