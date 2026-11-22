-- SIG-TEC · migración de campus 0101
-- Tablas ORIGINALES de las ocho capas en el esquema local del campus.
-- Variables: :schema, :campus_id (las entrega scripts/db/migrate.sh)
\ir ../../schema/capas_locales.sql

COMMENT ON SCHEMA :"schema" IS :'schema_comment';
