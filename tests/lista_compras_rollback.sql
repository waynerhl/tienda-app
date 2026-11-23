BEGIN;
SELECT set_config('test.usuario',(SELECT u.id_usuario::text FROM public.usuarios u JOIN public.roles r ON r.id_rol=u.rol_id WHERE u.activo AND r.nombre='ADMINISTRADOR' LIMIT 1),true);
SELECT set_config('request.jwt.claims',json_build_object('sub',current_setting('test.usuario'),'role','authenticated')::text,true);
DO $fixtures$
DECLARE v_cat integer;v_prov integer;v_a integer;v_b integer;v_c integer;v_tr integer;v_hoy date:=(CURRENT_TIMESTAMP AT TIME ZONE 'America/Guatemala')::date;v_codigo text:='00'||replace(gen_random_uuid()::text,'-','');
BEGIN
  INSERT INTO public.categorias(nombre) VALUES('__TEST_LISTA_CAT__') RETURNING id_categoria INTO v_cat;
  INSERT INTO public.proveedores(nombre) VALUES('__TEST_LISTA_PROV__') RETURNING id_proveedor INTO v_prov;
  INSERT INTO public.productos(categoria_id,nombre,codigo_barras,precio_venta,existencia_minima) VALUES(v_cat,'__TEST_LISTA_A__',v_codigo,5,5) RETURNING id_producto INTO v_a;
  INSERT INTO public.productos(categoria_id,nombre,precio_venta,existencia_minima,controla_lotes) VALUES(v_cat,'__TEST_LISTA_B__',5,3,true) RETURNING id_producto INTO v_b;
  INSERT INTO public.productos(categoria_id,nombre,precio_venta) VALUES(v_cat,'__TEST_LISTA_C__',5) RETURNING id_producto INTO v_c;
  SELECT id_forma_pago INTO v_tr FROM public.formas_pago WHERE nombre='TRANSFERENCIA';
  PERFORM public.registrar_compra(v_prov,v_tr,'TEST-LISTA-A',jsonb_build_array(jsonb_build_object('producto_id',v_a,'cantidad',2,'costo_unitario',2)),null);
  PERFORM public.registrar_compra(v_prov,v_tr,'TEST-LISTA-B',jsonb_build_array(jsonb_build_object('producto_id',v_b,'cantidad',5,'costo_unitario',2,'lotes',jsonb_build_array(jsonb_build_object('cantidad',4,'numero_lote','VENC','fecha_vencimiento',v_hoy+10),jsonb_build_object('cantidad',1,'numero_lote','VIG','fecha_vencimiento',v_hoy+20)))),null);
  UPDATE public.lotes SET fecha_ingreso=v_hoy-10,fecha_vencimiento=v_hoy-1 WHERE numero_lote='VENC' AND detalle_compra_id IN(SELECT id_detalle_compra FROM public.detalle_compras WHERE producto_id=v_b);
  PERFORM set_config('test.a',v_a::text,true);PERFORM set_config('test.b',v_b::text,true);PERFORM set_config('test.c',v_c::text,true);PERFORM set_config('test.codigo',v_codigo,true);
