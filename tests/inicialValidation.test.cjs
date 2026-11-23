const {test}=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');const path=require('node:path');const ts=require('typescript');
function cargar(relative){const s=ts.transpileModule(fs.readFileSync(path.resolve(__dirname,'../src',relative),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS}}).outputText;const m={exports:{}};new Function('require','module','exports',s)(n=>cargar(path.join(path.dirname(relative),n+'.ts')),m,m.exports);return m.exports;}
const {prepararInicial,recuperarInicial}=cargar('services/inicialValidation.ts');
const p={id_producto:1,activo:true,disponible_inicial:true,existencia:0,controla_lotes:true};const f={numero_lote:' A ',fecha_vencimiento:'2026-12-01',cantidad:'5',costo:'2,50'};const uuid='be26b875-5795-4fc2-a735-e2d5206c1901';
test('normaliza costo y lotes sin perder cantidades ni vencimientos',()=>{
 const r=prepararInicial(p,[f,{...f,numero_lote:'B',cantidad:'7'}],' Conteo ',uuid,'2026-11-18');
 assert.equal(r.p_partidas[0].costo_unitario,'2.50');assert.equal(r.p_partidas[0].numero_lote,'A');assert.equal(r.p_partidas[1].cantidad,7);assert.equal(r.p_motivo,'Conteo');
 for(const bad of [{...f,cantidad:'0'},{...f,costo:''},{...f,costo:'1.001'},{...f,numero_lote:''},{...f,fecha_vencimiento:'2026-11-17'},{...f,fecha_vencimiento:'2026-02-30'}])assert.throws(()=>prepararInicial(p,[bad],'Conteo',uuid,'2026-11-18'));
 assert.throws(()=>prepararInicial(p,[f,f],'Conteo',uuid,'2026-11-18'));assert.throws(()=>prepararInicial({...p,existencia:1},[f],'Conteo',uuid));
});
test('sin lotes acepta una partida con costo explícito, incluido cero',()=>{
 const r=prepararInicial({...p,controla_lotes:false},[{...f,costo:'0'}],'Conteo',uuid,'2026-11-18');assert.equal(r.p_partidas[0].numero_lote,null);assert.equal(r.p_partidas[0].fecha_vencimiento,null);assert.equal(r.p_partidas[0].costo_unitario,'0.00');
 assert.throws(()=>prepararInicial({...p,controla_lotes:false},[f,f],'Conteo',uuid));
});
test('recupera payload exacto sin reinterpretar fechas vencidas desde el primer intento',()=>{
 const payload=prepararInicial(p,[f],'Conteo',uuid,'2026-11-18');let raw=JSON.stringify(payload);global.localStorage={getItem:()=>raw};assert.deepEqual(recuperarInicial('x').pendiente,payload);
 for(const bad of ['null','{',JSON.stringify({...payload,p_producto_id:0}),JSON.stringify({...payload,p_partidas:[{...payload.p_partidas[0],cantidad:'5'}]})]){raw=bad;assert.ok(recuperarInicial('x').error);}delete global.localStorage;
});
