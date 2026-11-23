BEGIN;
SELECT set_config('test.admin',(SELECT u.id_usuario::text FROM public.usuarios u JOIN public.roles r ON r.id_rol=u.rol_id WHERE u.activo AND r.nombre='ADMINISTRADOR' LIMIT 1),true);
DO $estructura$
BEGIN
 ASSERT NOT EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='r' AND NOT c.relrowsecurity),'Hay una tabla sin RLS';
 ASSERT NOT has_function_privilege('anon','public.fn_tiene_rol(text[])','EXECUTE'),'Helper accesible sin sesión';
END;
$estructura$;
SET LOCAL ROLE anon;
DO $anon$
DECLARE t text; bloqueado boolean;
BEGIN
 FOREACH t IN ARRAY ARRAY['productos','clientes','proveedores','ventas','compras','caja_dias','reserva_saldo','reserva_eventos'] LOOP
  bloqueado:=false;
  BEGIN EXECUTE format('SELECT 1 FROM public.%I LIMIT 1',t);
  EXCEPTION WHEN insufficient_privilege THEN bloqueado:=true; END;
  ASSERT bloqueado,'Tabla accesible sin sesión: '||t;
 END LOOP;
END;
$anon$;
RESET ROLE;
SELECT set_config('request.jwt.claims',json_build_object('sub',gen_random_uuid(),'role','authenticated')::text,true);
SET LOCAL ROLE authenticated;
DO $sin_perfil$
DECLARE t text; n bigint;
BEGIN
 FOREACH t IN ARRAY ARRAY['roles','formas_pago','tipos_movimientos','categorias','productos','lotes','movimientos_inventario','clientes','proveedores','ventas','compras','caja_dias','reserva_saldo'] LOOP
  EXECUTE format('SELECT count(*) FROM public.%I',t) INTO n;
  ASSERT n=0,'Datos visibles sin perfil: '||t;
 END LOOP;
 BEGIN
  PERFORM public.obtener_reserva(0);
  RAISE EXCEPTION 'RPC permitió acceso sin perfil';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END;
$sin_perfil$;
RESET ROLE;
SELECT set_config('request.jwt.claims',json_build_object('sub',current_setting('test.admin'),'role','authenticated')::text,true);
SET LOCAL ROLE authenticated;
DO $admin$
BEGIN
 ASSERT public.fn_tiene_rol(ARRAY['ADMINISTRADOR']),'Se perdió el acceso administrador';
 ASSERT EXISTS(SELECT 1 FROM public.productos),'El administrador no ve el catálogo';
 PERFORM public.obtener_reserva(0);
 PERFORM public.obtener_caja_dia((CURRENT_TIMESTAMP AT TIME ZONE 'America/Guatemala')::date);
END;
$admin$;
RESET ROLE;
ROLLBACK;
