--tienda-app123  09356e2f-4b67-4fbe-9208-dabf0f9611f6

CREATE TABLE categorias (
    id_categoria INTEGER GENERATED ALWAYS AS IDENTITY,
    nombre VARCHAR(120) NOT NULL,

    CONSTRAINT pk_categorias
        PRIMARY KEY (id_categoria),

    CONSTRAINT uq_categorias_nombre
        UNIQUE (nombre)
);

CREATE TABLE productos (
    id_producto INTEGER GENERATED ALWAYS AS IDENTITY,
    categoria_id INTEGER NOT NULL,

    codigo_barras VARCHAR(50),
    nombre VARCHAR(150) NOT NULL,

    precio_venta NUMERIC(12,2) NOT NULL,
    ultimo_costo NUMERIC(12,2),

    existencia INTEGER NOT NULL DEFAULT 0,
    existencia_minima INTEGER NOT NULL DEFAULT 0,

    imagen VARCHAR(500),

    activo BOOLEAN NOT NULL DEFAULT TRUE,

    CONSTRAINT pk_productos
        PRIMARY KEY (id_producto),

    CONSTRAINT fk_productos_categorias
        FOREIGN KEY (categoria_id)
        REFERENCES categorias(id_categoria),

    CONSTRAINT uq_productos_codigo_barras
        UNIQUE (codigo_barras),

    CONSTRAINT ck_productos_precio_venta
        CHECK (precio_venta >= 0),

    CONSTRAINT ck_productos_ultimo_costo
        CHECK (
            ultimo_costo IS NULL
            OR ultimo_costo >= 0
        ),

    CONSTRAINT ck_productos_existencia
        CHECK (existencia >= 0),

    CONSTRAINT ck_productos_existencia_minima
        CHECK (existencia_minima >= 0)
);

CREATE TABLE proveedores (
    id_proveedor INTEGER GENERATED ALWAYS AS IDENTITY,

    nombre VARCHAR(150) NOT NULL,
    telefono VARCHAR(20),
    correo VARCHAR(150),
    direccion VARCHAR(250),

    CONSTRAINT pk_proveedores
        PRIMARY KEY (id_proveedor)
);

CREATE TABLE roles (
    id_rol INTEGER GENERATED ALWAYS AS IDENTITY,
    nombre VARCHAR(150) NOT NULL,

    CONSTRAINT pk_roles
        PRIMARY KEY (id_rol),

    CONSTRAINT uq_roles_nombre
        UNIQUE (nombre)
);

CREATE TABLE formas_pago (
    id_forma_pago INTEGER GENERATED ALWAYS AS IDENTITY,
    nombre VARCHAR(150) NOT NULL,

    CONSTRAINT pk_formas_pago
        PRIMARY KEY (id_forma_pago),

    CONSTRAINT uq_formas_pago_nombre
        UNIQUE (nombre)
);

CREATE TABLE tipos_movimientos (
    id_tipo_movimiento INTEGER GENERATED ALWAYS AS IDENTITY,

    nombre VARCHAR(150) NOT NULL,

    factor SMALLINT NOT NULL,

    CONSTRAINT pk_tipos_movimientos
        PRIMARY KEY (id_tipo_movimiento),

    CONSTRAINT uq_tipos_movimientos_nombre
        UNIQUE (nombre),

    CONSTRAINT ck_tipos_movimientos_factor
        CHECK (factor IN (-1, 1))
);

CREATE TABLE clientes (
    id_cliente INTEGER GENERATED ALWAYS AS IDENTITY,

    nombre VARCHAR(150) NOT NULL,
    telefono VARCHAR(20),
    direccion VARCHAR(250),

    limite_credito NUMERIC(12,2),

    CONSTRAINT pk_clientes
        PRIMARY KEY (id_cliente),

    CONSTRAINT ck_clientes_limite_credito
        CHECK (
            limite_credito IS NULL
            OR limite_credito >= 0
        )
);

