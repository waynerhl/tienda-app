const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const ts = require('typescript');
const path = require('node:path');
function cargar(relative) {
  const file = path.resolve(__dirname, '../src', relative);
  const source = ts.transpileModule(fs.readFileSync(file, 'utf8'), { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2023 } }).outputText;
  const mod = { exports: {} };
  new Function('require', 'module', 'exports', source)((name) => cargar(path.join(path.dirname(relative), name + '.ts')), mod, mod.exports);
  return mod.exports;
}
const { prepararAbono, prepararCliente, recuperarAbono } = cargar('services/cobroValidation.ts');
const forma = { id_forma_pago: 1, nombre: 'EFECTIVO' };
const uuid = 'a1f5b29a-f082-4b90-b199-8ac717943c8e';
test('abonos exactos en centavos, coma decimal y liquidación', () => {
  assert.equal(prepararAbono(1, '12,50', 12.5, forma, uuid).p_monto, 12.5);
  assert.equal(prepararAbono(1, '0.30', 0.3, forma, uuid).p_monto, 0.3);
  for (const monto of ['0', '-1', '1.001', 'NaN', '1e2', '999999999999']) assert.throws(() => prepararAbono(1, monto, 100, forma, uuid));
  assert.throws(() => prepararAbono(1, '10.01', 10, forma, uuid), /supera/);
  assert.throws(() => prepararAbono(1, '1', 10, { id_forma_pago: 4, nombre: 'CREDITO' }, uuid), /crédito/);
});
test('límite vacío, límite cero y teléfono conservan su significado', () => {
  const c = prepararCliente(' Ana ', ' 001234 ', ' ', '');
  assert.deepEqual(c, { nombre: 'Ana', telefono: '001234', direccion: null, limite_credito: null });
  assert.equal(prepararCliente('Ana', '', '', '0').limite_credito, 0);
  assert.throws(() => prepararCliente(' ', '', '', ''));
  assert.throws(() => prepararCliente('Ana', '1'.repeat(21), '', ''));
});
test('recupera el mismo UUID después de recargar y bloquea almacenamiento corrupto', () => {
  const p = prepararAbono(1, '12.5', 20, forma, uuid);
  let texto = JSON.stringify(p);
  global.localStorage = { getItem: () => texto };
  assert.deepEqual(recuperarAbono('pendiente').pendiente, p);
  for (const bad of ['{', 'null', JSON.stringify({ ...p, p_monto: '12.50' }), JSON.stringify({ ...p, p_solicitud_id: 'otro' })]) {
    texto = bad; assert.ok(recuperarAbono('pendiente').error);
  }
  global.localStorage = { getItem: () => { throw Error('storage bloqueado'); } };
  assert.ok(recuperarAbono('pendiente').error);
  delete global.localStorage;
});
