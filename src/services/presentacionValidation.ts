import { cantidadEntera, costoCentavos } from "./compraValidation";
export type PrecioPresentacion = {
 precio_venta: number;
 paquete_nombre?: string | null;
 paquete_unidades?: number | null;
 paquete_precio?: number | null;
 paquete_predeterminado?: boolean;
 paquete_version?: number;
};
export function tienePaquete(p: PrecioPresentacion): boolean {
 return Number.isInteger(p.paquete_unidades) && Number(p.paquete_unidades)>=2 && p.paquete_precio!==null && p.paquete_precio!==undefined;
}
export function calcularPresentacion(p: PrecioPresentacion, cantidad: string) {
 const unidades=cantidadEntera(cantidad);const unitario=costoCentavos(String(p.precio_venta));
 const paquetes=tienePaquete(p)?Math.floor(unidades/Number(p.paquete_unidades)):0;
 const sueltas=tienePaquete(p)?unidades%Number(p.paquete_unidades):unidades;
 const centavos=paquetes*(tienePaquete(p)?costoCentavos(String(p.paquete_precio)):0)+sueltas*unitario;
 if(!Number.isSafeInteger(centavos)||centavos>999999999999)throw new Error("El importe de la línea supera el máximo permitido.");
 return {unidades,paquetes,sueltas,centavos};
}
export function prepararPresentacion(id:number,version:number,activa:boolean,nombre:string,unidades:string,precio:string,predeterminada:boolean) {
 if(!Number.isSafeInteger(id)||id<1||!Number.isSafeInteger(version)||version<0)throw new Error("Actualiza el producto antes de configurar su presentación.");
 if(!activa)return {p_producto_id:id,p_version_esperada:version,p_nombre:null,p_unidades:null,p_precio:null,p_predeterminado:false};
 const n=nombre.trim();const cantidad=cantidadEntera(unidades);const centavos=costoCentavos(precio);
 if(!n||n.length>50||cantidad<2)throw new Error("Indica un nombre de hasta 50 caracteres y al menos dos unidades por paquete.");
 return {p_producto_id:id,p_version_esperada:version,p_nombre:n,p_unidades:cantidad,p_precio:centavos/100,p_predeterminado:predeterminada};
}
