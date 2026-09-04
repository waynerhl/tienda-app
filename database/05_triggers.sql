CREATE TRIGGER trg_aplicar_movimiento_inventario
AFTER INSERT
ON movimientos_inventario
FOR EACH ROW
EXECUTE FUNCTION fn_aplicar_movimiento_inventario();


CREATE TRIGGER trg_validar_movimiento_inventario
BEFORE INSERT OR UPDATE
ON movimientos_inventario
FOR EACH ROW
EXECUTE FUNCTION fn_validar_movimiento_inventario();

CREATE TRIGGER trg_actualizar_ultimo_costo_detalle
AFTER INSERT OR UPDATE OR DELETE
ON detalle_compras
FOR EACH ROW
EXECUTE FUNCTION fn_actualizar_ultimo_costo_detalle();