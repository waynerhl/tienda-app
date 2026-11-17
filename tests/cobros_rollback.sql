-- Prueba como postgres en SQL Editor. Todos los fixtures se revierten.
BEGIN;
SELECT set_config('test.usuario',(SELECT u.id_usuario::text FROM public.usuarios u JOIN public.roles r ON r.id_rol=u.rol_id WHERE u.activo AND r.nombre='ADMINISTRADOR' LIMIT 1),true);
WITH x AS (INSERT INTO public.categorias(nombre) VALUES('__TEST_COBROS_CAT__') RETURNING id_categoria)
SELECT set_config('test.categoria',(SELECT id_categoria::text FROM x),true);
WITH x AS (INSERT INTO public.proveedores(nombre) VALUES('__TEST_COBROS_PROV__') RETURNING id_proveedor)
SELECT set_config('test.proveedor',(SELECT id_proveedor::text FROM x),true);
WITH x AS (INSERT INTO public.productos(categoria_id,nombre,precio_venta) VALUES(current_setting('test.categoria')::integer,'__TEST_COBROS_PRODUCTO__',5) RETURNING id_producto)
SELECT set_config('test.producto',(SELECT id_producto::text FROM x),true);
WITH x AS (INSERT INTO public.clientes(nombre,limite_credito) VALUES('__TEST_COBROS_CLIENTE__',100) RETURNING id_cliente)
SELECT set_config('test.cliente',(SELECT id_cliente::text FROM x),true);
SELECT set_config('request.jwt.claims',json_build_object('sub',current_setting('test.usuario'),'role','authenticated')::text,true);
SET LOCAL ROLE authenticated;
DO $test$
DECLARE
  efectivo integer; credito integer; cuenta integer; resp jsonb; solicitud uuid:=gen_random_uuid();
  cliente integer:=current_setting('test.cliente')::integer;
  producto integer:=current_setting('test.producto')::integer;
  uid uuid:=auth.uid();
