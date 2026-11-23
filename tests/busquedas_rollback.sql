-- Pruebas sin operaciones financieras. Ejecutar completo; revierte las filas.
BEGIN;
SELECT set_config('request.jwt.claims',json_build_object('sub',(SELECT u.id_usuario::text FROM public.usuarios u JOIN public.roles r ON r.id_rol=u.rol_id WHERE u.activo AND r.nombre='ADMINISTRADOR' LIMIT 1),'role','authenticated')::text,true);
DO $test$
DECLARE cat integer; pid integer; r jsonb; hoy date := (CURRENT_TIMESTAMP AT TIME ZONE 'America/Guatemala')::date;
BEGIN
  IF public.normalizar_busqueda('ÁÉÍÓÚÜ Ñ') <> 'aeiouu ñ'
    OR public.normalizar_busqueda(U&'Cajo\0301n') <> 'cajon' THEN RAISE EXCEPTION 'Normalización incorrecta'; END IF;
  INSERT INTO public.categorias(nombre) VALUES('__TEST_TILDES__') RETURNING id_categoria INTO cat;
  INSERT INTO public.productos(categoria_id,nombre,precio_venta,codigo_barras)
    VALUES(cat,'__TEST_TILDES_Cajón Café__',14,'001TILDES') RETURNING id_producto INTO pid;
  INSERT INTO public.clientes(nombre) VALUES('__TEST_TILDES_José__');
  INSERT INTO public.proveedores(nombre) VALUES('__TEST_TILDES_Ramón__');
  SET LOCAL ROLE authenticated;
  IF NOT EXISTS(SELECT 1 FROM public.productos WHERE id_producto=pid AND nombre_busqueda ILIKE '%cajon cafe%') THEN RAISE EXCEPTION 'Filtro catálogo'; END IF;
  r:=public.obtener_productos_inicial('cajon cafe','nombre');
  IF NOT r @> jsonb_build_array(jsonb_build_object('id_producto',pid)) THEN RAISE EXCEPTION 'Inicial'; END IF;
  r:=public.obtener_lista_compras('cajon cafe','nombre',false,0);
  IF NOT (r->'candidatos') @> jsonb_build_array(jsonb_build_object('id_producto',pid)) THEN RAISE EXCEPTION 'Lista'; END IF;
  r:=public.obtener_rotacion_productos(hoy,hoy,7,'cajon cafe','todos','reponer',0);
  IF NOT (r->'productos') @> jsonb_build_array(jsonb_build_object('id_producto',pid)) THEN RAISE EXCEPTION 'Rotación'; END IF;
  r:=public.listar_clientes_cobros('__TEST_TILDES_Jose__',0);
  IF (r->>'total')::integer<>1 THEN RAISE EXCEPTION 'Clientes'; END IF;
  r:=public.listar_proveedores_pagos('__TEST_TILDES_Ramon__',0);
  IF (r->>'total')::integer<>1 THEN RAISE EXCEPTION 'Proveedores'; END IF;
  r:=public.obtener_productos_inicial('001TILDES','codigo_barras');
  IF NOT r @> jsonb_build_array(jsonb_build_object('id_producto',pid)) THEN RAISE EXCEPTION 'Código completo'; END IF;
  r:=public.obtener_productos_inicial('1TILDES','codigo_barras');
  IF r <> '[]'::jsonb THEN RAISE EXCEPTION 'Código debe ser exacto'; END IF;
  RESET ROLE;
END;
$test$;
ROLLBACK;
