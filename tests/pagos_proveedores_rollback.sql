-- Ejecutar completo como postgres. Los registros de prueba se revierten.
BEGIN;
SELECT set_config('test.usuario',(SELECT u.id_usuario::text FROM public.usuarios u JOIN public.roles r ON r.id_rol=u.rol_id WHERE u.activo AND r.nombre='ADMINISTRADOR' LIMIT 1),true);
WITH x AS (INSERT INTO public.categorias(nombre) VALUES('__TEST_PAGOS_CAT__') RETURNING id_categoria)
SELECT set_config('test.categoria',(SELECT id_categoria::text FROM x),true);
WITH x AS (INSERT INTO public.proveedores(nombre) VALUES('__TEST_PAGOS_PROV__') RETURNING id_proveedor)
SELECT set_config('test.proveedor',(SELECT id_proveedor::text FROM x),true);
WITH x AS (INSERT INTO public.productos(categoria_id,nombre,precio_venta) VALUES(current_setting('test.categoria')::integer,'__TEST_PAGOS_PRODUCTO__',7) RETURNING id_producto)
SELECT set_config('test.producto',(SELECT id_producto::text FROM x),true);
SELECT set_config('request.jwt.claims',json_build_object('sub',current_setting('test.usuario'),'role','authenticated')::text,true);
WITH x AS (
  SELECT public.registrar_compra(current_setting('test.proveedor')::integer,
    (SELECT id_forma_pago FROM public.formas_pago WHERE nombre='CREDITO'),
    'TEST-PAGOS-CREDITO',jsonb_build_array(jsonb_build_object('producto_id',current_setting('test.producto')::integer,'cantidad',10,'costo_unitario',5)),null) AS resp
)
SELECT set_config('test.compra',(SELECT resp->>'id_compra' FROM x),true);
-- La fecha vencida se prepara como fixture; el navegador no modifica cuentas.
UPDATE public.cuentas_por_pagar SET fecha_limite=(CURRENT_TIMESTAMP AT TIME ZONE 'America/Guatemala')::date-1
WHERE compra_id=current_setting('test.compra')::integer;
SET LOCAL ROLE authenticated;
DO $test$
DECLARE
  efectivo integer; credito integer; cuenta integer; resp jsonb; solicitud uuid:=gen_random_uuid();
  proveedor integer:=current_setting('test.proveedor')::integer;
  producto integer:=current_setting('test.producto')::integer;
  uid uuid:=auth.uid();
