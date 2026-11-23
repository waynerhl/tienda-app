BEGIN;
CREATE TABLE public.lista_compras (
  producto_id integer PRIMARY KEY REFERENCES public.productos(id_producto),
  cantidad integer NOT NULL CHECK(cantidad>0),nota text NOT NULL DEFAULT '' CHECK(length(nota)<=500),
  version integer NOT NULL CHECK(version>0),activo boolean NOT NULL DEFAULT true,
  actualizado timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  usuario_id uuid NOT NULL REFERENCES public.usuarios(id_usuario)
);
CREATE INDEX lista_compras_usuario_idx ON public.lista_compras(usuario_id);
CREATE TABLE public.lista_compras_operaciones (
  id_operacion bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,solicitud_id uuid NOT NULL UNIQUE,
  producto_id integer NOT NULL REFERENCES public.productos(id_producto),usuario_id uuid NOT NULL REFERENCES public.usuarios(id_usuario),
  fecha timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,parametros jsonb NOT NULL,resultado jsonb NOT NULL
);
CREATE INDEX lista_compras_operaciones_producto_idx ON public.lista_compras_operaciones(producto_id);
CREATE INDEX lista_compras_operaciones_usuario_idx ON public.lista_compras_operaciones(usuario_id);
ALTER TABLE public.lista_compras ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lista_compras_operaciones ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.lista_compras,public.lista_compras_operaciones FROM anon,authenticated;
GRANT SELECT ON public.lista_compras,public.lista_compras_operaciones TO authenticated;
CREATE POLICY lista_compras_lectura ON public.lista_compras FOR SELECT TO authenticated USING(public.fn_tiene_rol(ARRAY['ADMINISTRADOR','INVENTARIO']));
CREATE POLICY lista_compras_operaciones_lectura ON public.lista_compras_operaciones FOR SELECT TO authenticated USING(public.fn_tiene_rol(ARRAY['ADMINISTRADOR','INVENTARIO']));

