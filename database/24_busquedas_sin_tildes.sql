-- Búsquedas por nombre sin tildes; conserva ñ y códigos de barras.
CREATE OR REPLACE FUNCTION public.normalizar_busqueda(p_texto text)
RETURNS text LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE
SET search_path = ''
AS $$
 SELECT lower(translate(normalize(p_texto, NFC), 'áéíóúüÁÉÍÓÚÜ', 'aeiouuAEIOUU'));
$$;
REVOKE ALL ON FUNCTION public.normalizar_busqueda(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.normalizar_busqueda(text) TO authenticated;
ALTER TABLE public.productos ADD COLUMN nombre_busqueda text
 GENERATED ALWAYS AS (public.normalizar_busqueda(nombre)) STORED;
GRANT SELECT(nombre_busqueda) ON public.productos TO authenticated;

CREATE OR REPLACE FUNCTION public.listar_clientes_cobros(p_busqueda text DEFAULT ''::text, p_pagina integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE v_resultado jsonb; v_hoy date := (CURRENT_TIMESTAMP AT TIME ZONE 'America/Guatemala')::date;
BEGIN
  IF auth.uid() IS NULL OR NOT public.fn_tiene_rol(ARRAY['ADMINISTRADOR','CAJERO']) THEN
    RAISE EXCEPTION 'No tienes permiso para consultar clientes.' USING ERRCODE='42501';
  END IF;
  IF p_pagina IS NULL OR p_pagina<0 OR p_pagina>1000000 OR p_busqueda IS NULL OR length(p_busqueda)>150 THEN
    RAISE EXCEPTION 'Revisa la búsqueda o la página.' USING ERRCODE='22023';
  END IF;
  WITH encontrados AS (
    SELECT * FROM public.clientes
    WHERE strpos(public.normalizar_busqueda(nombre),public.normalizar_busqueda(trim(p_busqueda)))>0
       OR strpos(coalesce(telefono,''),trim(p_busqueda))>0
  ), pagina AS (
    SELECT * FROM encontrados ORDER BY nombre,id_cliente LIMIT 20 OFFSET p_pagina*20
  ), saldos AS (
    SELECT v.cliente_id,sum(c.saldo_pendiente) AS saldo,
      coalesce(sum(c.saldo_pendiente) FILTER(WHERE c.fecha_limite<v_hoy),0) AS vencido
    FROM public.cuentas_por_cobrar c JOIN public.ventas v ON v.id_venta=c.venta_id
    WHERE v.estado='REGISTRADA' GROUP BY v.cliente_id
  )
  SELECT jsonb_build_object('total',(SELECT count(*) FROM encontrados),'clientes',
    coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.nombre,x.id_cliente) FROM
      (SELECT p.*,coalesce(s.saldo,0) AS saldo,coalesce(s.vencido,0) AS vencido
       FROM pagina p LEFT JOIN saldos s ON s.cliente_id=p.id_cliente)x),'[]'::jsonb)) INTO v_resultado;
  RETURN v_resultado;
END;
$function$;