CREATE TABLE usuarios (
    id_usuario UUID,

    rol_id INTEGER NOT NULL,

    nombre VARCHAR(100) NOT NULL,
    activo BOOLEAN NOT NULL DEFAULT TRUE,

    CONSTRAINT pk_usuarios
        PRIMARY KEY (id_usuario),

    CONSTRAINT fk_usuarios_auth
        FOREIGN KEY (id_usuario)
        REFERENCES auth.users(id),

    CONSTRAINT fk_usuarios_roles
        FOREIGN KEY (rol_id)
        REFERENCES roles(id_rol)
);

CREATE TABLE compras (
    id_compra INTEGER GENERATED ALWAYS AS IDENTITY,

    proveedor_id INTEGER NOT NULL,
    usuario_id UUID NOT NULL,
    forma_pago_id INTEGER NOT NULL,

    fecha TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    numero_documento VARCHAR(100),

    total NUMERIC(12,2) NOT NULL,

    estado VARCHAR(30)
        NOT NULL
        DEFAULT 'REGISTRADA',

    CONSTRAINT pk_compras
        PRIMARY KEY (id_compra),

    CONSTRAINT fk_compras_proveedores
        FOREIGN KEY (proveedor_id)
        REFERENCES proveedores(id_proveedor),

    CONSTRAINT fk_compras_usuarios
        FOREIGN KEY (usuario_id)
        REFERENCES usuarios(id_usuario),

    CONSTRAINT fk_compras_formas_pago
        FOREIGN KEY (forma_pago_id)
        REFERENCES formas_pago(id_forma_pago),

    CONSTRAINT uq_compras_proveedor_documento
        UNIQUE (proveedor_id, numero_documento),

    CONSTRAINT ck_compras_total
        CHECK (total >= 0),

    CONSTRAINT ck_compras_estado
        CHECK (
            estado IN ('REGISTRADA', 'ANULADA')
        )
);

CREATE TABLE detalle_compras (
    id_detalle_compra INTEGER GENERATED ALWAYS AS IDENTITY,

    compra_id INTEGER NOT NULL,
    producto_id INTEGER NOT NULL,

    cantidad INTEGER NOT NULL,

    costo_unitario NUMERIC(12,2) NOT NULL,

    subtotal NUMERIC(12,2)
        GENERATED ALWAYS AS (
            cantidad * costo_unitario
        ) STORED,

    CONSTRAINT pk_detalle_compras
        PRIMARY KEY (id_detalle_compra),

    CONSTRAINT fk_detalle_compras_compras
        FOREIGN KEY (compra_id)
        REFERENCES compras(id_compra),

    CONSTRAINT fk_detalle_compras_productos
        FOREIGN KEY (producto_id)
        REFERENCES productos(id_producto),

    CONSTRAINT ck_detalle_compras_cantidad
        CHECK (cantidad > 0),

    CONSTRAINT ck_detalle_compras_costo_unitario
        CHECK (costo_unitario >= 0)
);

CREATE TABLE lotes (
    id_lote INTEGER GENERATED ALWAYS AS IDENTITY,

    detalle_compra_id INTEGER NOT NULL,

    numero_lote VARCHAR(150),

    fecha_ingreso DATE
        NOT NULL
        DEFAULT CURRENT_DATE,

    fecha_vencimiento DATE,

    CONSTRAINT pk_lotes
        PRIMARY KEY (id_lote),

    CONSTRAINT fk_lotes_detalle_compra
        FOREIGN KEY (detalle_compra_id)
        REFERENCES detalle_compras(id_detalle_compra),

    CONSTRAINT ck_lotes_fecha_vencimiento
        CHECK (
            fecha_vencimiento IS NULL
            OR fecha_vencimiento >= fecha_ingreso
        )
);


CREATE TABLE ventas (
    id_venta INTEGER GENERATED ALWAYS AS IDENTITY,

    usuario_id UUID NOT NULL,
    forma_pago_id INTEGER NOT NULL,

    fecha TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    total NUMERIC(12,2) NOT NULL,

    estado VARCHAR(30)
        NOT NULL
        DEFAULT 'REGISTRADA',

    CONSTRAINT pk_ventas
        PRIMARY KEY (id_venta),

    CONSTRAINT fk_ventas_clientes
        FOREIGN KEY (cliente_id)
        REFERENCES clientes(id_cliente),

    CONSTRAINT fk_ventas_usuarios
        FOREIGN KEY (usuario_id)
        REFERENCES usuarios(id_usuario),

    CONSTRAINT fk_ventas_formas_pago
        FOREIGN KEY (forma_pago_id)
        REFERENCES formas_pago(id_forma_pago),

    CONSTRAINT ck_ventas_total
        CHECK (total >= 0),

    CONSTRAINT ck_ventas_estado
        CHECK (
            estado IN ('REGISTRADA', 'ANULADA')
        )
);

