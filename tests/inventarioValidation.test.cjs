const { test }=require('node:test');const assert=require('node:assert/strict');const ts=require('typescript');const fs=require('node:fs');const path=require('node:path');
function cargar(relative){const source=ts.transpileModule(fs.readFileSync(path.resolve(__dirname,'../src',relative),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS}}).outputText;const mod={exports:{}};new Function('require','module','exports',source)(n=>cargar(path.join(path.dirname(relative),n+'.ts')),mod,mod.exports);return mod.exports;}
const {prepararAjuste,recuperarAjuste}=cargar('services/inventarioValidation.ts');
const prod={id_producto:1,nombre:'Producto',codigo_barras:'00123',existencia:10,controla_lotes:false,activo:true};const uuid='122c781a-0cf4-400a-95f7-f2bb7837c68a';
test('conteo usa total físico y permite cero; pérdidas usan unidades positivas',()=>{
  const p=prepararAjuste(prod,null,'CONTEO','0',' Vacío ',uuid);assert.equal(p.p_cantidad,0);assert.equal(p.p_existencia_esperada,10);assert.equal(p.p_motivo,'Vacío');
  for(const n of ['0','-1','1.5','1e2','NaN','11'])assert.throws(()=>prepararAjuste(prod,null,'PERDIDA',n,'Daño',uuid));
  assert.throws(()=>prepararAjuste(prod,null,'CONTEO','8',' ',uuid));
});
test('exige lote y solo permite vencimiento antes de hoy',()=>{
  const p={...prod,controla_lotes:true};const l={id_lote:3,numero_lote:'A',fecha_ingreso:'2026-01-01',fecha_vencimiento:'2026-01-02',existencia:4,vencido:true};
  assert.throws(()=>prepararAjuste(p,null,'CONTEO','4','Conteo',uuid));
  assert.throws(()=>prepararAjuste(prod,l,'CONTEO','4','Conteo',uuid));
  assert.throws(()=>prepararAjuste(p,l,'VENCIMIENTO','1','Retiro',uuid,'2026-01-02'));
  assert.equal(prepararAjuste(p,l,'VENCIMIENTO','1','Retiro',uuid,'2026-01-03').p_existencia_esperada,4);
  assert.throws(()=>prepararAjuste({...prod,existencia:2147483647},null,'AJUSTE_POSITIVO','1','Corregir',uuid));
});
test('recupera solicitud exacta y bloquea almacenamiento dañado',()=>{
  const p=prepararAjuste(prod,null,'CONTEO','8','Conteo',uuid);let t=JSON.stringify(p);global.localStorage={getItem:()=>t};assert.deepEqual(recuperarAjuste('key').pendiente,p);
  for(const bad of ['null','{',JSON.stringify({...p,p_cantidad:'8'}),JSON.stringify({...p,p_solicitud_id:'otro'}),JSON.stringify({...p,p_tipo:'COMPRA'})]){t=bad;assert.ok(recuperarAjuste('key').error);}delete global.localStorage;
});
