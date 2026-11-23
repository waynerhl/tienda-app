const {test}=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');const path=require('node:path');const ts=require('typescript');
function cargar(relative){const s=ts.transpileModule(fs.readFileSync(path.resolve(__dirname,'../src',relative),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS}}).outputText;const m={exports:{}};new Function('require','module','exports',s)(n=>cargar(path.join(path.dirname(relative),n+'.ts')),m,m.exports);return m.exports;}
const {validarPeriodo,csvVentasDiarias}=cargar('services/reporteValidation.ts');
test('acepta períodos inclusivos de hasta 366 días y valida fechas reales',()=>{
  assert.doesNotThrow(()=>validarPeriodo('2024-01-01','2024-12-31','2026-01-01'));
  assert.doesNotThrow(()=>validarPeriodo('2026-01-01','2026-01-01','2026-01-01'));
  for(const [desde,hasta] of [['2024-01-01','2025-01-01'],['2026-01-02','2026-01-01'],['2026-02-30','2026-02-30'],['','2026-01-01'],['2027-01-01','2027-01-01']])assert.throws(()=>validarPeriodo(desde,hasta,'2026-01-01'));
});
test('CSV conserva fechas, ceros y centavos para todo el detalle diario',()=>{
  const csv=csvVentasDiarias([{dia:'2026-01-01',total:12.5,transacciones:2,unidades:3},{dia:'2026-01-02',total:0,transacciones:0,unidades:0}]);
  assert.equal(csv,'\ufefffecha,total_gtq,transacciones,unidades\r\n2026-01-01,12.50,2,3\r\n2026-01-02,0.00,0,0\r\n');
});