END;
$fixtures$;
SET LOCAL ROLE authenticated;
DO $test$
DECLARE v_a integer:=current_setting('test.a')::integer;v_b integer:=current_setting('test.b')::integer;v_c integer:=current_setting('test.c')::integer;v_uuid uuid:=gen_random_uuid();v_quitar uuid:=gen_random_uuid();v_r jsonb;v_item jsonb;
BEGIN
  v_r:=public.obtener_lista_compras('__TEST_LISTA_','nombre',true,0);
  SELECT x INTO v_item FROM jsonb_array_elements(v_r->'candidatos')x WHERE (x->>'id_producto')::integer=v_b;
  ASSERT (v_item->>'existencia')::integer=5 AND (v_item->>'disponible')::integer=1 AND (v_item->>'vencido')::integer=4 AND (v_item->>'cantidad_sugerida')::integer=3,'Sugerencia incluyó existencias vencidas';
  v_r:=public.actualizar_lista_compras(v_uuid,v_a,0,'GUARDAR',3,'Primera partida');
  ASSERT (v_r->>'version')::integer=1 AND (v_r->>'activo')::boolean,'No guardó partida';
  v_r:=public.actualizar_lista_compras(v_uuid,v_a,0,'GUARDAR',3,'Primera partida');
  ASSERT (v_r->>'repetida')::boolean AND (SELECT count(*)=1 FROM public.lista_compras WHERE producto_id=v_a),'Duplicó partida al reintentar';
  BEGIN
    PERFORM public.actualizar_lista_compras(v_uuid,v_a,0,'GUARDAR',4,'Primera partida');RAISE EXCEPTION 'Aceptó referencia con otros datos';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
  BEGIN
    PERFORM public.actualizar_lista_compras(gen_random_uuid(),v_a,0,'GUARDAR',5,'Otro dispositivo');RAISE EXCEPTION 'Sobrescribió versión antigua';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
  PERFORM public.actualizar_lista_compras(gen_random_uuid(),v_a,1,'GUARDAR',4,'Cantidad revisada');
  PERFORM public.actualizar_lista_compras(gen_random_uuid(),v_c,0,'GUARDAR',2,'Sin costo conocido');
  v_r:=public.obtener_lista_compras(current_setting('test.codigo'),'codigo_barras',false,0);
  ASSERT (v_r->>'total_candidatos')::integer=1,'No buscó código exacto';
  ASSERT (SELECT count(*)=2 FROM jsonb_array_elements(v_r->'lista')x WHERE (x->>'id_producto')::integer IN(v_a,v_c)),'La búsqueda ocultó partidas de la lista guardada';
  ASSERT (v_r->>'sin_costo')::integer>=1,'No señaló costo desconocido';
  PERFORM public.actualizar_lista_compras(v_quitar,v_a,2,'QUITAR',null,'');
  v_r:=public.actualizar_lista_compras(v_quitar,v_a,2,'QUITAR',null,'');
  ASSERT (v_r->>'repetida')::boolean AND (SELECT NOT activo AND version=3 FROM public.lista_compras WHERE producto_id=v_a),'No reconoció reintento de quitar';
  PERFORM public.actualizar_lista_compras(gen_random_uuid(),v_a,3,'GUARDAR',6,'Volver a planificar');
  v_r:=public.obtener_lista_compras('__TEST_LISTA_','nombre',false,0);
  SELECT x INTO v_item FROM jsonb_array_elements(v_r->'lista')x WHERE (x->>'id_producto')::integer=v_a;
  ASSERT (v_item->>'cantidad')::integer=6 AND (v_item->>'subtotal_estimado')::numeric=12,'Presupuesto o cantidad incorrectos';
  ASSERT (SELECT existencia=2 AND ultimo_costo=2 FROM public.productos WHERE id_producto=v_a),'La lista cambió stock o costo';
  BEGIN
    PERFORM public.actualizar_lista_compras(gen_random_uuid(),v_a,4,'GUARDAR',0,'Cero');RAISE EXCEPTION 'Aceptó cantidad cero';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
  UPDATE public.productos SET activo=false WHERE id_producto=v_a;
  BEGIN
    PERFORM public.actualizar_lista_compras(gen_random_uuid(),v_a,4,'GUARDAR',7,'Inactivo');RAISE EXCEPTION 'Guardó producto inactivo';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
  PERFORM public.actualizar_lista_compras(gen_random_uuid(),v_a,4,'QUITAR',null,'');
  BEGIN
    UPDATE public.lista_compras SET cantidad=500 WHERE producto_id=v_c;RAISE EXCEPTION 'Permitió modificar lista directamente';
  EXCEPTION WHEN insufficient_privilege THEN NULL;END;
  PERFORM set_config('request.jwt.claims','{"role":"authenticated"}',true);
  BEGIN
    PERFORM public.obtener_lista_compras('', 'nombre',true,0);RAISE EXCEPTION 'Consultó sin sesión';
  EXCEPTION WHEN insufficient_privilege THEN NULL;END;
  BEGIN
    PERFORM public.actualizar_lista_compras(gen_random_uuid(),v_c,1,'QUITAR',null,'');RAISE EXCEPTION 'Modificó sin sesión';
  EXCEPTION WHEN insufficient_privilege THEN NULL;END;
  ASSERT NOT has_function_privilege('anon','public.actualizar_lista_compras(uuid,integer,integer,text,integer,text)','EXECUTE'),'RPC pública para anon';
END;
$test$;
ROLLBACK;
SELECT 'OK: sugerencias, vencidos, lista compartida, versiones, reintentos, costo desconocido y permisos. Fixtures revertidos.' AS resultado;
