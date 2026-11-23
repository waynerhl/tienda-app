BEGIN;
-- La autorización exige un perfil activo de la tienda, además de iniciar sesión.
CREATE OR REPLACE FUNCTION public.fn_tiene_rol(p_roles text[])
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $function$
 SELECT EXISTS (
   SELECT 1 FROM public.usuarios u JOIN public.roles r ON r.id_rol=u.rol_id
   WHERE u.id_usuario=auth.uid() AND u.activo AND r.nombre=ANY(p_roles)
 );
$function$;
REVOKE EXECUTE ON FUNCTION public.fn_tiene_rol(text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_tiene_rol(text[]) TO authenticated;

ALTER POLICY roles_select_authenticated ON public.roles
 USING (public.fn_tiene_rol(ARRAY['ADMINISTRADOR','CAJERO','INVENTARIO']));
ALTER POLICY formas_pago_select_authenticated ON public.formas_pago
 USING (public.fn_tiene_rol(ARRAY['ADMINISTRADOR','CAJERO','INVENTARIO']));
ALTER POLICY tipos_movimientos_select_authenticated ON public.tipos_movimientos
 USING (public.fn_tiene_rol(ARRAY['ADMINISTRADOR','CAJERO','INVENTARIO']));
ALTER POLICY categorias_select_authenticated ON public.categorias
 USING (public.fn_tiene_rol(ARRAY['ADMINISTRADOR','CAJERO','INVENTARIO']));
ALTER POLICY productos_select_authenticated ON public.productos
 USING (public.fn_tiene_rol(ARRAY['ADMINISTRADOR','CAJERO','INVENTARIO']));
ALTER POLICY lotes_select_authenticated ON public.lotes
 USING (public.fn_tiene_rol(ARRAY['ADMINISTRADOR','CAJERO','INVENTARIO']));
ALTER POLICY movimientos_select_authenticated ON public.movimientos_inventario
 USING (public.fn_tiene_rol(ARRAY['ADMINISTRADOR','CAJERO','INVENTARIO']));
COMMIT;
