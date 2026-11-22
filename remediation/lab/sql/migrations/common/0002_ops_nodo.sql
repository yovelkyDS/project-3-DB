-- SIG-TEC · migración común 0002
-- Identidad del nodo, registro de datos de prueba y marcas de recuperación.

CREATE TABLE ops.node_info (
    singleton      boolean     PRIMARY KEY DEFAULT true CHECK (singleton),
    node_code      text        NOT NULL CHECK (node_code IN ('central','cartago','san_jose','san_carlos','alajuela','limon')),
    node_host      text        NOT NULL,
    campus_id      smallint    NULL CHECK (campus_id BETWEEN 1 AND 5),
    campus_nombre  text        NULL,
    local_schema   text        NULL,
    srid           integer     NOT NULL DEFAULT 5367,
    updated_at     timestamptz NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT node_info_central_ck CHECK (
        (node_code = 'central' AND campus_id IS NULL AND local_schema IS NULL)
     OR (node_code <> 'central' AND campus_id IS NOT NULL AND local_schema = 'local_' || node_code)
    )
);
COMMENT ON TABLE ops.node_info IS
  'Identidad de este nodo SIG-TEC (una sola fila). La mantiene scripts/db/migrate.sh.';

CREATE TABLE ops.seed_runs (
    seed_name    text        PRIMARY KEY,
    applied_at   timestamptz NOT NULL DEFAULT clock_timestamp(),
    filas        integer     NOT NULL,
    descripcion  text        NOT NULL
);
COMMENT ON TABLE ops.seed_runs IS
  'Conjuntos de datos de prueba cargados. Un conjunto registrado no se vuelve a cargar (idempotencia).';

CREATE TABLE ops.recovery_markers (
    id             bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    run_id         text        NOT NULL,
    marker         text        NOT NULL,
    detalle        text        NULL,
    lsn            pg_lsn      NULL,
    registrado_en  timestamptz NOT NULL DEFAULT clock_timestamp()
);
COMMENT ON TABLE ops.recovery_markers IS
  'Marcas verificables de las pruebas de respaldo/PITR (cambio A, instante objetivo, cambio B, recuperación).';
