-- Ejecutar completo como postgres. Los datos de prueba se revierten al finalizar.
BEGIN;
SELECT set_config('test.usuario',(SELECT u.id_usuario::text FROM public.usuarios u JOIN public.roles r ON r.id_rol=u.rol_id WHERE u.activo AND r.nombre='ADMINISTRADOR' LIMIT 1),true);
SELECT set_config('request.jwt.claims',json_build_object('sub',current_setting('test.usuario'),'role','authenticated')::text,true);
DO $fixtures$
DECLARE cat integer;prov integer;tr integer;a integer;b integer;c integer;d integer;e integer;fuera integer;r jsonb;hoy date:=(CURRENT_TIMESTAMP AT TIME ZONE 'America/Guatemala')::date;
BEGIN
  INSERT INTO public.categorias(nombre) VALUES('__TEST_ROT_CAT__') RETURNING id_categoria INTO cat;
  INSERT INTO public.proveedores(nombre) VALUES('__TEST_ROT_PROV__') RETURNING id_proveedor INTO prov;
  SELECT id_forma_pago INTO tr FROM public.formas_pago WHERE nombre='TRANSFERENCIA';
  INSERT INTO public.productos(categoria_id,nombre,precio_venta,existencia_minima,codigo_barras) VALUES(cat,'__TEST_ROT_A__',5,5,'00'||replace(gen_random_uuid()::text,'-','')) RETURNING id_producto INTO a;
  INSERT INTO public.productos(categoria_id,nombre,precio_venta,existencia_minima,controla_lotes) VALUES(cat,'__TEST_ROT_B__',5,1,true) RETURNING id_producto INTO b;
  INSERT INTO public.productos(categoria_id,nombre,precio_venta) VALUES(cat,'__TEST_ROT_C__',5) RETURNING id_producto INTO c;
  INSERT INTO public.productos(categoria_id,nombre,precio_venta,controla_lotes,existencia) VALUES(cat,'__TEST_ROT_D__',5,true,2) RETURNING id_producto INTO d;
  INSERT INTO public.productos(categoria_id,nombre,precio_venta) VALUES(cat,'__TEST_ROT_E__',0) RETURNING id_producto INTO e;
  INSERT INTO public.productos(categoria_id,nombre,precio_venta) VALUES(cat,'__TEST_ROT_FUERA__',5) RETURNING id_producto INTO fuera;
  PERFORM public.registrar_compra(prov,tr,'TEST-ROT',jsonb_build_array(
    jsonb_build_object('producto_id',a,'cantidad',10,'costo_unitario',2),
    jsonb_build_object('producto_id',b,'cantidad',10,'costo_unitario',2,'lotes',jsonb_build_array(jsonb_build_object('cantidad',6,'numero_lote','ROT-VENC','fecha_vencimiento',hoy+20),jsonb_build_object('cantidad',4,'numero_lote','ROT-VIG','fecha_vencimiento',hoy+10))),
    jsonb_build_object('producto_id',e,'cantidad',1,'costo_unitario',0),
    jsonb_build_object('producto_id',fuera,'cantidad',8,'costo_unitario',1)),null);
  r:=public.registrar_venta(null,tr,jsonb_build_array(jsonb_build_object('producto_id',a,'cantidad',6),jsonb_build_object('producto_id',b,'cantidad',2),jsonb_build_object('producto_id',e,'cantidad',1)),null);
  UPDATE public.ventas SET fecha='2002-02-01T06:00:00Z' WHERE id_venta=(r->>'id_venta')::integer;
  UPDATE public.lotes SET fecha_ingreso=hoy-10,fecha_vencimiento=hoy-1 WHERE numero_lote='ROT-VENC' AND detalle_compra_id IN(SELECT id_detalle_compra FROM public.detalle_compras WHERE producto_id=b);
  -- Último segundo del período, fuera antes/después y documento incongruente.
  r:=public.registrar_venta(null,tr,jsonb_build_array(jsonb_build_object('producto_id',fuera,'cantidad',1)),null);
  UPDATE public.ventas SET fecha='2002-02-04T05:59:59Z' WHERE id_venta=(r->>'id_venta')::integer;
  r:=public.registrar_venta(null,tr,jsonb_build_array(jsonb_build_object('producto_id',fuera,'cantidad',1)),null);
  UPDATE public.ventas SET fecha='2002-02-01T05:59:59Z' WHERE id_venta=(r->>'id_venta')::integer;
  r:=public.registrar_venta(null,tr,jsonb_build_array(jsonb_build_object('producto_id',fuera,'cantidad',1)),null);
  UPDATE public.ventas SET fecha='2002-02-04T06:00:00Z' WHERE id_venta=(r->>'id_venta')::integer;
  r:=public.registrar_venta(null,tr,jsonb_build_array(jsonb_build_object('producto_id',fuera,'cantidad',1)),null);
  UPDATE public.ventas SET fecha='2002-02-02T18:00:00Z',total=99 WHERE id_venta=(r->>'id_venta')::integer;
  r:=public.registrar_venta(null,tr,jsonb_build_array(jsonb_build_object('producto_id',fuera,'cantidad',1)),null);
  UPDATE public.ventas SET fecha='2002-02-02T18:00:00Z',estado='ANULADA' WHERE id_venta=(r->>'id_venta')::integer;
  INSERT INTO public.ventas(usuario_id,forma_pago_id,fecha,total,estado) VALUES(auth.uid(),tr,'2002-02-02T18:00:00Z',50,'REGISTRADA');
  INSERT INTO public.productos(categoria_id,nombre,precio_venta) SELECT cat,'__TEST_ROT_PAGE_'||lpad(i::text,2,'0'),1 FROM generate_series(1,23)i;
  INSERT INTO public.productos(categoria_id,nombre,precio_venta,activo) VALUES(cat,'__TEST_ROT_INACTIVO__',5,false);
  PERFORM set_config('test.a',a::text,true);PERFORM set_config('test.b',b::text,true);PERFORM set_config('test.d',d::text,true);PERFORM set_config('test.e',e::text,true);PERFORM set_config('test.fuera',fuera::text,true);