BEGIN
  SELECT id_forma_pago INTO STRICT efectivo FROM public.formas_pago WHERE nombre='EFECTIVO';
  SELECT id_forma_pago INTO STRICT credito FROM public.formas_pago WHERE nombre='CREDITO';
  PERFORM public.registrar_compra(current_setting('test.proveedor')::integer,efectivo,'TEST-COBROS',jsonb_build_array(jsonb_build_object('producto_id',producto,'cantidad',50,'costo_unitario',1)),null);
  resp:=public.registrar_venta(cliente,credito,jsonb_build_array(jsonb_build_object('producto_id',producto,'cantidad',10)),null);
  SELECT id_cuenta_por_cobrar INTO STRICT cuenta FROM public.cuentas_por_cobrar WHERE venta_id=(resp->>'id_venta')::integer;
  PERFORM set_config('test.cuenta',cuenta::text,true);
  -- El usuario no puede falsificar saldos mediante UPDATE directo.
  BEGIN
    UPDATE public.cuentas_por_cobrar SET saldo_pendiente=0 WHERE id_cuenta_por_cobrar=cuenta;
    RAISE EXCEPTION 'Permitió modificar el saldo directo';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  resp:=public.registrar_abono_cxc(solicitud,cuenta,efectivo,12.50);
  ASSERT (resp->>'saldo_pendiente')::numeric=37.50 AND NOT (resp->>'repetida')::boolean,'Abono parcial incorrecto';
  resp:=public.registrar_abono_cxc(solicitud,cuenta,efectivo,12.50);
  ASSERT (resp->>'repetida')::boolean AND (resp->>'saldo_pendiente')::numeric=37.50,'Reintento no fue idempotente';
  ASSERT (SELECT count(*)=1 FROM public.pagos_cuentas_por_cobrar WHERE cuenta_por_cobrar_id=cuenta),'Duplicó el abono';
  BEGIN
    PERFORM public.registrar_abono_cxc(solicitud,cuenta,efectivo,13);
    RAISE EXCEPTION 'Aceptó reutilizar UUID con otro monto';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  BEGIN
    PERFORM public.registrar_abono_cxc(gen_random_uuid(),cuenta,efectivo,38);
    RAISE EXCEPTION 'Aceptó sobrepago';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  BEGIN
    PERFORM public.registrar_abono_cxc(gen_random_uuid(),cuenta,credito,1);
    RAISE EXCEPTION 'Aceptó abono a crédito';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  BEGIN
    PERFORM public.registrar_abono_cxc(gen_random_uuid(),cuenta,efectivo,0);
    RAISE EXCEPTION 'Aceptó cero';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  BEGIN
    PERFORM public.registrar_abono_cxc(gen_random_uuid(),cuenta,efectivo,-1);
    RAISE EXCEPTION 'Aceptó negativo';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  BEGIN
    PERFORM public.registrar_abono_cxc(gen_random_uuid(),cuenta,efectivo,1.001);
    RAISE EXCEPTION 'Aceptó fracción de centavo';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  BEGIN
    PERFORM public.registrar_abono_cxc(gen_random_uuid(),cuenta,efectivo,'NaN'::numeric);
    RAISE EXCEPTION 'Aceptó NaN';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  ASSERT (SELECT saldo_pendiente=37.50 FROM public.cuentas_por_cobrar WHERE id_cuenta_por_cobrar=cuenta),'Un rechazo cambió el saldo';
  resp:=public.listar_clientes_cobros('__TEST_COBROS_CLIENTE__',0);
  ASSERT (resp->>'total')::integer=1 AND (resp->'clientes'->0->>'saldo')::numeric=37.50,'Lista de saldos incorrecta';
  resp:=public.obtener_cobros_cliente(cliente,0);
  ASSERT (resp->>'saldo')::numeric=37.50 AND (resp->>'total')::integer=1,'Detalle incorrecto';
  -- Disminuir el límite no perdona la deuda ni bloquea los abonos.
  UPDATE public.clientes SET limite_credito=0 WHERE id_cliente=cliente;
  resp:=public.registrar_abono_cxc(gen_random_uuid(),cuenta,efectivo,25);
  ASSERT (resp->>'saldo_pendiente')::numeric=12.50,'Bloqueó abono tras bajar límite';
  resp:=public.registrar_abono_cxc(gen_random_uuid(),cuenta,efectivo,12.50);
  ASSERT (resp->>'saldo_pendiente')::numeric=0,'No liquidó cuenta';
  ASSERT (SELECT estado='PAGADA' FROM public.cuentas_por_cobrar WHERE id_cuenta_por_cobrar=cuenta),'Estado final incorrecto';
  ASSERT (SELECT sum(monto)=50 AND count(*)=3 FROM public.pagos_cuentas_por_cobrar WHERE cuenta_por_cobrar_id=cuenta),'Total de pagos incorrecto';
  BEGIN
    PERFORM public.registrar_abono_cxc(gen_random_uuid(),cuenta,efectivo,1);
    RAISE EXCEPTION 'Aceptó abono a cuenta liquidada';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  PERFORM set_config('request.jwt.claims',json_build_object('sub',gen_random_uuid(),'role','authenticated')::text,true);
  BEGIN
    PERFORM public.registrar_abono_cxc(gen_random_uuid(),cuenta,efectivo,1);
    RAISE EXCEPTION 'Permitió usuario sin perfil';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    PERFORM public.listar_clientes_cobros('',0);
    RAISE EXCEPTION 'Filtró clientes sin perfil';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM set_config('request.jwt.claims','{"role":"authenticated"}',true);
  BEGIN
    PERFORM public.obtener_cobros_cliente(cliente,0);
    RAISE EXCEPTION 'Permitió consultar sin sesión';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM set_config('request.jwt.claims',json_build_object('sub',uid,'role','authenticated')::text,true);
  ASSERT NOT has_function_privilege('anon','public.registrar_abono_cxc(uuid,integer,integer,numeric)','EXECUTE'),'RPC accesible a anon';
  ASSERT NOT has_function_privilege('anon','tienda_privada.registrar_abono_cxc(uuid,integer,integer,numeric)','EXECUTE'),'Implementación accesible a anon';
END;
$test$;
ROLLBACK;
SELECT 'OK: parcial, reintento, sobrepago, liquidación, validación y permisos. Fixtures revertidos.' AS resultado;
