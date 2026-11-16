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

## Módulo de Compras

Disponible para ADMINISTRADOR e INVENTARIO. Abre **Compras** en la navegación.

1. Selecciona un proveedor o créalo con **Nuevo proveedor**.
2. Escribe la factura o conserva la referencia generada. La combinación
   proveedor/referencia es única y protege frente a registros duplicados.
3. Elige la forma de pago. CREDITO crea una cuenta por pagar y permite una fecha
   límite opcional. Los abonos se implementarán en otra etapa.
4. Busca productos activos por nombre o código exacto y agrégalos uno a uno.
5. Escribe la cantidad en unidades y el costo POR UNIDAD. Para una caja de
   12 unidades que cuesta Q60, usa cantidad 12 y costo Q5.
6. Si el producto controla lotes, reparte la cantidad entre uno o varios lotes.
   Número y vencimiento son opcionales; las cantidades son obligatorias y su
   suma debe coincidir. No se admiten vencimientos anteriores a hoy en Guatemala.
7. Pulsa **Registrar compra** una vez. El recibo confirma el ID y total; el
   historial muestra las últimas 30 compras. Vuelve a Productos para verificar
   el aumento de existencias.

La compra, detalles, lotes, movimientos y cuenta por pagar se registran mediante
`registrar_compra()` en una transacción. React no modifica existencia ni costo
directamente. El total se calcula en centavos en el cliente y se recalcula en
PostgreSQL. El precio de venta no cambia al registrar una compra.

Si falla la conexión, conserva la referencia y revisa el historial antes de
reintentar. Un mensaje de duplicado requiere revisar la compra existente, no
cambiar su referencia para repetirla. La pestaña conserva el borrador al cambiar
entre Productos y Compras, pero una recarga de página descarta un borrador sin guardar.

### SQL y validación

`database/09_compras.sql` corrige las referencias de esquema de las funciones
auxiliares, fija su search_path y actualiza la RPC de compras conservando sus
comprobaciones de usuario y rol. La RPC interpreta fechas en America/Guatemala.
Para una instalación nueva, ejecuta este archivo después de `08_permissions.sql`.
En el proyecto de Wayner ya se aplicó durante esta etapa.

- Código: `npm run build` y `npm run lint`.
- Validaciones de compras: `node --test tests/compraValidation.test.cjs`.
- Prueba integral SQL: `tests/compras_rollback.sql`, desde SQL Editor como postgres.
  Crea fixtures, comprueba contado/crédito/lotes/duplicados/autenticación y termina
  con ROLLBACK. No deja registros, aunque las secuencias pueden presentar saltos.
- Prueba desde la app: registra una compra real de pocas unidades y comprueba
  referencia, total, último costo y existencias. Al pulsar Registrar, sí se guarda.

Las ventas, anulaciones y pagos de deudas siguen pendientes de interfaz y de sus
pruebas específicas. Los datos anteriores no se eliminan ni se corrigen automáticamente.
