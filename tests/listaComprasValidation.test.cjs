const {test}=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');const path=require('node:path');const ts=require('typescript');
const source=ts.transpileModule(fs.readFileSync(path.join(__dirname,'../src/services/listaComprasValidation.ts'),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2023}}).outputText;const mod={exports:{}};new Function('module','exports',source)(mod,mod.exports);const {prepararPartida,recuperarPartida,csvListaCompras}=mod.exports;
const item={id_producto:1,nombre:'Producto',codigo_barras:'00123',activo:true,version_lista:0,en_lista:false,costo_estimado:2,cantidad:3,nota:''};const uuid='53325bd4-f034-4c45-b36e-2f136e658e49';
test('cantidad y versión se conservan sin incrementar cantidades por reintento',()=>{
  assert.deepEqual(prepararPartida(item,'6',' Revisar proveedor ',uuid),{p_solicitud_id:uuid,p_producto_id:1,p_version_esperada:0,p_accion:'GUARDAR',p_cantidad:6,p_nota:'Revisar proveedor'});
  for(const n of ['0','-1','1.2','1e2','NaN'])assert.throws(()=>prepararPartida(item,n,'',uuid));
  assert.throws(()=>prepararPartida({...item,activo:false},'1','',uuid));
});
test('CSV escapa textos y neutraliza fórmulas sin rellenar costos desconocidos',()=>{
  const csv=csvListaCompras([{...item,nombre:' =SUM(1,2)',nota:'A "B"'},{...item,id_producto:2,nombre:'Sin costo',costo_estimado:null}]);
  assert.ok(csv.includes('"\' =SUM(1,2)"'));assert.ok(csv.includes('"00123"'));assert.ok(csv.includes('"A ""B"""'));assert.ok(csv.includes('2.00,6.00'));assert.ok(csv.includes('"Sin costo","00123",3,"",,\r\n'));
});
test('recupera solicitudes exactas y bloquea pendientes malformados',()=>{
  const p=prepararPartida(item,'6','',uuid);let texto=JSON.stringify(p);global.localStorage={getItem:()=>texto};assert.deepEqual(recuperarPartida('x').pendiente,p);
  for(const bad of ['null','{',JSON.stringify({...p,p_cantidad:'6'}),JSON.stringify({...p,p_version_esperada:-1}),JSON.stringify({...p,p_solicitud_id:'otro'})]){texto=bad;assert.ok(recuperarPartida('x').error);}delete global.localStorage;
});
