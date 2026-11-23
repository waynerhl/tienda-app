-- Ejecutar completo como postgres. Fixtures y ajustes se revierten al terminar.
BEGIN;
SELECT set_config('test.usuario',(SELECT u.id_usuario::text FROM public.usuarios u JOIN public.roles r ON r.id_rol=u.rol_id WHERE u.activo AND r.nombre='ADMINISTRADOR' LIMIT 1),true);
SELECT set_config('request.jwt.claims',json_build_object('sub',current_setting('test.usuario'),'role','authenticated')::text,true);
DO $fixtures$
DECLARE cat integer; prov integer; prod integer; v_lotes integer; paginado integer; tr integer; r jsonb; hoy date:=(CURRENT_TIMESTAMP AT TIME ZONE 'America/Guatemala')::date;
BEGIN
  INSERT INTO public.categorias(nombre) VALUES('__TEST_INV_CAT__') RETURNING id_categoria INTO cat;
  INSERT INTO public.proveedores(nombre) VALUES('__TEST_INV_PROV__') RETURNING id_proveedor INTO prov;
  INSERT INTO public.productos(categoria_id,nombre,precio_venta) VALUES(cat,'__TEST_INV_PRODUCTO__',7) RETURNING id_producto INTO prod;
  INSERT INTO public.productos(categoria_id,nombre,precio_venta,controla_lotes) VALUES(cat,'__TEST_INV_LOTES__',7,true) RETURNING id_producto INTO v_lotes;
  INSERT INTO public.productos(categoria_id,nombre,precio_venta,controla_lotes) VALUES(cat,'__TEST_INV_PAGINADO__',7,true) RETURNING id_producto INTO paginado;
  SELECT id_forma_pago INTO tr FROM public.formas_pago WHERE nombre='TRANSFERENCIA';
  PERFORM public.registrar_compra(prov,tr,'TEST-INV-SIMPLE',jsonb_build_array(jsonb_build_object('producto_id',prod,'cantidad',10,'costo_unitario',2)),null);
  PERFORM public.registrar_compra(prov,tr,'TEST-INV-LOTES',jsonb_build_array(jsonb_build_object('producto_id',v_lotes,'cantidad',10,'costo_unitario',2,'lotes',jsonb_build_array(jsonb_build_object('cantidad',4,'numero_lote','VENC','fecha_vencimiento',hoy+30),jsonb_build_object('cantidad',6,'numero_lote','VIG','fecha_vencimiento',hoy+60)))),null);
  UPDATE public.lotes SET fecha_ingreso=hoy-10,fecha_vencimiento=hoy-1 WHERE numero_lote='VENC' AND detalle_compra_id IN(SELECT id_detalle_compra FROM public.detalle_compras WHERE producto_id=v_lotes);
  PERFORM public.registrar_compra(prov,tr,'TEST-INV-PAGINADO',jsonb_build_array(jsonb_build_object('producto_id',paginado,'cantidad',21,'costo_unitario',1,'lotes',(SELECT jsonb_agg(jsonb_build_object('cantidad',1,'numero_lote','P'||i,'fecha_vencimiento',hoy+30)) FROM generate_series(1,21)i))),null);
  PERFORM set_config('test.producto',prod::text,true);PERFORM set_config('test.lotes',v_lotes::text,true);PERFORM set_config('test.paginado',paginado::text,true);
  PERFORM set_config('test.vencido',(SELECT l.id_lote::text FROM public.lotes l JOIN public.detalle_compras d ON d.id_detalle_compra=l.detalle_compra_id WHERE d.producto_id=v_lotes AND l.numero_lote='VENC'),true);
  PERFORM set_config('test.vigente',(SELECT l.id_lote::text FROM public.lotes l JOIN public.detalle_compras d ON d.id_detalle_compra=l.detalle_compra_id WHERE d.producto_id=v_lotes AND l.numero_lote='VIG'),true);
END;
$fixtures$;
SET LOCAL ROLE authenticated;
DO $test$
DECLARE
  prod integer:=current_setting('test.producto')::integer; lp integer:=current_setting('test.lotes')::integer;
  venc integer:=current_setting('test.vencido')::integer; vig integer:=current_setting('test.vigente')::integer;
  solicitud uuid:=gen_random_uuid(); r jsonb; antes bigint; v_compras bigint; v_ventas bigint;
