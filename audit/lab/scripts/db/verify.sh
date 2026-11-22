#!/usr/bin/env bash
# =====================================================================
# SIG-TEC · verificación rápida de los nodos (versiones, PostGIS, capas)
#   uso (en sigtec-tools): scripts/db/verify.sh [all|campus|recovery|<nodo> ...]
# Para un nodo recuperado:  scripts/db/verify.sh recovery
# Sale con código 1 si algún nodo o capa falla.
# =====================================================================
. "${SIGTEC_HOME:-/opt/sigtec}/scripts/lib/db.sh"

rc=0
targets="${*:-all}"
[ "$targets" = "recovery" ] || targets="$(nodes_expand "$targets")"

for node in $targets; do
    wait_node "$node" 60
    info="$(sql_value "$node" "SELECT node_code || '|' || coalesce(campus_id::text,'-') || '|' || coalesce(local_schema,'-') FROM ops.node_info")"
    code="${info%%|*}"; rest="${info#*|}"; cid="${rest%%|*}"; schema="${rest#*|}"
    printf '\n== %s (%s) · nodo=%s campus_id=%s ==\n' "$node" "$(target_host "$node")" "$code" "$cid"
    psql_su "$node" -P pager=off -c "
        SELECT current_setting('server_version') AS postgresql,
               postgis_lib_version()              AS postgis,
               current_setting('wal_level')       AS wal_level,
               current_setting('archive_mode')    AS archive_mode,
               (SELECT archived_count FROM pg_stat_archiver) AS wal_archivados,
               (SELECT failed_count   FROM pg_stat_archiver) AS archivado_fallido,
               pg_is_in_recovery()                AS en_recuperacion"
    if [ "$schema" != "-" ]; then
        out="$(psql_su "$node" -P pager=off -v schema="$schema" -v campus_id="$cid" -f "$SIGTEC_HOME/sql/checks/validacion_capas.sql")"
        echo "$out"
        echo "$out" | grep -q 'ERROR' && rc=1
        echo "$out" | grep -q '(8 rows)' || rc=1
    fi
done
exit "$rc"