END;
$fixtures$;
SET LOCAL ROLE authenticated;
DO $test$
DECLARE r jsonb;i jsonb;a integer:=current_setting('test.a')::integer;antes integer;
BEGIN
  SELECT existencia INTO antes FROM public.productos WHERE id_producto=a;
  r:=public.obtener_rotacion_productos('2002-02-01','2002-02-03',7,'__TEST_ROT_A__','todos','mas',0);
  i:=r->'productos'->0;
  ASSERT (r->>'dias')::integer=3 AND (r->>'total')::integer=1,'Período o búsqueda incorrectos';
  ASSERT (i->>'unidades')::integer=6 AND (i->>'importe')::numeric=30 AND (i->>'promedio_diario')::numeric=2,'Duplicó cantidades o no contó días sin ventas';
  ASSERT (i->>'disponible')::integer=4 AND (i->>'cobertura_dias')::numeric=2 AND (i->>'sugerencia')::integer=10,'Cobertura u objetivo incorrectos';
  ASSERT (r->>'ventas_excluidas')::integer=2,'No excluyó venta incongruente o sin detalles';
  r:=public.obtener_rotacion_productos('2002-02-01','2002-02-03',1,(SELECT codigo_barras FROM public.productos WHERE id_producto=a),'todos','mas',0);
  ASSERT (r->>'total')::integer=1 AND (r->'productos'->0->>'sugerencia')::integer=2,'No conserva código o mínimo+1';
  r:=public.obtener_rotacion_productos('2002-02-01','2002-02-03',7,'__TEST_ROT_B__');i:=r->'productos'->0;
  ASSERT (i->>'existencia')::integer=8 AND (i->>'disponible')::integer=2 AND (i->>'vencido')::integer=6,'Incluyó vencidos';
  ASSERT (i->>'sugerencia')::integer=3 AND (i->>'cobertura_dias')::numeric=3,'Redondeó el promedio antes de calcular';
  r:=public.obtener_rotacion_productos('2002-02-01','2002-02-03',7,'__TEST_ROT_C__','sin_ventas');i:=r->'productos'->0;
  ASSERT i->>'estado'='SIN_VENTAS' AND i->'cobertura_dias'='null'::jsonb AND i->'sugerencia'='null'::jsonb AND (i->>'bajo_minimo')::boolean,'Inventó demanda sin ventas';
  r:=public.obtener_rotacion_productos('2002-02-01','2002-02-03',7,'__TEST_ROT_D__','revisar');i:=r->'productos'->0;
  ASSERT i->>'estado'='REVISAR' AND i->'sugerencia'='null'::jsonb AND i->'cobertura_dias'='null'::jsonb,'Calculó con inventario incoherente';
  r:=public.obtener_rotacion_productos('2002-02-01','2002-02-03',7,'__TEST_ROT_E__');i:=r->'productos'->0;
  ASSERT (i->>'unidades')::integer=1 AND (i->>'importe')::numeric=0 AND (i->>'cobertura_dias')::numeric=0 AND (i->>'sugerencia')::integer=3,'Venta gratuita, cero disponible o redondeo incorrecto';
  r:=public.obtener_rotacion_productos('2002-02-01','2002-02-03',7,'__TEST_ROT_FUERA__');
  ASSERT (r->'productos'->0->>'unidades')::integer=1,'Incluyó anuladas o fechas fuera del horario de Guatemala';
  r:=public.obtener_rotacion_productos('2002-02-01','2002-02-03',7,'__TEST_ROT_PAGE_','todos','menos',0);
  ASSERT (r->>'total')::integer=23 AND jsonb_array_length(r->'productos')=20,'Total incompleto o página sin límite';
  r:=public.obtener_rotacion_productos('2002-02-01','2002-02-03',7,'__TEST_ROT_PAGE_','todos','menos',1);
  ASSERT jsonb_array_length(r->'productos')=3 AND r->'productos'->0->>'nombre'='__TEST_ROT_PAGE_21','Orden de página inestable';
  r:=public.obtener_rotacion_productos('2002-02-01','2002-02-03',7,'__TEST_ROT_INACTIVO__');
  ASSERT (r->>'total')::integer=0,'Incluyó catálogo inactivo';
  ASSERT (SELECT existencia=antes FROM public.productos WHERE id_producto=a),'La lectura modificó existencias';
  BEGIN PERFORM public.obtener_rotacion_productos('2002-02-03','2002-02-01');RAISE EXCEPTION 'Aceptó fechas invertidas';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
  BEGIN PERFORM public.obtener_rotacion_productos('2000-01-01','2001-01-01');RAISE EXCEPTION 'Aceptó más de 366 días';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
  BEGIN PERFORM public.obtener_rotacion_productos('2002-02-01','2002-02-03',0);RAISE EXCEPTION 'Aceptó objetivo cero';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
  BEGIN PERFORM public.obtener_rotacion_productos('2002-02-01','2002-02-03',91);RAISE EXCEPTION 'Aceptó objetivo >90';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
  BEGIN PERFORM public.obtener_rotacion_productos('2002-02-01','2002-02-03',7,'','otro');RAISE EXCEPTION 'Aceptó filtro ajeno';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
  PERFORM set_config('request.jwt.claims',json_build_object('sub',gen_random_uuid(),'role','authenticated')::text,true);
  BEGIN PERFORM public.obtener_rotacion_productos('2002-02-01','2002-02-03');RAISE EXCEPTION 'Aceptó usuario sin perfil';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
  PERFORM set_config('request.jwt.claims','{"role":"authenticated"}',true);
  BEGIN PERFORM public.obtener_rotacion_productos('2002-02-01','2002-02-03');RAISE EXCEPTION 'Aceptó lectura sin sesión';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
  ASSERT NOT has_function_privilege('anon','public.obtener_rotacion_productos(date,date,integer,text,text,text,integer)','EXECUTE'),'Permitió acceso anon';
END;
$test$;
ROLLBACK;
SELECT 'OK: rotación, mínimos, días, redondeo, lotes vencidos, consistencia, límites GT, páginas y permisos. Fixtures revertidos.' AS resultado;