CREATE TABLE detalle_ventas (
    id_detalle_venta INTEGER GENERATED ALWAYS AS IDENTITY,

    venta_id INTEGER NOT NULL,
    producto_id INTEGER NOT NULL,

    cantidad INTEGER NOT NULL,

    precio_unitario NUMERIC(12,2) NOT NULL,

    subtotal NUMERIC(12,2)
        GENERATED ALWAYS AS (
            cantidad * precio_unitario
        ) STORED,

    CONSTRAINT pk_detalle_ventas
        PRIMARY KEY (id_detalle_venta),

    CONSTRAINT fk_detalle_ventas_venta
        FOREIGN KEY (venta_id)
        REFERENCES ventas(id_venta),

    CONSTRAINT fk_detalle_ventas_producto
        FOREIGN KEY (producto_id)
        REFERENCES productos(id_producto),

    CONSTRAINT ck_detalle_ventas_cantidad
        CHECK (cantidad > 0),

    CONSTRAINT ck_detalle_ventas_precio_unitario
        CHECK (precio_unitario >= 0)
);

CREATE TABLE cuentas_por_cobrar (
    id_cuenta_por_cobrar INTEGER GENERATED ALWAYS AS IDENTITY,

    venta_id INTEGER NOT NULL,

    monto_original NUMERIC(12,2) NOT NULL,
    saldo_pendiente NUMERIC(12,2) NOT NULL,

    fecha_limite DATE,

    estado VARCHAR(30)
        NOT NULL
        DEFAULT 'PENDIENTE',

    CONSTRAINT pk_cuentas_por_cobrar
        PRIMARY KEY (id_cuenta_por_cobrar),

    CONSTRAINT fk_cuentas_por_cobrar_ventas
        FOREIGN KEY (venta_id)
        REFERENCES ventas(id_venta),

    CONSTRAINT uq_cuentas_por_cobrar_venta
        UNIQUE (venta_id),

    CONSTRAINT ck_cuentas_por_cobrar_monto_original
        CHECK (monto_original > 0),

    CONSTRAINT ck_cuentas_por_cobrar_saldo
        CHECK (
            saldo_pendiente >= 0
            AND saldo_pendiente <= monto_original
        ),

    CONSTRAINT ck_cuentas_por_cobrar_estado
        CHECK (
            estado IN (
                'PENDIENTE',
                'PAGADA',
                'VENCIDA'
            )
        )
);

CREATE TABLE pagos_cuentas_por_cobrar (
    id_pago_cuenta_por_cobrar INTEGER
        GENERATED ALWAYS AS IDENTITY,

    cuenta_por_cobrar_id INTEGER NOT NULL,

    usuario_id UUID NOT NULL,

    forma_pago_id INTEGER NOT NULL,

    fecha TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    monto NUMERIC(12,2) NOT NULL,

    CONSTRAINT pk_pagos_cuentas_por_cobrar
        PRIMARY KEY (id_pago_cuenta_por_cobrar),

    CONSTRAINT fk_pagos_cxc_cuenta
        FOREIGN KEY (cuenta_por_cobrar_id)
        REFERENCES cuentas_por_cobrar(
            id_cuenta_por_cobrar
        ),

    CONSTRAINT fk_pagos_cxc_usuario
        FOREIGN KEY (usuario_id)
        REFERENCES usuarios(id_usuario),

    CONSTRAINT fk_pagos_cxc_forma_pago
        FOREIGN KEY (forma_pago_id)
        REFERENCES formas_pago(id_forma_pago),

    CONSTRAINT ck_pagos_cxc_monto
        CHECK (monto > 0)
);


