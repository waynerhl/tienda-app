# React + TypeScript + Vite

This template provides a minimal setup to get React working in Vite with HMR and some ESLint rules.

Currently, two official plugins are available:

- [@vitejs/plugin-react](https://github.com/vitejs/vite-plugin-react/blob/main/packages/plugin-react) uses [Oxc](https://oxc.rs)
- [@vitejs/plugin-react-swc](https://github.com/vitejs/vite-plugin-react/blob/main/packages/plugin-react-swc) uses [SWC](https://swc.rs/)

## React Compiler

The React Compiler is not enabled on this template because of its impact on dev & build performances. To add it, see [this documentation](https://react.dev/learn/react-compiler/installation).

## Expanding the ESLint configuration

If you are developing a production application, we recommend updating the configuration to enable type-aware lint rules:

```js
export default defineConfig([
  globalIgnores(['dist']),
  {
    files: ['**/*.{ts,tsx}'],
    extends: [
      // Other configs...

      // Remove tseslint.configs.recommended and replace with this
      tseslint.configs.recommendedTypeChecked,
      // Alternatively, use this for stricter rules
      tseslint.configs.strictTypeChecked,
      // Optionally, add this for stylistic rules
      tseslint.configs.stylisticTypeChecked,

      // Other configs...
    ],
    languageOptions: {
      parserOptions: {
        project: ['./tsconfig.node.json', './tsconfig.app.json'],
        tsconfigRootDir: import.meta.dirname,
      },
      // other options...
    },
  },
])

```

You can also install [eslint-plugin-react-x](https://github.com/Rel1cx/eslint-react/tree/main/packages/plugins/eslint-plugin-react-x) and [eslint-plugin-react-dom](https://github.com/Rel1cx/eslint-react/tree/main/packages/plugins/eslint-plugin-react-dom) for React-specific lint rules:

```js
// eslint.config.js
import reactX from 'eslint-plugin-react-x'
import reactDom from 'eslint-plugin-react-dom'

export default defineConfig([
  globalIgnores(['dist']),
  {
    files: ['**/*.{ts,tsx}'],
    extends: [
      // Other configs...
      // Enable lint rules for React
      reactX.configs['recommended-typescript'],
      // Enable lint rules for React DOM
      reactDom.configs.recommended,
    ],
    languageOptions: {
      parserOptions: {
        project: ['./tsconfig.node.json', './tsconfig.app.json'],
        tsconfigRootDir: import.meta.dirname,
      },
      // other options...
    },
  },
])

```

## Primera interfaz conectada a Supabase

La aplicación permite iniciar sesión con una cuenta existente de Supabase Auth,
verifica que tenga un perfil activo en `public.usuarios` y consulta los productos
respetando los permisos RLS. Incluye búsqueda por nombre, paginación de 25
productos, alertas de stock y cierre de sesión en este dispositivo.

### Configuración local

1. Instala las dependencias con `npm ci`.
2. Si ya tienes `.env.local`, conserva sus valores y revisa estos nombres:
   - `VITE_SUPABASE_URL`: URL del proyecto.
   - `VITE_SUPABASE_PUBLISHABLE_KEY`: clave publicable del proyecto.
   - También se admite `VITE_SUPABASE_ANON_KEY` para una clave anon existente.
3. Si aún no tienes `.env.local`, copia `.env.example` y completa la clave
   publicable desde Supabase → Settings → API Keys.
4. Ejecuta `npm run dev` y abre la dirección que muestre Vite.
5. Ingresa con el correo y contraseña de un usuario de **tu aplicación**,
   creado en Supabase Auth. No son necesariamente los de tu cuenta del panel.
   Su UUID debe coincidir con `usuarios.id_usuario`; necesita un rol asignado
   y `activo = true`.

No pongas una clave `service_role` ni `sb_secret_` en variables `VITE_*`.
No subas `.env.local` a Git. Reinicia Vite después de cambiar sus variables.
Las pantallas de sesión no reemplazan las políticas RLS: la autorización real
se mantiene en Supabase. No se incluye registro público de usuarios.

### Comprobación manual

- Sin configuración, debe aparecer una indicación para completar `.env.local`.
- Con configuración, debe aparecer el formulario de ingreso.
- Una contraseña incorrecta debe mostrar un mensaje y permitir reintentar.
- Con una cuenta autorizada, deben aparecer los productos reales de Supabase.
- Busca un producto por nombre, prueba una búsqueda sin resultados y actualiza.
- Recarga: la sesión debe mantenerse. Cierra sesión: debe volver al formulario.
- Un perfil inexistente o inactivo debe mostrar «Acceso pendiente».

Validación de código: `npm run build` y `npm run lint`.

### Alcance de esta etapa

Esta pantalla consulta productos; todavía no registra compras, ventas ni abonos.
Antes de habilitar esas operaciones hay que verificar los triggers y funciones
SQL, el tratamiento de lotes vencidos y la consistencia de los datos de prueba.
Los indicadores de rentabilidad requieren definir el costo histórico vendido.

## Catálogo editable

Los perfiles activos ADMINISTRADOR e INVENTARIO pueden agregar y editar
productos. El CAJERO conserva la consulta del catálogo. Estos controles de
interfaz acompañan las políticas RLS y los permisos SQL existentes.

- Campos: nombre, categoría, código de barras opcional, precio de venta,
  existencia mínima y estado activo.
- Al crear se define si utiliza control por lotes. Esa opción queda bloqueada
  al editar, de acuerdo con los permisos actuales.
- La existencia inicial es cero. No se envían existencia ni último costo en
  estas operaciones; las entradas se registrarán mediante compras.
- El código de barras se conserva como texto, incluidos los ceros iniciales.
- Un código vacío se guarda como NULL. Los códigos duplicados muestran un error.
- El precio admite punto o coma decimal y hasta dos decimales.
- El guardado conserva el formulario si falla y evita envíos simultáneos.

Prueba manual con tu cuenta autorizada:

1. Agrega un producto real con una categoría existente y un código único.
2. Comprueba que se creó con existencia cero.
3. Edita su precio y mínimo; recarga y comprueba que persistieron.
4. Intenta reutilizar su código en otro producto: debe rechazarse.
5. Cancela un formulario y comprueba que no crea un registro.

Esta etapa no cambia el esquema SQL ni habilita todavía compras o ventas.
