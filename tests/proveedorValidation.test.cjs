const { test } = require('node:test');
const assert = require('node:assert/strict');
const ts = require('typescript');
const fs = require('node:fs');
const path = require('node:path');
const source = ts.transpileModule(fs.readFileSync(path.join(__dirname, '../src/services/proveedorValidation.ts'), 'utf8'), { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText;
const mod = { exports: {} };
new Function('module', 'exports', source)(mod, mod.exports);
const { prepararProveedor } = mod.exports;
test('conserva ceros del teléfono y transforma campos opcionales vacíos en null', () => {
  assert.deepEqual(prepararProveedor(' Distribuidor ', ' 001234 ', ' ', ' '), { nombre: 'Distribuidor', telefono: '001234', direccion: null, correo: null });
});
test('valida contactos y tamaños antes de guardar', () => {
  assert.equal(prepararProveedor('A', '', '', ' ventas@proveedor.gt ').correo, 'ventas@proveedor.gt');
  for (const args of [[' ', '', '', ''], ['A', '1'.repeat(21), '', ''], ['A', '', 'a'.repeat(251), ''], ['A', '', '', 'correo inválido']]) assert.throws(() => prepararProveedor(...args));
});
