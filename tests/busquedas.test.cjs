const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const ts = require('typescript');
const source = ts.transpileModule(fs.readFileSync(require('node:path').join(__dirname, '../src/services/busquedas.ts'), 'utf8'), {compilerOptions:{module:ts.ModuleKind.CommonJS}}).outputText;
const m = {exports:{}};
new Function('module','exports',source)(m,m.exports);
const {normalizarBusqueda,patronBusquedaNombre} = m.exports;
test('encuentra tildes y diéresis, incluso Unicode descompuesto, preservando ñ', () => {
  for (const s of ['Cajón','CAJÓN','Cajo\u0301n','Cajon']) assert.equal(normalizarBusqueda(s),'cajon');
  assert.equal(normalizarBusqueda('ÁÉÍÓÚÜ Ñ'),'aeiouu ñ');
  assert.notEqual(normalizarBusqueda('año'),normalizarBusqueda('ano'));
});
test('escapa comodines literales sin perder ceros', () => {
  assert.equal(patronBusquedaNombre('Café 10%_\\'),' %cafe 10\\%\\_\\\\%'.trimStart());
  assert.equal(normalizarBusqueda('001234'),'001234');
});
