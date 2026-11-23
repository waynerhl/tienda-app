# Publicar Mi tienda en Cloudflare Workers

Esta preparación se aplica después de Búsquedas sin tildes. No requiere el parche de Compras por costo total y conserva el formulario anterior de compras. Usa la misma base Supabase; no copia, reinicia ni vuelve a cargar productos, ventas, Caja o Reserva.

## Estado de la preparación

- Configuración de Workers estáticos con navegación SPA, sin servidor adicional ni Functions.
- Wrangler fijado en 4.166.0 y Node 22 mediante .nvmrc.
- La migración 26 ya está aplicada en Supabase: perfiles activos autorizados para leer catálogo, roles, lotes y movimientos; helper de roles sin acceso anónimo.
- RLS verificado en las 26 tablas públicas; sin permisos anónimos de lectura o escritura. Probados usuario sin sesión, cuenta sin perfil y administrador.
- Compilación para Cloudflare, lint, 33 pruebas de validación y ensayo de despliegue sin publicar.
- Cabeceras para evitar inclusión en otros sitios, limitar conexiones al proyecto Supabase y pedir a buscadores que no indexen la app. robots.txt no es una protección de acceso: los datos se protegen con RLS y sesión.
- La compilación de publicación falla si faltan variables o se intenta usar una clave privada.
- Todavía no existe una URL publicada por este cambio. Falta vincular la cuenta de Cloudflare y GitHub, configurar las variables y desplegar.
- No se ha generado un respaldo de datos en esta preparación. Git guarda código, no los registros de Supabase.

## Aplicar el parche y subir el código

Desde ~/Proyectos/tienda-app:

```bash
git apply --check ~/Descargas/Tienda_Publicar_Cloudflare_Con_Tildes.patch
git apply ~/Descargas/Tienda_Publicar_Cloudflare_Con_Tildes.patch
npm ci
npm run build:cloudflare
npm run lint
git add .gitignore .nvmrc index.html package.json package-lock.json wrangler.jsonc public/_headers public/robots.txt scripts/verificar-entorno.mjs src/App.tsx src/lib/supabase.ts database/26_acceso_publicacion.sql tests/publicacion_acceso_rollback.sql docs/Publicar_Cloudflare.md
git commit -m "Preparar publicación en Cloudflare"
git push
```

El build local usa las variables públicas existentes en .env.local. La migración ya está aplicada: no volver a ejecutarla ni ejecutar semillas.

## Cuenta y compilación en Cloudflare

1. Entra en https://dash.cloudflare.com/ o crea una cuenta en el plan gratuito.
2. En Workers & Pages, crea un Worker importando un repositorio de GitHub. Elige Workers, no la opción de Pages ni un nuevo proyecto de ejemplo.
3. Autoriza a Cloudflare para acceder al repositorio waynerhl/tienda-app. Basta con autorizar ese repositorio.
4. Usa esta configuración:

| Ajuste | Valor |
|---|---|
| Nombre del Worker | tienda-app |
| Rama de producción | main |
| Directorio raíz | raíz del repositorio |
| Comando de compilación | npm run build:cloudflare |
| Comando de despliegue | npm run deploy |
| Node | 22 (el archivo .nvmrc lo especifica) |

5. Antes del primer despliegue, en las variables de **compilación / Build variables** configura:

| Variable | Valor |
|---|---|
| VITE_SUPABASE_URL | https://ytzybvbeleuuoduitckq.supabase.co |
| VITE_SUPABASE_PUBLISHABLE_KEY | La misma clave publicable de tu .env.local |

La clave publicable también está en Supabase > Project Settings > API Keys. No pegar contraseñas de usuarios, URL de conexión PostgreSQL, service_role ni claves sb_secret. Las variables VITE_* se incluyen en JavaScript público por diseño; el control de acceso lo realizan sesión y RLS. No hace falta compartir las claves en el chat.

Si Cloudflare solo permite crear primero el Worker, guarda las variables en Settings > Build y vuelve a desplegar. Configurarlas solo como secretos de ejecución no modifica una app Vite ya compilada.

6. Despliega. Cloudflare mostrará una URL HTTPS bajo workers.dev. No se configura una base D1 ni un dominio de pago.

## Inicio de sesión y primera comprobación

El login actual usa correo y contraseña, sin redirección OAuth: la misma cuenta funciona en el nuevo sitio. Como la dirección es un origen diferente, hay que iniciar sesión de nuevo; el carrito o formularios pendientes guardados en localhost no se trasladan al teléfono ni al dominio publicado.

En Supabase > Authentication > URL Configuration, establece Site URL con la URL HTTPS publicada. Si más adelante se usan enlaces de recuperación o invitaciones, añade esa URL exacta a Redirect URLs. Conserva localhost si sigues usando esos enlaces en desarrollo; no es necesario habilitar todos los dominios con un comodín.

Comprueba primero sin crear operaciones ficticias:

1. Ventana privada: aparece el login y no se ven datos de la tienda.
2. Inicia sesión con tu cuenta: compara productos, Caja y Reserva con localhost.
3. Recarga la página: se recupera la sesión y se cargan los datos.
4. Abre la misma URL en el teléfono, entra y comprueba catálogo y navegación.
5. Cierra sesión en el teléfono y confirma que desaparecen los datos.
6. Registra la siguiente venta real desde un solo dispositivo y verifica que aparece una sola vez y descuenta la cantidad correcta.

Para atender con dos dispositivos, recuerda que comparten inventario y Caja: no registres dos veces el mismo cobro. Los formularios pendientes son locales a cada navegador. Las previsualizaciones que usan esta misma conexión también operan sobre datos reales.

## Respaldo y actualizaciones

Antes de depender exclusivamente de la URL, prepara un respaldo externo de los registros de Supabase. Los reportes CSV sirven para consulta, pero no sustituyen un respaldo restaurable. Las opciones de copia de seguridad dependen del plan; consulta https://supabase.com/docs/guides/platform/backups y conserva las exportaciones fuera de Git, en un lugar privado. La publicación no mueve ni elimina la base actual.

Cloudflare puede desplegar automáticamente al hacer push a main. Publica cambios probados; ante un problema de interfaz puedes volver a un despliegue anterior desde Cloudflare. Eso no revierte migraciones ni operaciones de Supabase. npm run dev continúa disponible en la computadora.

La app todavía requiere internet. Publicarla no añade modo sin conexión ni instalación PWA.

Referencias verificadas: https://developers.cloudflare.com/workers/static-assets/routing/single-page-application/ ; https://developers.cloudflare.com/workers/static-assets/headers/ ; https://developers.cloudflare.com/workers/ci-cd/builds/configuration/ ; https://supabase.com/docs/guides/database/postgres/row-level-security
