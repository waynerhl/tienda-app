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
const { prepararCaja, recuperarCaja } = cargar('services/cajaValidation.ts');
const uuid='53325bd4-f034-4c45-b36e-2f136e658e49';
test('permite apertura y conteo en cero, pero gastos y retiros deben ser positivos',()=>{
  assert.equal(prepararCaja('2026-01-01','APERTURA','0','',uuid,'2026-01-02').p_monto,0);
  assert.equal(prepararCaja('2026-01-01','CIERRE','0','',uuid,'2026-01-02').p_monto,0);
  assert.equal(prepararCaja('2026-01-01','RETIRO_PERSONAL','12,50',' Personal ',uuid,'2026-01-02').p_monto,12.5);
  for(const tipo of ['GASTO','RETIRO_PERSONAL','APORTE'])assert.throws(()=>prepararCaja('2026-01-01',tipo,'0','Concepto',uuid,'2026-01-02'));
  for(const monto of ['-1','1.001','NaN','1e2'])assert.throws(()=>prepararCaja('2026-01-01','GASTO',monto,'Concepto',uuid,'2026-01-02'));
});
test('exige motivo al corregir fondo o reabrir y valida fechas',()=>{
  for(const tipo of ['REAPERTURA','AJUSTE_FONDO'])assert.throws(()=>prepararCaja('2026-01-01',tipo,'20','',uuid,'2026-01-02'));
  assert.equal(prepararCaja('2026-01-01','REAPERTURA','',' Continuar atención ',uuid,'2026-01-02').p_monto,null);
  assert.equal(prepararCaja('2026-01-01','AJUSTE_FONDO','0','Corregir digitación',uuid,'2026-01-02').p_monto,0);
  for(const fecha of ['2026-02-30','2027-01-01','1899-12-31',''])assert.throws(()=>prepararCaja(fecha,'APERTURA','20','',uuid,'2026-01-02'));
});
test('conserva solicitud pendiente y bloquea datos corruptos',()=>{
  const payload=prepararCaja('2026-01-01','GASTO','12.5','Bolsas',uuid,'2026-01-02');
  let texto=JSON.stringify(payload);global.localStorage={getItem:()=>texto};
  assert.deepEqual(recuperarCaja('key').pendiente,payload);
  for(const value of ['null','{',JSON.stringify({...payload,p_solicitud_id:'otro'}),JSON.stringify({...payload,p_tipo:'OTRO'}),JSON.stringify({...payload,p_monto:'12.5'})]){texto=value;assert.ok(recuperarCaja('key').error);}
  delete global.localStorage;
});