CREATE TABLE cuentas_por_pagar (
    id_cuenta_por_pagar INTEGER GENERATED ALWAYS AS IDENTITY,

    compra_id INTEGER NOT NULL,

    monto_original NUMERIC(12,2) NOT NULL,
    saldo_pendiente NUMERIC(12,2) NOT NULL,

    fecha_limite DATE,

    estado VARCHAR(30)
        NOT NULL
        DEFAULT 'PENDIENTE',

    CONSTRAINT pk_cuentas_por_pagar
        PRIMARY KEY (id_cuenta_por_pagar),

    CONSTRAINT fk_cuentas_por_pagar_compras
        FOREIGN KEY (compra_id)
        REFERENCES compras(id_compra),

    CONSTRAINT uq_cuentas_por_pagar_compra
        UNIQUE (compra_id),

    CONSTRAINT ck_cuentas_por_pagar_monto_original
        CHECK (monto_original > 0),

    CONSTRAINT ck_cuentas_por_pagar_saldo
        CHECK (
            saldo_pendiente >= 0
            AND saldo_pendiente <= monto_original
        ),

    CONSTRAINT ck_cuentas_por_pagar_estado
        CHECK (
            estado IN (
                'PENDIENTE',
                'PAGADA',
                'VENCIDA'
            )
        )
);


CREATE TABLE pagos_cuentas_por_pagar (
    id_pago_cuenta_por_pagar INTEGER
        GENERATED ALWAYS AS IDENTITY,

    cuenta_por_pagar_id INTEGER NOT NULL,

    usuario_id UUID NOT NULL,

    forma_pago_id INTEGER NOT NULL,

    fecha TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    monto NUMERIC(12,2) NOT NULL,

    CONSTRAINT pk_pagos_cuentas_por_pagar
        PRIMARY KEY (id_pago_cuenta_por_pagar),

    CONSTRAINT fk_pagos_cxp_cuenta
        FOREIGN KEY (cuenta_por_pagar_id)
        REFERENCES cuentas_por_pagar(
            id_cuenta_por_pagar
        ),

    CONSTRAINT fk_pagos_cxp_usuario
        FOREIGN KEY (usuario_id)
        REFERENCES usuarios(id_usuario),

    CONSTRAINT fk_pagos_cxp_forma_pago
        FOREIGN KEY (forma_pago_id)
        REFERENCES formas_pago(id_forma_pago),

    CONSTRAINT ck_pagos_cxp_monto
        CHECK (monto > 0)
);


CREATE TABLE movimientos_inventario (
    id_movimiento_inventario INTEGER
        GENERATED ALWAYS AS IDENTITY,

    producto_id INTEGER NOT NULL,

    lote_id INTEGER,

    tipo_movimiento_id INTEGER NOT NULL,


    detalle_compra_id INTEGER,
    detalle_venta_id INTEGER,

    cantidad INTEGER NOT NULL,

    fecha TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    usuario_id UUID NOT NULL,

    observacion VARCHAR(500),

    CONSTRAINT pk_movimientos_inventario
        PRIMARY KEY (id_movimiento_inventario),

    CONSTRAINT fk_movimientos_producto
        FOREIGN KEY (producto_id)
        REFERENCES productos(id_producto),

    CONSTRAINT fk_movimientos_lote
        FOREIGN KEY (lote_id)
        REFERENCES lotes(id_lote),

    CONSTRAINT fk_movimientos_tipo
        FOREIGN KEY (tipo_movimiento_id)
        REFERENCES tipos_movimientos(id_tipo_movimiento),

    CONSTRAINT fk_movimientos_usuario
        FOREIGN KEY (usuario_id)
        REFERENCES usuarios(id_usuario),

    CONSTRAINT fk_movimientos_detalle_compra
        FOREIGN KEY (detalle_compra_id)
        REFERENCES detalle_compras(id_detalle_compra),

    CONSTRAINT fk_movimientos_detalle_venta
        FOREIGN KEY (detalle_venta_id)
        REFERENCES detalle_ventas(id_detalle_venta),

    CONSTRAINT ck_movimientos_cantidad
        CHECK (cantidad > 0),

    CONSTRAINT ck_movimientos_origen
        CHECK (
            detalle_compra_id IS NULL
            OR detalle_venta_id IS NULL
        )
);