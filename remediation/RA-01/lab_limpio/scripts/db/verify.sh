#!/usr/bin/env bash
# =====================================================================
# SIG-TEC · verificación rápida de los nodos (versiones, PostGIS, capas,
# migraciones pendientes y registro global de identificadores)
#   uso (en sigtec-tools): scripts/db/verify.sh [all|campus|recovery|<nodo> ...]
# Para un nodo recuperado:  scripts/db/verify.sh recovery
# Sale con código 1 si algún nodo o capa falla, si quedan migraciones
# pendientes o si la migración 0103 no está operativa en un campus.
# Una pg-recovery solo se declara apta para entregar cuando todo pasa.
# =====================================================================
. "${SIGTEC_HOME:-/opt/sigtec}/scripts/lib/db.sh"
shopt -s inherit_errexit

rc=0
targets="${*:-all}"
[ "$targets" = "recovery" ] || targets="$(nodes_expand "$targets")"

# Migraciones del repositorio que el nodo (identidad lógica $2) aún no registra
pending() {
    local t="$1" l="$2" applied f v
    applied=" $(sql_value "$t" "SELECT coalesce(string_agg(version, ' '), '') FROM ops.schema_migrations") "
    for f in "$SIGTEC_HOME"/sql/migrations/common/*.sql; do
        v="${f#"$SIGTEC_HOME/sql/migrations/"}"; v="${v%.sql}"
        case "$applied" in *" $v "*) ;; *) echo "$v" ;; esac
    done
    if [ "$l" != central ]; then
        for f in "$SIGTEC_HOME"/sql/migrations/campus/*.sql; do
            v="${f#"$SIGTEC_HOME/sql/migrations/"}"; v="${v%.sql}"
            case "$applied" in *" $v "*) ;; *) echo "$v" ;; esac
        done
    fi
}

for node in $targets; do
    node_rc=0
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
    pend="$(pending "$node" "$code" | tr '\n' ' ' | sed 's/ $//')"
    if [ -n "$pend" ]; then
        echo "MIGRACIONES PENDIENTES: $pend   (ejecute: make migrate NODE=$node)"
        node_rc=1
    else
        echo "migraciones: todas aplicadas ($(sql_value "$node" "SELECT count(*) FROM ops.schema_migrations"))"
    fi
    if [ "$schema" != "-" ]; then
        out="$(psql_su "$node" -P pager=off -v schema="$schema" -v campus_id="$cid" -f "$SIGTEC_HOME/sql/checks/validacion_capas.sql")"
        echo "$out"
        echo "$out" | grep -q 'ERROR' && node_rc=1
        echo "$out" | grep -q '(8 rows)' || node_rc=1
        if [ "$(sql_value "$node" "SELECT to_regclass('ops.identificadores_globales') IS NOT NULL")" = t ]; then
            out="$(psql_su "$node" -P pager=off -v schema="$schema" -f "$SIGTEC_HOME/sql/checks/verificar_registro_ids.sql")"
            echo "$out"
            echo "$out" | grep -q ' OK *$' || node_rc=1
            out="$(psql_su "$node" -v schema="$schema" -v campus_id="$cid" -f "$SIGTEC_HOME/sql/checks/verificar_0103.sql")"
            echo "$out" | sed 's/^/  /'
            echo "$out" | grep -q '^FAIL' && node_rc=1
        elif [ -f "$SIGTEC_HOME/sql/migrations/campus/0103_registro_identificadores.sql" ]; then
            echo "FALTA el registro global de identificadores (migración 0103): el nodo admite ids repetidos entre capas"
            node_rc=1
        else
            echo "(registro global de identificadores no disponible en esta versión del código)"
        fi
    fi
    if [ "$node" = recovery ]; then
        if [ "$node_rc" = 0 ] && [ "$(sql_value recovery "SELECT pg_is_in_recovery()")" = f ]; then
            echo "pg-recovery: promovida, esquema al día, capas válidas y registro de ids íntegro: apta para entregar al Integrante 2 (la reincorporación a la replicación no está demostrada)"
        else
            echo "pg-recovery: NO APTA para entregar ni reincorporar hasta corregir lo anterior (make migrate NODE=recovery)"
        fi
    fi
    [ "$node_rc" = 0 ] || rc=1
done
exit "$rc"
