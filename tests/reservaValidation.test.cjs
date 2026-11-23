const {test}=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');const path=require('node:path');const ts=require('typescript');
function cargar(relative){const s=ts.transpileModule(fs.readFileSync(path.resolve(__dirname,'../src',relative),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS}}).outputText;const m={exports:{}};new Function('require','module','exports',s)(n=>cargar(path.join(path.dirname(relative),n+'.ts')),m,m.exports);return m.exports;}
const {prepararReserva,recuperarReserva}=cargar('services/reservaValidation.ts');const uuid='510e3d20-f86c-4f2a-b753-201785fc3ce0';
test('saldo inicial admite cero; traslados y gastos requieren monto positivo y motivo',()=>{
 assert.equal(prepararReserva('INICIAL','0','Conteo',uuid).p_monto,0);assert.equal(prepararReserva('CAJA_A_RESERVA','500,50',' Excedente ',uuid).p_monto,500.5);
 for(const tipo of ['APORTE','GASTO','RETIRO_PERSONAL','CAJA_A_RESERVA','RESERVA_A_CAJA'])assert.throws(()=>prepararReserva(tipo,'0','Motivo',uuid));
 for(const monto of ['-1','1.001','','1e2'])assert.throws(()=>prepararReserva('APORTE',monto,'Motivo',uuid));assert.throws(()=>prepararReserva('GASTO','1',' ',uuid));
});
test('recupera exactamente la referencia y bloquea pendientes inválidos',()=>{
 const payload=prepararReserva('CAJA_A_RESERVA','700','Excedente',uuid);let raw=JSON.stringify(payload);global.localStorage={getItem:()=>raw};assert.deepEqual(recuperarReserva('x').pendiente,payload);
 for(const bad of ['{','null',JSON.stringify({...payload,p_tipo:'COMPRA'}),JSON.stringify({...payload,p_monto:'700'}),JSON.stringify({...payload,p_monto:0})]){raw=bad;assert.ok(recuperarReserva('x').error);}delete global.localStorage;
});