CREATE OR REPLACE FUNCTION public.listar_proveedores_pagos(p_busqueda text DEFAULT ''::text, p_pagina integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE v_resultado jsonb; v_hoy date := (CURRENT_TIMESTAMP AT TIME ZONE 'America/Guatemala')::date;
BEGIN
  IF auth.uid() IS NULL OR NOT public.fn_tiene_rol(ARRAY['ADMINISTRADOR','INVENTARIO']) THEN
    RAISE EXCEPTION 'No tienes permiso para consultar proveedores.' USING ERRCODE='42501';
  END IF;
  IF p_pagina IS NULL OR p_pagina<0 OR p_pagina>1000000 OR p_busqueda IS NULL OR length(p_busqueda)>150 THEN
    RAISE EXCEPTION 'Revisa la búsqueda o la página.' USING ERRCODE='22023';
  END IF;
  WITH encontrados AS (
    SELECT * FROM public.proveedores
    WHERE strpos(public.normalizar_busqueda(nombre),public.normalizar_busqueda(trim(p_busqueda)))>0
       OR strpos(coalesce(telefono,''),trim(p_busqueda))>0
  ), pagina AS (
    SELECT * FROM encontrados ORDER BY nombre,id_proveedor LIMIT 20 OFFSET p_pagina*20
  ), saldos AS (
    SELECT v.proveedor_id,sum(c.saldo_pendiente) AS saldo,
      coalesce(sum(c.saldo_pendiente) FILTER(WHERE c.fecha_limite<v_hoy),0) AS vencido
    FROM public.cuentas_por_pagar c JOIN public.compras v ON v.id_compra=c.compra_id
    WHERE v.estado='REGISTRADA' GROUP BY v.proveedor_id
  )
  SELECT jsonb_build_object('total',(SELECT count(*) FROM encontrados),'proveedores',
    coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.nombre,x.id_proveedor) FROM
      (SELECT p.*,coalesce(s.saldo,0) AS saldo,coalesce(s.vencido,0) AS vencido
       FROM pagina p LEFT JOIN saldos s ON s.proveedor_id=p.id_proveedor)x),'[]'::jsonb)) INTO v_resultado;
  RETURN v_resultado;
END;
$function$;

