#!/bin/bash
set -euo pipefail
root=$(pwd)
c=(docker compose --project-directory "$root/audit/lab" -f "$root/audit/lab/compose.yaml")
"${c[@]}" --profile tools run --rm -T sigtec-tools -c '. scripts/lib/db.sh
psql_su central --single-transaction -f sql/templates/central_copias_locales.sql
psql_su san_jose <<SQL
BEGIN;
CREATE PUBLICATION audit_publication_probe FOR TABLES IN SCHEMA local_san_jose;
SELECT pubname,schemaname,tablename FROM pg_publication_tables WHERE pubname = '\''audit_publication_probe'\'' ORDER BY tablename;
ROLLBACK;
SQL
psql_su central -tAc "SELECT count(*) FROM geometry_columns WHERE f_table_schema LIKE '\''local_%'\''"
'