BEGIN
  SELECT count(*) INTO v_compras FROM public.compras;SELECT count(*) INTO v_ventas FROM public.ventas;
  r:=public.registrar_ajuste_inventario(solicitud,prod,null,'CONTEO',8,10,'Conteo físico de prueba');
  ASSERT (r->>'variacion')::integer=-2 AND (r->>'producto_nuevo')::integer=8,'Conteo incorrecto';
  r:=public.registrar_ajuste_inventario(solicitud,prod,null,'CONTEO',8,10,'Conteo físico de prueba');
  ASSERT (r->>'repetida')::boolean AND (SELECT existencia=8 FROM public.productos WHERE id_producto=prod),'Duplicó el ajuste';
  BEGIN
    PERFORM public.registrar_ajuste_inventario(solicitud,prod,null,'CONTEO',7,10,'Conteo físico de prueba');
    RAISE EXCEPTION 'Reutilizó UUID con otros parámetros';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  BEGIN
    PERFORM public.registrar_ajuste_inventario(gen_random_uuid(),prod,null,'CONTEO',7,10,'Conteo desactualizado');
    RAISE EXCEPTION 'Sobrescribió stock cambiado';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  SELECT count(*) INTO antes FROM public.movimientos_inventario WHERE producto_id=prod;
  r:=public.registrar_ajuste_inventario(gen_random_uuid(),prod,null,'CONTEO',8,8,'Conteo coincidente');
  ASSERT (r->>'variacion')::integer=0 AND r->'movimiento_id'='null'::jsonb,'Creó movimiento para conteo coincidente';
  ASSERT (SELECT count(*)=antes FROM public.movimientos_inventario WHERE producto_id=prod),'Movió stock sin diferencia';
  PERFORM public.registrar_ajuste_inventario(gen_random_uuid(),prod,null,'AJUSTE_POSITIVO',3,8,'Corregir entrada');
  PERFORM public.registrar_ajuste_inventario(gen_random_uuid(),prod,null,'PERDIDA',2,11,'Unidades dañadas');
  PERFORM public.registrar_ajuste_inventario(gen_random_uuid(),prod,null,'AJUSTE_NEGATIVO',1,9,'Corregir salida');
  ASSERT (SELECT existencia=8 AND ultimo_costo=2 FROM public.productos WHERE id_producto=prod),'Alteró costo o existencia';
  BEGIN
    PERFORM public.registrar_ajuste_inventario(gen_random_uuid(),prod,null,'PERDIDA',9,8,'Más de lo disponible');
    RAISE EXCEPTION 'Permitió stock negativo';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  BEGIN
    PERFORM public.registrar_ajuste_inventario(gen_random_uuid(),prod,null,'AJUSTE_POSITIVO',2147483647,8,'Desborde');
    RAISE EXCEPTION 'Permitió desborde';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  BEGIN
    PERFORM public.registrar_ajuste_inventario(gen_random_uuid(),prod,null,'VENCIMIENTO',1,8,'Sin fecha de lote');
    RAISE EXCEPTION 'Retiró vencimiento sin lote';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  BEGIN
    PERFORM public.registrar_ajuste_inventario(gen_random_uuid(),lp,null,'PERDIDA',1,10,'Sin lote');
    RAISE EXCEPTION 'Permitió ajuste global de producto con lotes';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  BEGIN
    PERFORM public.registrar_ajuste_inventario(gen_random_uuid(),prod,venc,'PERDIDA',1,8,'Lote ajeno');
    RAISE EXCEPTION 'Aceptó lote ajeno';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  PERFORM public.registrar_ajuste_inventario(gen_random_uuid(),lp,venc,'VENCIMIENTO',2,4,'Retiro físico de vencidos');
  ASSERT public.fn_stock_lote(venc)=2 AND (SELECT existencia=8 FROM public.productos WHERE id_producto=lp),'Baja de vencidos incorrecta';
  BEGIN
    PERFORM public.registrar_ajuste_inventario(gen_random_uuid(),lp,vig,'VENCIMIENTO',1,6,'Vigente');
    RAISE EXCEPTION 'Permitió vencimiento de lote vigente';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  PERFORM public.registrar_ajuste_inventario(gen_random_uuid(),lp,venc,'CONTEO',0,2,'Lote retirado por completo');
  ASSERT public.fn_stock_lote(venc)=0 AND (SELECT existencia=6 FROM public.productos WHERE id_producto=lp),'Conteo por lote incorrecto';
  PERFORM public.registrar_ajuste_inventario(gen_random_uuid(),lp,venc,'AJUSTE_POSITIVO',1,0,'Unidad vencida encontrada físicamente');
  PERFORM public.registrar_ajuste_inventario(gen_random_uuid(),lp,venc,'VENCIMIENTO',1,1,'Retiro físico de la unidad encontrada');
  PERFORM public.registrar_ajuste_inventario(gen_random_uuid(),lp,vig,'CONTEO',7,6,'Una unidad adicional en conteo');
  ASSERT (SELECT existencia=7 FROM public.productos WHERE id_producto=lp) AND public.fn_stock_lote(vig)=7,'No conservó sumatoria de lotes';
  r:=public.obtener_inventario_producto(lp,0);
  ASSERT (r->>'suma_lotes')::integer=7 AND (r->>'total_lotes')::integer=2 AND jsonb_array_length(r->'lotes')=2,'Consulta de lotes incorrecta';
  r:=public.obtener_inventario_producto(current_setting('test.paginado')::integer,1);
  ASSERT (r->>'total_lotes')::integer=21 AND jsonb_array_length(r->'lotes')=1 AND (r->>'suma_lotes')::integer=21,'Paginación de lotes incorrecta';
  UPDATE public.productos SET activo=false WHERE id_producto=prod;
  PERFORM public.registrar_ajuste_inventario(gen_random_uuid(),prod,null,'CONTEO',8,8,'Conteo de producto inactivo');
  ASSERT (SELECT count(*)=v_compras FROM public.compras) AND (SELECT count(*)=v_ventas FROM public.ventas),'El ajuste creó documentos comerciales';
  BEGIN
    UPDATE public.productos SET existencia=500 WHERE id_producto=prod;
    RAISE EXCEPTION 'Permitió alterar stock directo';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM set_config('request.jwt.claims',json_build_object('sub',gen_random_uuid(),'role','authenticated')::text,true);
  BEGIN
    PERFORM public.registrar_ajuste_inventario(gen_random_uuid(),prod,null,'CONTEO',8,8,'Sin perfil');
    RAISE EXCEPTION 'Aceptó usuario sin perfil';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM set_config('request.jwt.claims','{"role":"authenticated"}',true);
  BEGIN
    PERFORM public.obtener_inventario_producto(prod,0);
    RAISE EXCEPTION 'Aceptó consulta sin sesión';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  ASSERT NOT has_function_privilege('anon','public.registrar_ajuste_inventario(uuid,integer,integer,text,integer,integer,text)','EXECUTE'),'RPC pública para anon';
END;
$test$;
ROLLBACK;
SELECT 'OK: conteos, reintentos, existencias cambiadas, pérdidas, lotes, vencimientos, paginación y permisos. Fixtures revertidos.' AS resultado;
