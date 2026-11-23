const {test}=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');const path=require('node:path');const ts=require('typescript');
function cargar(relative){const s=ts.transpileModule(fs.readFileSync(path.resolve(__dirname,'../src',relative),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS}}).outputText;const m={exports:{}};new Function('require','module','exports',s)(n=>cargar(path.join(path.dirname(relative),n+'.ts')),m,m.exports);return m.exports;}
const {calcularPresentacion,prepararPresentacion}=cargar('services/presentacionValidation.ts');
test('paquetes completos más sobrantes a precio individual, sin prorratear el precio del paquete',()=>{
 const leche={precio_venta:14,paquete_unidades:12,paquete_precio:145};const huevos={precio_venta:1.5,paquete_unidades:30,paquete_precio:38};
 for(const [cantidad,total] of [[1,14],[12,145],[13,159],[24,290],[25,304],[30,374]])assert.equal(calcularPresentacion(leche,String(cantidad)).centavos,total*100);
 for(const [cantidad,total] of [[1,1.5],[29,43.5],[30,38],[31,39.5],[32,41],[60,76]])assert.equal(calcularPresentacion(huevos,String(cantidad)).centavos,total*100);
 assert.deepEqual(calcularPresentacion(leche,'13'),{unidades:13,paquetes:1,sueltas:1,centavos:15900});assert.equal(calcularPresentacion({precio_venta:14},'12').centavos,16800);
});
test('valida cantidades y límites sin convertir entradas incompletas a cero',()=>{
 for(const n of ['','0','1.5','-1','1e2'])assert.throws(()=>calcularPresentacion({precio_venta:14},n));
 assert.throws(()=>calcularPresentacion({precio_venta:9999999999.99},'2'));
 assert.equal(calcularPresentacion({precio_venta:14,paquete_unidades:12,paquete_precio:0},'13').centavos,1400);
});
test('configuración y desactivación conservan versión y validan precios',()=>{
 assert.deepEqual(prepararPresentacion(1,0,true,' Caja ','12','145,00',false),{p_producto_id:1,p_version_esperada:0,p_nombre:'Caja',p_unidades:12,p_precio:145,p_predeterminado:false});
 assert.equal(prepararPresentacion(1,1,false,'Caja','12','145',true).p_unidades,null);
 for(const args of [[1,0,true,'','12','145',false],[1,0,true,'Caja','1','145',false],[1,0,true,'Caja','12','145.001',false]])assert.throws(()=>prepararPresentacion(...args));
});