BEGIN
  SELECT id_forma_pago INTO STRICT efectivo FROM public.formas_pago WHERE nombre='EFECTIVO';
  SELECT id_forma_pago INTO STRICT credito FROM public.formas_pago WHERE nombre='CREDITO';
  SELECT id_cuenta_por_pagar INTO STRICT cuenta FROM public.cuentas_por_pagar WHERE compra_id=current_setting('test.compra')::integer;
  BEGIN
    UPDATE public.cuentas_por_pagar SET saldo_pendiente=0 WHERE id_cuenta_por_pagar=cuenta;
    RAISE EXCEPTION 'Permitió falsificar el saldo';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  resp:=public.registrar_abono_cxp(solicitud,cuenta,efectivo,12.50);
  ASSERT (resp->>'saldo_pendiente')::numeric=37.50 AND NOT (resp->>'repetida')::boolean,'Abono parcial incorrecto';
  resp:=public.registrar_abono_cxp(solicitud,cuenta,efectivo,12.50);
  ASSERT (resp->>'repetida')::boolean AND (resp->>'saldo_pendiente')::numeric=37.50,'No reconoció el reintento';
  ASSERT (SELECT count(*)=1 FROM public.pagos_cuentas_por_pagar WHERE cuenta_por_pagar_id=cuenta),'Duplicó el pago';
  BEGIN
    PERFORM public.registrar_abono_cxp(solicitud,cuenta,efectivo,13);
    RAISE EXCEPTION 'Permitió reutilizar referencia con otro monto';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  BEGIN
    PERFORM public.registrar_abono_cxp(gen_random_uuid(),cuenta,efectivo,38);
    RAISE EXCEPTION 'Aceptó sobrepago';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  BEGIN
    PERFORM public.registrar_abono_cxp(gen_random_uuid(),cuenta,credito,1);
    RAISE EXCEPTION 'Aceptó pago a crédito';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  BEGIN
    PERFORM public.registrar_abono_cxp(gen_random_uuid(),cuenta,efectivo,0);
    RAISE EXCEPTION 'Aceptó cero';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  BEGIN
    PERFORM public.registrar_abono_cxp(gen_random_uuid(),cuenta,efectivo,-1);
    RAISE EXCEPTION 'Aceptó negativo';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  BEGIN
    PERFORM public.registrar_abono_cxp(gen_random_uuid(),cuenta,efectivo,1.001);
    RAISE EXCEPTION 'Aceptó fracción de centavo';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  BEGIN
    PERFORM public.registrar_abono_cxp(gen_random_uuid(),cuenta,efectivo,'NaN'::numeric);
    RAISE EXCEPTION 'Aceptó NaN';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  ASSERT (SELECT saldo_pendiente=37.50 FROM public.cuentas_por_pagar WHERE id_cuenta_por_pagar=cuenta),'Cambió el saldo tras un rechazo';
  resp:=public.listar_proveedores_pagos('__TEST_PAGOS_PROV__',0);
  ASSERT (resp->>'total')::integer=1 AND (resp->'proveedores'->0->>'saldo')::numeric=37.50,'Lista incorrecta';
  ASSERT (resp->'proveedores'->0->>'vencido')::numeric=37.50,'Vencimiento incorrecto';
  resp:=public.obtener_pagos_proveedor(proveedor,0);
  ASSERT (resp->>'saldo')::numeric=37.50 AND (resp->>'vencido')::numeric=37.50 AND (resp->>'total')::integer=1,'Detalle incorrecto';
  ASSERT resp->'cuentas'->0->>'numero_documento'='TEST-PAGOS-CREDITO','Perdió referencia de compra';
  resp:=public.registrar_abono_cxp(gen_random_uuid(),cuenta,efectivo,37.50);
  ASSERT (resp->>'saldo_pendiente')::numeric=0,'No liquidó cuenta';
  ASSERT (SELECT estado='PAGADA' FROM public.cuentas_por_pagar WHERE id_cuenta_por_pagar=cuenta),'Estado final incorrecto';
  ASSERT (SELECT sum(monto)=50 AND count(*)=2 FROM public.pagos_cuentas_por_pagar WHERE cuenta_por_pagar_id=cuenta),'Total pagado incorrecto';
  ASSERT (SELECT existencia=10 FROM public.productos WHERE id_producto=producto),'El pago modificó el inventario';
  BEGIN
    PERFORM public.registrar_abono_cxp(gen_random_uuid(),cuenta,efectivo,1);
    RAISE EXCEPTION 'Aceptó abono a cuenta liquidada';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  PERFORM set_config('request.jwt.claims',json_build_object('sub',gen_random_uuid(),'role','authenticated')::text,true);
  BEGIN
    PERFORM public.registrar_abono_cxp(gen_random_uuid(),cuenta,efectivo,1);
    RAISE EXCEPTION 'Aceptó usuario sin perfil';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    PERFORM public.listar_proveedores_pagos('',0);
    RAISE EXCEPTION 'Filtró proveedores sin perfil';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM set_config('request.jwt.claims','{"role":"authenticated"}',true);
  BEGIN
    PERFORM public.obtener_pagos_proveedor(proveedor,0);
    RAISE EXCEPTION 'Permitió consultar sin sesión';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM set_config('request.jwt.claims',json_build_object('sub',uid,'role','authenticated')::text,true);
  ASSERT NOT has_function_privilege('anon','public.registrar_abono_cxp(uuid,integer,integer,numeric)','EXECUTE'),'RPC accesible a anon';
  ASSERT NOT has_function_privilege('anon','tienda_privada.registrar_abono_cxp(uuid,integer,integer,numeric)','EXECUTE'),'Implementación accesible a anon';
END;
$test$;
ROLLBACK;
SELECT 'OK: pagos parciales, reintentos, vencidos, liquidación, montos y permisos. Fixtures revertidos.' AS resultado;
