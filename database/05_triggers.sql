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


CREATE TRIGGER trg_recalcular_costos_estado_compra
AFTER UPDATE OF estado
ON compras
FOR EACH ROW
EXECUTE FUNCTION fn_recalcular_costos_por_estado_compra();

CREATE TRIGGER trg_validar_pago_cuenta_por_cobrar
BEFORE INSERT OR UPDATE
ON pagos_cuentas_por_cobrar
FOR EACH ROW
EXECUTE FUNCTION fn_validar_pago_cuenta_por_cobrar();

CREATE TRIGGER trg_actualizar_cuenta_por_cobrar_pago
AFTER INSERT OR UPDATE OR DELETE
ON pagos_cuentas_por_cobrar
FOR EACH ROW
EXECUTE FUNCTION fn_actualizar_cuenta_por_cobrar_pago();

CREATE TRIGGER trg_validar_pago_cuenta_por_pagar
BEFORE INSERT OR UPDATE
ON pagos_cuentas_por_pagar
FOR EACH ROW
EXECUTE FUNCTION fn_validar_pago_cuenta_por_pagar();

CREATE TRIGGER trg_actualizar_cuenta_por_pagar_pago
AFTER INSERT OR UPDATE OR DELETE
ON pagos_cuentas_por_pagar
FOR EACH ROW
EXECUTE FUNCTION fn_actualizar_cuenta_por_pagar_pago();

CREATE TRIGGER trg_validar_cuenta_por_cobrar
BEFORE INSERT OR UPDATE OF
    venta_id,
    monto_original,
    fecha_limite
ON cuentas_por_cobrar
FOR EACH ROW
EXECUTE FUNCTION fn_validar_cuenta_por_cobrar();

CREATE TRIGGER trg_validar_cuenta_por_pagar
BEFORE INSERT OR UPDATE OF
    compra_id,
    monto_original,
    fecha_limite
ON cuentas_por_pagar
FOR EACH ROW
EXECUTE FUNCTION fn_validar_cuenta_por_pagar();


CREATE TRIGGER trg_validar_forma_pago_abono_cxc
BEFORE INSERT OR UPDATE OF forma_pago_id
ON pagos_cuentas_por_cobrar
FOR EACH ROW
EXECUTE FUNCTION fn_validar_forma_pago_abono();

CREATE TRIGGER trg_validar_forma_pago_abono_cxp
BEFORE INSERT OR UPDATE OF forma_pago_id
ON pagos_cuentas_por_pagar
FOR EACH ROW
EXECUTE FUNCTION fn_validar_forma_pago_abono();