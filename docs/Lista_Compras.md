# Lista de compras compartida

Disponible para ADMINISTRADOR e INVENTARIO. Las partidas se guardan en Supabase
y se comparten entre dispositivos y cuentas autorizadas de esta tienda.

## Instalación

Aplica después del parche Costos y utilidad:

```bash
git apply --check ~/Descargas/Tienda_Lista_Compras.patch
git apply ~/Descargas/Tienda_Lista_Compras.patch
npm run build
```

Supabase ya fue actualizado. No necesitas ejecutar SQL adicional ni instalar
dependencias. En instalaciones nuevas, `database/19_lista_compras.sql` va después
de los scripts 01–18.

## Preparar y usar la lista

1. Abre **Lista de compras** y revisa las sugerencias de reposición.
2. Busca por nombre o código de barras exacto. Desmarca el filtro de mínimos para
   buscar otros productos activos y pulsa **Buscar reposición**.
3. Pulsa **Añadir a lista**, indica unidades y nota, revisa y confirma.
4. La lista guardada conserva todas sus partidas aunque cambies la búsqueda.
5. Usa **Editar partida** o **Quitar de lista** cuando lo necesites.
6. **Descargar lista CSV** exporta la lista completa para llevarla al proveedor.
7. Después de recibir los productos, registra la compra en **Compras**. Luego
   ajusta o quita la partida planificada; no se borra automáticamente.

La lista no genera compras, deudas ni existencias. Registra cantidades en unidades
del producto y adapta la cifra a los empaques y condiciones de tu proveedor.

## Sugerencias y presupuesto

La sugerencia intenta superar el mínimo por una unidad:
**máximo(0, mínimo + 1 − disponible)**, dentro del rango permitido de inventario.
No es una predicción de demanda ni un lote económico de compra.

Sin lotes, disponible es la existencia registrada. Con lotes, suma existencias
de compras registradas con vencimiento de hoy o posterior, o sin fecha de
vencimiento según las reglas actuales de la aplicación. Los lotes vencidos se
muestran aparte y no se usan como unidades disponibles para reponer.
Si el producto y sus lotes no concilian, se señala y no se genera sugerencia.

El subtotal estimado usa el último costo conocido. Las partidas sin costo quedan
fuera de ese subtotal y se cuentan aparte. Los precios reales deben confirmarse
con el proveedor; el presupuesto se actualiza cuando cambia el último costo.

El CSV escapa textos y neutraliza posibles fórmulas de hoja de cálculo. Para
conservar ceros iniciales al abrirlo, importa la columna de códigos como texto.

## Cambios desde otros dispositivos

Una partida tiene una versión. Si otra persona la modifica, una edición basada
en una versión anterior se rechaza y pide actualizar. Los reintentos de una misma
confirmación no duplican la partida ni suman otra vez la cantidad.

Si se interrumpe la conexión, utiliza **Reintentar confirmación**. No borres los
datos del navegador ni prepares otra operación por el mismo cambio mientras
esa confirmación siga pendiente. Para ver cambios ajenos, pulsa **Actualizar lista**.

## Verificación

```bash
npm run build
npm run lint
node --test tests/listaComprasValidation.test.cjs
```

`tests/lista_compras_rollback.sql` prueba reposición con vencidos, presupuestos,
ediciones, versiones, reintentos, códigos exactos y permisos. Ejecuta el archivo
completo como postgres; los fixtures se revierten al terminar.
