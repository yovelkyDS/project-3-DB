#!/bin/bash
# Only runs in a --network none disposable container; dump input is read-only.
set -Eeuo pipefail
tmp=$(mktemp -d /tmp/reaudit-legacy.XXXXXX)
chown postgres:postgres "$tmp"; chmod 0755 "$tmp"
gosu postgres initdb -D "$tmp/data" -U postgres --auth=trust >/dev/null
gosu postgres pg_ctl -D "$tmp/data" -l "$tmp/server.log" -w -o "-c listen_addresses='' -c unix_socket_directories=$tmp -c cluster_name=reaudit-legacy-recovery" start >/dev/null
q() { psql -X -qAt -h "$tmp" -U postgres -d sigtec -v ON_ERROR_STOP=1 -v VERBOSITY=verbose "$@"; }
psql -X -q -h "$tmp" -U postgres -d postgres -c 'CREATE DATABASE sigtec' -c 'CREATE ROLE sigtec_backup'
pg_restore -h "$tmp" -U postgres -d sigtec --exit-on-error /input.dump
q -c "SELECT version FROM ops.schema_migrations ORDER BY version; SELECT to_regclass('ops.identificadores_globales') IS NULL AS registro_ausente; CREATE ROLE reaudit_legacy_editor NOLOGIN; GRANT USAGE ON SCHEMA local_san_carlos TO reaudit_legacy_editor; GRANT SELECT,INSERT ON local_san_carlos.puntos_interes,local_san_carlos.iluminacion TO reaudit_legacy_editor; SELECT has_sequence_privilege('reaudit_legacy_editor','local_san_carlos.objeto_id_seq','USAGE');"
id=$(q -c "SELECT 3000000000 + nextval('local_san_carlos.objeto_id_seq')")
q <<SQL > "$tmp/first.out" 2>&1 &
BEGIN; SET ROLE reaudit_legacy_editor; SET LOCAL sigtec.permitir_id_explicito=on;
INSERT INTO local_san_carlos.puntos_interes(id,nombre,tipo,geom) VALUES ($id,'REAUDIT LEGACY','otro',ST_SetSRID(ST_MakePoint(510000,1090000),5367));
SELECT pg_sleep(3); COMMIT;
SQL
first=$!
sleep 1
set +e
q <<SQL
BEGIN; SET ROLE reaudit_legacy_editor; SET LOCAL sigtec.permitir_id_explicito=on;
INSERT INTO local_san_carlos.iluminacion(id,codigo,potencia,estado,geom) VALUES ($id,'REAUDIT-LEGACY',100,'funcional',ST_SetSRID(ST_MakePoint(510000,1090000),5367)); COMMIT;
SQL
second_rc=$?
wait "$first"; first_rc=$?
set -e
echo FIRST_RC=$first_rc SECOND_RC=$second_rc
cat "$tmp/first.out"
rows=$(q -c "SELECT (SELECT count(*) FROM local_san_carlos.puntos_interes WHERE id=$id)+(SELECT count(*) FROM local_san_carlos.iluminacion WHERE id=$id)")
echo LEGACY_DUPLICATE_ID=$id CONFIRMED_ROWS=$rows
[ "$first_rc" = 0 ] && [ "$second_rc" = 0 ] && [ "$rows" = 2 ]
gosu postgres pg_ctl -D "$tmp/data" -m fast -w stop >/dev/null