CREATE OR REPLACE FUNCTION public.obtener_lista_compras(p_busqueda text DEFAULT ''::text, p_modo text DEFAULT 'nombre'::text, p_solo_reponer boolean DEFAULT true, p_pagina integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
DECLARE v_hoy date:=(CURRENT_TIMESTAMP AT TIME ZONE 'America/Guatemala')::date;v_resultado jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT public.fn_tiene_rol(ARRAY['ADMINISTRADOR','INVENTARIO']) THEN RAISE EXCEPTION 'No tienes permiso para consultar la lista.' USING ERRCODE='42501';END IF;
  IF p_busqueda IS NULL OR length(p_busqueda)>150 OR p_modo IS NULL OR p_modo NOT IN ('nombre','codigo_barras') OR p_solo_reponer IS NULL OR p_pagina IS NULL OR p_pagina<0 OR p_pagina>1000000 THEN RAISE EXCEPTION 'Revisa la búsqueda o la página.' USING ERRCODE='22023';END IF;
  WITH stocks AS (
    SELECT l.producto_id,sum(public.fn_stock_lote(l.id_lote)) AS total,
      coalesce(sum(public.fn_stock_lote(l.id_lote)) FILTER(WHERE l.estado='REGISTRADA'),0) AS registrado,
      coalesce(sum(public.fn_stock_lote(l.id_lote)) FILTER(WHERE l.estado='REGISTRADA' AND (l.fecha_vencimiento IS NULL OR l.fecha_vencimiento>=v_hoy)),0) AS apto,
      coalesce(sum(public.fn_stock_lote(l.id_lote)) FILTER(WHERE l.estado='REGISTRADA' AND l.fecha_vencimiento<v_hoy),0) AS vencido,
      bool_or(public.fn_stock_lote(l.id_lote)<0) AS negativo
    FROM public.lotes_contexto l GROUP BY l.producto_id
  ), catalogo AS (
    SELECT p.id_producto,p.nombre,p.codigo_barras,p.activo,p.existencia,p.existencia_minima,p.controla_lotes,
      CASE WHEN p.controla_lotes THEN coalesce(s.apto,0) ELSE p.existencia END AS disponible,
      CASE WHEN p.controla_lotes THEN coalesce(s.vencido,0) ELSE 0 END AS vencido,
      p.controla_lotes AND (coalesce(s.total,0)<>p.existencia OR coalesce(s.registrado,0)<>p.existencia OR coalesce(s.negativo,false)) AS inconsistente,
      CASE WHEN p.ultimo_costo>=0 AND p.ultimo_costo<=9999999999.99 THEN p.ultimo_costo ELSE NULL END AS costo_estimado,
      coalesce(l.version,0) AS version_lista,coalesce(l.activo,false) AS en_lista,l.cantidad AS cantidad_lista,coalesce(l.nota,'') AS nota_lista
    FROM public.productos p LEFT JOIN stocks s ON s.producto_id=p.id_producto LEFT JOIN public.lista_compras l ON l.producto_id=p.id_producto
  ), candidatos AS (
    SELECT c.*,CASE WHEN inconsistente THEN NULL ELSE greatest(least(existencia_minima::bigint+1,2147483647)-disponible,0) END AS cantidad_sugerida
    FROM catalogo c WHERE activo AND (trim(p_busqueda)='' OR CASE WHEN p_modo='codigo_barras' THEN codigo_barras=trim(p_busqueda) ELSE strpos(public.normalizar_busqueda(nombre),public.normalizar_busqueda(trim(p_busqueda)))>0 END)
      AND (NOT p_solo_reponer OR disponible<=existencia_minima OR inconsistente)
  ), pagina AS (
    SELECT * FROM candidatos ORDER BY (disponible=0) DESC,disponible,nombre,id_producto LIMIT 20 OFFSET p_pagina*20
  ), lista AS (
    SELECT c.*,l.cantidad,l.nota,l.version,l.actualizado,CASE WHEN c.costo_estimado IS NULL THEN NULL ELSE l.cantidad::numeric*c.costo_estimado END AS subtotal_estimado
    FROM public.lista_compras l JOIN catalogo c ON c.id_producto=l.producto_id WHERE l.activo
  )
  SELECT jsonb_build_object('fecha',v_hoy,'total_candidatos',(SELECT count(*) FROM candidatos),
    'candidatos',coalesce((SELECT jsonb_agg(to_jsonb(p) ORDER BY (p.disponible=0) DESC,p.disponible,p.nombre,p.id_producto) FROM pagina p),'[]'::jsonb),
    'lista',coalesce((SELECT jsonb_agg(to_jsonb(l) ORDER BY l.nombre,l.id_producto) FROM lista l),'[]'::jsonb),
    'partidas',(SELECT count(*) FROM lista),'unidades',(SELECT coalesce(sum(cantidad),0) FROM lista),
    'subtotal_con_costo',(SELECT coalesce(sum(subtotal_estimado),0) FROM lista),'sin_costo',(SELECT count(*) FROM lista WHERE costo_estimado IS NULL)) INTO v_resultado;
  RETURN v_resultado;
END;
$function$;

CREATE OR REPLACE FUNCTION public.obtener_rotacion_productos(p_desde date, p_hasta date, p_objetivo integer DEFAULT 7, p_busqueda text DEFAULT ''::text, p_filtro text DEFAULT 'todos'::text, p_orden text DEFAULT 'reponer'::text, p_pagina integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
DECLARE
  v_hoy date := (CURRENT_TIMESTAMP AT TIME ZONE 'America/Guatemala')::date;
  v_dias integer; v_inicio timestamptz; v_fin timestamptz; v_resultado jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT public.fn_tiene_rol(ARRAY['ADMINISTRADOR']) THEN
    RAISE EXCEPTION 'Solo el administrador puede consultar la rotación.' USING ERRCODE='42501';
  END IF;
  IF p_desde IS NULL OR p_hasta IS NULL OR p_desde<'1900-01-01'::date OR p_desde>p_hasta OR p_hasta>v_hoy OR p_hasta-p_desde>365 THEN
    RAISE EXCEPTION 'Selecciona un período válido de hasta 366 días, sin fechas futuras.' USING ERRCODE='22023';
  END IF;
  IF p_objetivo IS NULL OR p_objetivo<1 OR p_objetivo>90 OR p_busqueda IS NULL OR length(p_busqueda)>150
    OR p_filtro IS NULL OR p_filtro NOT IN ('todos','reponer','sin_ventas','revisar')
    OR p_orden IS NULL OR p_orden NOT IN ('reponer','mas','menos')
    OR p_pagina IS NULL OR p_pagina<0 OR p_pagina>1000000 THEN
    RAISE EXCEPTION 'Revisa el objetivo, los filtros o la página.' USING ERRCODE='22023';
  END IF;
  v_dias:=p_hasta-p_desde+1;
  v_inicio:=p_desde::timestamp AT TIME ZONE 'America/Guatemala';
  v_fin:=(p_hasta+1)::timestamp AT TIME ZONE 'America/Guatemala';
  WITH candidatas AS (
    SELECT id_venta,total FROM public.ventas
    WHERE estado='REGISTRADA' AND fecha>=v_inicio AND fecha<v_fin
  ), revisadas AS (
    SELECT v.id_venta, count(d.id_detalle_venta)>0 AND v.total=coalesce(sum(d.subtotal),0) AS valida
    FROM candidatas v LEFT JOIN public.detalle_ventas d ON d.venta_id=v.id_venta GROUP BY v.id_venta,v.total
  ), vendido AS (
    SELECT d.producto_id,sum(d.cantidad) AS unidades,sum(d.subtotal) AS importe
    FROM public.detalle_ventas d JOIN revisadas v ON v.id_venta=d.venta_id AND v.valida GROUP BY d.producto_id
  ), lotes_stock AS MATERIALIZED (
    SELECT l.producto_id,l.estado,l.fecha_vencimiento,public.fn_stock_lote(l.id_lote) AS stock
    FROM public.lotes_contexto l
  ), stocks AS (
    SELECT producto_id,sum(stock) AS total,
      coalesce(sum(stock) FILTER(WHERE estado='REGISTRADA'),0) AS registrado,
      coalesce(sum(stock) FILTER(WHERE estado='REGISTRADA' AND (fecha_vencimiento IS NULL OR fecha_vencimiento>=v_hoy)),0) AS apto,
      coalesce(sum(stock) FILTER(WHERE estado='REGISTRADA' AND fecha_vencimiento<v_hoy),0) AS vencido,
      bool_or(stock<0) AS negativo
    FROM lotes_stock GROUP BY producto_id
  ), base AS (
    SELECT p.id_producto,p.nombre,p.codigo_barras,p.existencia,p.existencia_minima,
      coalesce(v.unidades,0) AS unidades,coalesce(v.importe,0) AS importe,
      CASE WHEN p.controla_lotes THEN coalesce(s.apto,0) ELSE p.existencia END AS disponible,
      CASE WHEN p.controla_lotes THEN coalesce(s.vencido,0) ELSE 0 END AS vencido,
      p.controla_lotes AND (coalesce(s.total,0)<>p.existencia OR coalesce(s.registrado,0)<>p.existencia OR coalesce(s.negativo,false)) AS inconsistente
    FROM public.productos p LEFT JOIN vendido v ON v.producto_id=p.id_producto LEFT JOIN stocks s ON s.producto_id=p.id_producto
    WHERE p.activo
  ), calculada AS (
    SELECT b.*,round(unidades::numeric/v_dias,4) AS promedio_diario,
      CASE WHEN unidades>0 AND NOT inconsistente THEN round(disponible::numeric*v_dias/unidades,2) END AS cobertura_dias,
      CASE WHEN unidades>0 AND NOT inconsistente THEN
        greatest(greatest(ceil(unidades::numeric*p_objetivo/v_dias),existencia_minima::numeric+1)-disponible,0)
      END AS sugerencia,
      NOT inconsistente AND disponible<=existencia_minima AS bajo_minimo
    FROM base b
  ), clasificada AS (
    SELECT c.*,CASE WHEN inconsistente THEN 'REVISAR' WHEN unidades=0 THEN 'SIN_VENTAS'
      WHEN sugerencia>0 THEN 'REPONER' ELSE 'SUFICIENTE' END AS estado
    FROM calculada c
  ), filtrada AS (
    SELECT * FROM clasificada WHERE (trim(p_busqueda)='' OR strpos(public.normalizar_busqueda(nombre),public.normalizar_busqueda(trim(p_busqueda)))>0 OR codigo_barras=trim(p_busqueda))
      AND (p_filtro='todos' OR p_filtro='reponer' AND estado='REPONER' OR p_filtro='sin_ventas' AND estado='SIN_VENTAS' OR p_filtro='revisar' AND estado='REVISAR')
  ), ordenada AS (
    SELECT f.*,row_number() OVER(ORDER BY
      CASE WHEN p_orden='reponer' THEN CASE estado WHEN 'REVISAR' THEN 0 WHEN 'REPONER' THEN 1 WHEN 'SIN_VENTAS' THEN 3 ELSE 2 END END,
      CASE WHEN p_orden='reponer' AND estado='REPONER' THEN disponible::numeric*v_dias/nullif(unidades,0) END ASC NULLS LAST,
      CASE WHEN p_orden='mas' THEN unidades END DESC,
      CASE WHEN p_orden='menos' THEN unidades END ASC,
      nombre,id_producto) AS posicion
    FROM filtrada f
  ), pagina AS (SELECT * FROM ordenada ORDER BY posicion LIMIT 20 OFFSET p_pagina*20)
  SELECT jsonb_build_object('desde',p_desde,'hasta',p_hasta,'dias',v_dias,'objetivo',p_objetivo,
    'fecha_stock',v_hoy,'actualizado',CURRENT_TIMESTAMP,'total',(SELECT count(*) FROM filtrada),
    'activos',(SELECT count(*) FROM clasificada),'con_ventas',(SELECT count(*) FROM clasificada WHERE unidades>0),
    'sin_ventas',(SELECT count(*) FROM clasificada WHERE unidades=0),'reponer',(SELECT count(*) FROM clasificada WHERE estado='REPONER'),
    'revisar',(SELECT count(*) FROM clasificada WHERE inconsistente),'bajo_minimo',(SELECT count(*) FROM clasificada WHERE bajo_minimo),
    'ventas_excluidas',(SELECT count(*) FROM revisadas WHERE NOT valida),
    'productos',coalesce((SELECT jsonb_agg(to_jsonb(p)-'posicion' ORDER BY p.posicion) FROM pagina p),'[]'::jsonb)) INTO v_resultado;
  RETURN v_resultado;
END;
$function$;

CREATE OR REPLACE FUNCTION public.obtener_productos_inicial(p_busqueda text DEFAULT ''::text, p_modo text DEFAULT 'nombre'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
DECLARE v_resultado jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT public.fn_tiene_rol(ARRAY['ADMINISTRADOR']) THEN RAISE EXCEPTION 'Solo el administrador puede preparar inventario inicial.' USING ERRCODE='42501'; END IF;
  IF p_busqueda IS NULL OR length(p_busqueda)>150 OR p_modo IS NULL OR p_modo NOT IN ('nombre','codigo_barras') THEN RAISE EXCEPTION 'Revisa la búsqueda.' USING ERRCODE='22023'; END IF;
  SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.nombre,t.id_producto),'[]'::jsonb) INTO v_resultado FROM (
    SELECT p.id_producto,p.nombre,p.codigo_barras,p.existencia,p.controla_lotes,p.activo,i.resultado AS inicial,
      p.activo AND p.existencia=0 AND i.id_inicial IS NULL
        AND NOT EXISTS(SELECT 1 FROM public.movimientos_inventario m WHERE m.producto_id=p.id_producto)
        AND NOT EXISTS(SELECT 1 FROM public.detalle_compras d WHERE d.producto_id=p.id_producto)
        AND NOT EXISTS(SELECT 1 FROM public.detalle_ventas d WHERE d.producto_id=p.id_producto) AS disponible_inicial
    FROM public.productos p LEFT JOIN public.inventarios_iniciales i ON i.producto_id=p.id_producto
    WHERE trim(p_busqueda)='' OR CASE WHEN p_modo='codigo_barras' THEN p.codigo_barras=trim(p_busqueda) ELSE strpos(public.normalizar_busqueda(p.nombre),public.normalizar_busqueda(trim(p_busqueda)))>0 END
    ORDER BY p.nombre,p.id_producto LIMIT 20
  )t;
  RETURN v_resultado;
END;
$function$;
