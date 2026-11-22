#!/usr/bin/env bash
# SIG-TEC — inicialización de PRIMER ARRANQUE.
#
# docker-entrypoint.sh ejecuta este archivo solamente cuando el volumen de datos
# está vacío. Todo lo que debe poder aplicarse también a bases existentes vive en
# sql/migrations/ y lo aplica scripts/db/migrate.sh (idempotente, versionado).
set -Eeuo pipefail

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<'SQL'
CREATE EXTENSION IF NOT EXISTS postgis;
SQL

echo "sigtec-init: base '$POSTGRES_DB' creada con PostGIS $(psql -tA --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -c 'SELECT postgis_lib_version()')"
