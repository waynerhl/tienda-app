const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require('typescript');

const source = fs.readFileSync(path.join(__dirname, '../src/services/compraValidation.ts'), 'utf8');
const compiled = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } }).outputText;
const mod = { exports: {} };
new Function('require', 'module', 'exports', compiled)(require, mod, mod.exports);
const { prepararCompra, costoCentavos, totalCompraCentavos } = mod.exports;
const efectivo = { id_forma_pago: 1, nombre: 'EFECTIVO' };
const credito = { id_forma_pago: 2, nombre: 'CREDITO' };
const line = (overrides = {}) => ({ producto: { id_producto: 1, nombre: 'Producto', activo: true, controla_lotes: false, ultimo_costo: null, codigo_barras: null }, cantidad: '3', costo_unitario: '0.10', lotes: [], ...overrides });
const preparar = (lines, pago = efectivo, fecha = '') => prepararCompra('1', pago, ' FACTURA-1 ', fecha, lines, '2026-11-16');

test('calcula centavos exactos y admite coma decimal', () => {
  assert.equal(costoCentavos('0,10'), 10);
  assert.equal(totalCompraCentavos([line(), line({ producto: { ...line().producto, id_producto: 2 }, cantidad: '1', costo_unitario: '0.20' })]), 50);
  assert.equal(preparar([line()]).p_numero_documento, 'FACTURA-1');
});
test('rechaza compra vacía, repetidos, cantidades inválidas y costos inválidos', () => {
  assert.throws(() => preparar([]));
  assert.throws(() => preparar([line(), line()]));
  for (const cantidad of ['0', '-1', '1.5', '', '2147483648']) assert.throws(() => preparar([line({ cantidad })]));
  for (const costo_unitario of ['-1', '', '1.234', 'NaN', 'Infinity']) assert.throws(() => preparar([line({ costo_unitario })]));
  assert.throws(() => preparar([line({ cantidad: '2147483647', costo_unitario: '9999999999.99' })]));
});
test('valida sumas de lotes, fechas y productos activos', () => {
  const conLotes = line({ producto: { ...line().producto, controla_lotes: true }, lotes: [{ cantidad: '3', numero_lote: ' A ', fecha_vencimiento: '2026-12-01' }] });
  assert.equal(preparar([conLotes]).p_items[0].lotes[0].numero_lote, 'A');
  assert.throws(() => preparar([{ ...conLotes, cantidad: '4' }]));
  assert.throws(() => preparar([{ ...conLotes, lotes: [] }]));
  for (const fecha_vencimiento of ['2026-11-15', '2027-02-30']) assert.throws(() => preparar([{ ...conLotes, lotes: [{ ...conLotes.lotes[0], fecha_vencimiento }] }]));
  assert.throws(() => preparar([line({ producto: { ...line().producto, activo: false } })]));
});
test('el crédito lleva fecha y monto positivo; el contado no envía fecha', () => {
  assert.equal(preparar([line()], credito, '2026-11-20').p_fecha_limite, '2026-11-20');
  assert.equal(preparar([line()], efectivo, '2026-11-20').p_fecha_limite, null);
  assert.throws(() => preparar([line()], credito, '2026-11-15'));
  assert.throws(() => preparar([line({ costo_unitario: '0' })], credito));
  assert.equal(preparar([line({ costo_unitario: '0' })], efectivo).p_items[0].costo_unitario, 0);
});
test('el payload usa solo la RPC y no incluye existencias ni usuario', () => {
  const payload = preparar([line()]);
  assert.equal('usuario_id' in payload, false);
  assert.deepEqual(Object.keys(payload.p_items[0]).sort(), ['cantidad', 'costo_unitario', 'producto_id']);
  assert.throws(() => prepararCompra('', efectivo, 'F', '', [line()]));
  assert.throws(() => prepararCompra('1', undefined, 'F', '', [line()]));
  assert.throws(() => prepararCompra('1', efectivo, ' ', '', [line()]));
});
