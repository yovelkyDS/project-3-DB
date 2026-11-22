-- =====================================================================
-- SIG-TEC · PLANTILLA para el Integrante 2 (NO se aplica automáticamente)
--
-- Crea en el NODO CENTRAL las tablas destino del nivel 1 de replicación:
-- local_cartago.*, local_san_jose.*, local_san_carlos.*, local_alajuela.*,
-- local_limon.* con exactamente el mismo nombre calificado, columnas, tipos,
-- clave primaria y restricciones que las tablas originales de cada campus.
--
-- Uso (desde la raíz del repositorio):
--   docker compose --profile tools run --rm -T sigtec-tools -c \
--     'PGPASSWORD=$POSTGRES_PASSWORD psql -h pg-central -U postgres -d sigtec \
--        --single-transaction -v ON_ERROR_STOP=1 -f sql/templates/central_copias_locales.sql'
--
-- Diferencias deliberadas con las tablas originales:
--   * NO se crea la secuencia objeto_id_seq ni los disparadores de id:
--     el id llega ya asignado desde el campus dueño por replicación.
--   * REPLICA IDENTITY: se usa la de omisión (clave primaria "id"), suficiente
--     para replicar UPDATE y DELETE; las tablas originales también la usan.
--   * Las tablas copia no deben editarse directamente.
--
-- Validada automáticamente por tests/container/test_template_central.sh
-- (se aplica en un clúster temporal y se compara con los cinco campus).
-- =====================================================================

\set schema local_cartago
\set campus_id 1
\ir ../schema/capas_locales.sql
COMMENT ON SCHEMA local_cartago IS 'SIG-TEC: copia de consulta (replicación nivel 1) de Cartago, campus_id 1.';

\set schema local_san_jose
\set campus_id 2
\ir ../schema/capas_locales.sql
COMMENT ON SCHEMA local_san_jose IS 'SIG-TEC: copia de consulta (replicación nivel 1) de San José, campus_id 2.';

\set schema local_san_carlos
\set campus_id 3
\ir ../schema/capas_locales.sql
COMMENT ON SCHEMA local_san_carlos IS 'SIG-TEC: copia de consulta (replicación nivel 1) de San Carlos, campus_id 3.';

\set schema local_alajuela
\set campus_id 4
\ir ../schema/capas_locales.sql
COMMENT ON SCHEMA local_alajuela IS 'SIG-TEC: copia de consulta (replicación nivel 1) de Alajuela, campus_id 4.';

\set schema local_limon
\set campus_id 5
\ir ../schema/capas_locales.sql
COMMENT ON SCHEMA local_limon IS 'SIG-TEC: copia de consulta (replicación nivel 1) de Limón, campus_id 5.';
