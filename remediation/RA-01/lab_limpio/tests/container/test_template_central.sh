#!/usr/bin/env bash
# =====================================================================
# SIG-TEC · valida sql/templates/central_copias_locales.sql SIN tocar el
# nodo central: la aplica en un clúster PostgreSQL temporal dentro de
# sigtec-tools y compara columnas, tipos, NOT NULL, valores por omisión y
# restricciones contra las tablas originales de los cinco campus.
# =====================================================================
. "${SIGTEC_HOME:-/opt/sigtec}/scripts/lib/db.sh"

TMP="$(mktemp -d /tmp/sigtec-tpl.XXXXXX)"
chown postgres:postgres "$TMP"
chmod 0755 "$TMP"
PORT=5544
cleanup() { gosu postgres pg_ctl -D "$TMP/data" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$TMP"; }
trap cleanup EXIT

gosu postgres initdb -D "$TMP/data" -U postgres --auth=trust >/dev/null
gosu postgres pg_ctl -D "$TMP/data" -l "$TMP/log" -w \
    -o "-c listen_addresses='' -c unix_socket_directories=$TMP -c port=$PORT" start >/dev/null
tpl() { gosu postgres psql -X -q -v ON_ERROR_STOP=1 -h "$TMP" -p "$PORT" -U postgres "$@"; }

tpl -d postgres -c "CREATE DATABASE sigtec" >/dev/null
tpl -d sigtec -c "CREATE EXTENSION postgis" >/dev/null
( cd "$SIGTEC_HOME/sql/templates" && tpl -d sigtec --single-transaction -f central_copias_locales.sql >/dev/null )

SIG="SELECT 'col' AS k, c.relname, a.attnum::text, a.attname, format_type(a.atttypid, a.atttypmod),
              a.attnotnull::text, coalesce(pg_get_expr(d.adbin, d.adrelid), '')
       FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
       WHERE n.nspname = :'schema' AND c.relkind = 'r' AND a.attnum > 0 AND NOT a.attisdropped
       UNION ALL
       SELECT 'con', c.relname, k.contype::text, k.conname, pg_get_constraintdef(k.oid), '', ''
       FROM pg_constraint k JOIN pg_class c ON c.oid = k.conrelid JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname = :'schema'
       UNION ALL
       SELECT 'rid', c.relname, c.relreplident::text, '', '', '', ''
       FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname = :'schema' AND c.relkind = 'r'
       ORDER BY 1, 2, 3, 4"

echo "$SIG;" > "$TMP/firma.sql"
chmod 0644 "$TMP/firma.sql"
for node in $SIGTEC_CAMPUS_NODES; do
    s="$(node_schema "$node")"
    psql_su "$node" -tA -v schema="$s" -f "$TMP/firma.sql" > "$TMP/$node.campus"
    tpl -d sigtec -tA -v schema="$s" -f "$TMP/firma.sql" > "$TMP/$node.central"
    if ! diff -u "$TMP/$node.campus" "$TMP/$node.central" > "$TMP/$node.diff"; then
        echo "diferencias en $s:"; cat "$TMP/$node.diff"; exit 1
    fi
    [ -s "$TMP/$node.campus" ] || { echo "sin estructura en $s"; exit 1; }
done
echo "plantilla aplicada en clúster temporal: 5 esquemas × 8 tablas idénticos a los originales (columnas, tipos, NOT NULL, defaults, PK, CHECK, replica identity)"
