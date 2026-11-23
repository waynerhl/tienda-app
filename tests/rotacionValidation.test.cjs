const {test}=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');const path=require('node:path');const ts=require('typescript');
function cargar(relative){const s=ts.transpileModule(fs.readFileSync(path.resolve(__dirname,'../src',relative),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS}}).outputText;const m={exports:{}};new Function('require','module','exports',s)(n=>cargar(path.join(path.dirname(relative),n+'.ts')),m,m.exports);return m.exports;}
const {validarRotacion,csvRotacion}=cargar('services/rotacionValidation.ts');
test('períodos reales y objetivos enteros de 1 a 90',()=>{
 assert.equal(validarRotacion('2026-01-01','2026-01-03','7','2026-01-03'),7);
 for(const o of ['0','91','-1','1.5','1e1','',' 7','Infinity'])assert.throws(()=>validarRotacion('2026-01-01','2026-01-03',o,'2026-01-03'));
 assert.throws(()=>validarRotacion('2026-02-30','2026-02-30','7','2026-03-01'));
 assert.throws(()=>validarRotacion('2026-01-03','2026-01-01','7','2026-01-03'));
});
test('CSV incluye período y stock actual, neutraliza fórmulas y conserva ausencias',()=>{
 const p={nombre:' =SUM(1,2)',codigo_barras:'00123',unidades:0,importe:0,disponible:0,vencido:0,existencia_minima:1,promedio_diario:0,cobertura_dias:null,sugerencia:null,estado:'SIN_VENTAS',bajo_minimo:true};
 const csv=csvRotacion([p,{...p,nombre:'A "B"',unidades:2,cobertura_dias:0,sugerencia:3,estado:'REPONER'}],'2026-01-01','2026-01-03',7,'2026-02-01');
 assert.ok(csv.includes('2026-01-01,2026-01-03,7,2026-02-01,"\' =SUM(1,2)","00123"'));
 assert.ok(csv.includes('0,0.00,0,0,1,0,,,SIN_VENTAS,SI'));
 assert.ok(csv.includes('"A ""B"""'));assert.ok(csv.includes(',0,3,REPONER,SI'));
});
