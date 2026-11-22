-- =====================================================================
-- SIG-TEC · bootstrap (idempotente, se ejecuta en cada migración)
-- Crea el esquema operativo "ops" y el registro de migraciones aplicadas.
--
-- "ops" es infraestructura del Integrante 1 (operación, respaldos, pruebas).
-- No contiene datos geográficos y NO debe incluirse en publicaciones lógicas.
-- =====================================================================
CREATE SCHEMA IF NOT EXISTS ops;
COMMENT ON SCHEMA ops IS
  'SIG-TEC: metadatos operativos del nodo (migraciones, identidad, datos de prueba, marcas de recuperación). No replicar.';
REVOKE ALL ON SCHEMA ops FROM PUBLIC;

CREATE TABLE IF NOT EXISTS ops.schema_migrations (
    version     text PRIMARY KEY,
    checksum    text        NOT NULL,
    applied_at  timestamptz NOT NULL DEFAULT clock_timestamp(),
    applied_by  text        NOT NULL DEFAULT current_user
);
COMMENT ON TABLE ops.schema_migrations IS
  'Migraciones aplicadas por scripts/db/migrate.sh (versión y SHA-256 del archivo).';