CREATE OR REPLACE FUNCTION tienda_privada.actualizar_lista_compras(p_solicitud_id uuid,p_producto_id integer,p_version_esperada integer,p_accion text,p_cantidad integer,p_nota text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_usuario uuid:=auth.uid();v_anterior public.lista_compras_operaciones%ROWTYPE;v_fila public.lista_compras%ROWTYPE;v_producto public.productos%ROWTYPE;v_params jsonb;v_resultado jsonb;v_version integer;v_nota text:=trim(coalesce(p_nota,''));
BEGIN
  IF v_usuario IS NULL OR NOT public.fn_tiene_rol(ARRAY['ADMINISTRADOR','INVENTARIO']) THEN RAISE EXCEPTION 'No tienes permiso para modificar la lista de compras.' USING ERRCODE='42501';END IF;
  IF p_solicitud_id IS NULL OR p_producto_id IS NULL OR p_version_esperada IS NULL OR p_version_esperada<0 OR p_accion IS NULL OR p_accion NOT IN ('GUARDAR','QUITAR') OR length(v_nota)>500
     OR (p_accion='GUARDAR' AND (p_cantidad IS NULL OR p_cantidad<1)) OR (p_accion='QUITAR' AND p_cantidad IS NOT NULL) THEN
    RAISE EXCEPTION 'Revisa la operación, cantidad y nota.' USING ERRCODE='22023';
  END IF;
  v_params:=jsonb_build_object('producto',p_producto_id,'version',p_version_esperada,'accion',p_accion,'cantidad',p_cantidad,'nota',v_nota);
  PERFORM pg_advisory_xact_lock(hashtextextended('lista-compras:'||p_solicitud_id::text,0));
  SELECT * INTO v_anterior FROM public.lista_compras_operaciones WHERE solicitud_id=p_solicitud_id;
  IF FOUND THEN
    IF v_anterior.usuario_id<>v_usuario OR v_anterior.parametros<>v_params THEN RAISE EXCEPTION 'La referencia ya corresponde a otra operación.' USING ERRCODE='22023';END IF;
    RETURN v_anterior.resultado||jsonb_build_object('repetida',true);
  END IF;
  SELECT * INTO v_producto FROM public.productos WHERE id_producto=p_producto_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Producto no encontrado.' USING ERRCODE='22023';END IF;
  IF p_accion='GUARDAR' AND NOT v_producto.activo THEN RAISE EXCEPTION 'El producto está inactivo. Actívalo antes de añadirlo a la lista.' USING ERRCODE='22023';END IF;
  SELECT * INTO v_fila FROM public.lista_compras WHERE producto_id=p_producto_id FOR UPDATE;
  v_version:=coalesce(v_fila.version,0);
  IF v_version<>p_version_esperada THEN RAISE EXCEPTION 'La lista cambió en otro momento o dispositivo. Actualiza y revisa la cantidad antes de confirmar otra vez.' USING ERRCODE='22023';END IF;
  IF v_version=2147483647 THEN RAISE EXCEPTION 'La versión de esta partida requiere revisión.' USING ERRCODE='22023';END IF;
  IF p_accion='QUITAR' THEN
    IF NOT coalesce(v_fila.activo,false) THEN RAISE EXCEPTION 'El producto ya no está en la lista.' USING ERRCODE='22023';END IF;
    UPDATE public.lista_compras SET activo=false,version=v_version+1,usuario_id=v_usuario,actualizado=CURRENT_TIMESTAMP WHERE producto_id=p_producto_id;
  ELSE
    INSERT INTO public.lista_compras(producto_id,cantidad,nota,version,activo,usuario_id)
    VALUES(p_producto_id,p_cantidad,v_nota,v_version+1,true,v_usuario)
    ON CONFLICT(producto_id) DO UPDATE SET cantidad=EXCLUDED.cantidad,nota=EXCLUDED.nota,version=EXCLUDED.version,activo=true,usuario_id=v_usuario,actualizado=CURRENT_TIMESTAMP;
  END IF;
  v_resultado:=jsonb_build_object('producto_id',p_producto_id,'version',v_version+1,'activo',p_accion='GUARDAR','repetida',false);
  INSERT INTO public.lista_compras_operaciones(solicitud_id,producto_id,usuario_id,parametros,resultado) VALUES(p_solicitud_id,p_producto_id,v_usuario,v_params,v_resultado);
  RETURN v_resultado;
END;
$fn$;
REVOKE ALL ON FUNCTION tienda_privada.actualizar_lista_compras(uuid,integer,integer,text,integer,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION tienda_privada.actualizar_lista_compras(uuid,integer,integer,text,integer,text) TO authenticated;
CREATE OR REPLACE FUNCTION public.actualizar_lista_compras(p_solicitud_id uuid,p_producto_id integer,p_version_esperada integer,p_accion text,p_cantidad integer DEFAULT NULL,p_nota text DEFAULT '')
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $fn$
  SELECT tienda_privada.actualizar_lista_compras(p_solicitud_id,p_producto_id,p_version_esperada,p_accion,p_cantidad,p_nota);
$fn$;
REVOKE ALL ON FUNCTION public.actualizar_lista_compras(uuid,integer,integer,text,integer,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.actualizar_lista_compras(uuid,integer,integer,text,integer,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.obtener_lista_compras(p_busqueda text DEFAULT '',p_modo text DEFAULT 'nombre',p_solo_reponer boolean DEFAULT true,p_pagina integer DEFAULT 0)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path='' AS $fn$
DECLARE v_hoy date:=(CURRENT_TIMESTAMP AT TIME ZONE 'America/Guatemala')::date;v_resultado jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT public.fn_tiene_rol(ARRAY['ADMINISTRADOR','INVENTARIO']) THEN RAISE EXCEPTION 'No tienes permiso para consultar la lista.' USING ERRCODE='42501';END IF;
  IF p_busqueda IS NULL OR length(p_busqueda)>150 OR p_modo IS NULL OR p_modo NOT IN ('nombre','codigo_barras') OR p_solo_reponer IS NULL OR p_pagina IS NULL OR p_pagina<0 OR p_pagina>1000000 THEN RAISE EXCEPTION 'Revisa la búsqueda o la página.' USING ERRCODE='22023';END IF;
  WITH stocks AS (
    SELECT d.producto_id,sum(public.fn_stock_lote(l.id_lote)) AS total,
      coalesce(sum(public.fn_stock_lote(l.id_lote)) FILTER(WHERE c.estado='REGISTRADA'),0) AS registrado,
      coalesce(sum(public.fn_stock_lote(l.id_lote)) FILTER(WHERE c.estado='REGISTRADA' AND (l.fecha_vencimiento IS NULL OR l.fecha_vencimiento>=v_hoy)),0) AS apto,
      coalesce(sum(public.fn_stock_lote(l.id_lote)) FILTER(WHERE c.estado='REGISTRADA' AND l.fecha_vencimiento<v_hoy),0) AS vencido,
      bool_or(public.fn_stock_lote(l.id_lote)<0) AS negativo
    FROM public.lotes l JOIN public.detalle_compras d ON d.id_detalle_compra=l.detalle_compra_id JOIN public.compras c ON c.id_compra=d.compra_id GROUP BY d.producto_id
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
    FROM catalogo c WHERE activo AND (trim(p_busqueda)='' OR CASE WHEN p_modo='codigo_barras' THEN codigo_barras=trim(p_busqueda) ELSE strpos(lower(nombre),lower(trim(p_busqueda)))>0 END)
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
$fn$;
REVOKE ALL ON FUNCTION public.obtener_lista_compras(text,text,boolean,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.obtener_lista_compras(text,text,boolean,integer) TO authenticated;
COMMIT;
