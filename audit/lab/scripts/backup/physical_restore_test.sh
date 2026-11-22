#!/usr/bin/env bash
# =====================================================================
# SIG-TEC · PRUEBA DE RECUPERACIÓN FÍSICA en un entorno aislado
#   uso (en sigtec-tools): scripts/backup/physical_restore_test.sh [all|campus|<nodo> ...]
#
# Para cada nodo copia el pg_basebackup más reciente a un directorio temporal,
# configura restore_command contra el WAL archivado (/archives/<nodo>),
# recovery_target='immediate' (punto consistente al final de la copia) y
# arranca PostgreSQL. Verifica que se promueva, que PostGIS funcione y que
# conteos, secuencia y validación espacial coincidan con info.txt.
# El nodo en servicio y su archivo WAL NO se modifican.
# =====================================================================
. "${SIGTEC_HOME:-/opt/sigtec}/scripts/lib/backup.sh"

test_node() {
    local node="$1" dir tmp errors=0 port=5547 i got expected schema cid
    dir="$(latest_dir "$BACKUP_ROOT/physical/$node")"
    [ -n "$dir" ] && [ -f "$dir/data/PG_VERSION" ] || die "no hay pg_basebackup para $node (make backup-physical NODE=$node)"
    log "recuperación física de prueba: $node <- ${dir#"$BACKUP_ROOT"/} + WAL /archives/$node"

    tmp="$(mktemp -d /tmp/sigtec-restore-fisico.XXXXXX)"; chmod 0755 "$tmp"
    trap 'stop_temp_cluster; rm -rf "$tmp"' RETURN
    cp -a "$dir/data" "$tmp/data"
    rm -f "$tmp/data/backup_manifest"
    cat >> "$tmp/data/postgresql.auto.conf" <<EOF
# --- SIG-TEC: prueba de recuperación física ---
restore_command = 'cp $ARCHIVE_ROOT/$node/%f "%p"'
recovery_target = 'immediate'
recovery_target_action = 'promote'
EOF
    touch "$tmp/data/recovery.signal"
    chown -R postgres:postgres "$tmp"; chmod 0700 "$tmp/data"; chmod 0755 "$tmp"
    start_temp_cluster "$tmp/data" "$port" \
        "-c config_file=/etc/postgresql/postgresql.conf -c ssl=off -c archive_mode=off -c cluster_name=sigtec-restore-test"

    for i in $(seq 1 120); do
        [ "$(tmp_psql sigtec -tAc 'SELECT pg_is_in_recovery()' 2>/dev/null)" = "f" ] && break
        sleep 1
    done
    if [ "$(tmp_psql sigtec -tAc 'SELECT pg_is_in_recovery()')" = "f" ]; then
        log "  recuperación completada y promovida ($(grep -m1 -E 'consistent recovery state|recovery stopping' "$tmp/server.log" | sed 's/.*LOG:  //'))"
    else
        log "  FALLA: la instancia no salió de recuperación"; errors=$((errors+1))
    fi
    tmp_psql sigtec -tAc "SELECT postgis_lib_version()" | grep -qx '3.5.4' || { log "  FALLA PostGIS"; errors=$((errors+1)); }
    got="$(tmp_psql sigtec -tAc "SELECT node_code FROM ops.node_info")"
    [ "$got" = "$node" ] || { log "  FALLA node_info=$got"; errors=$((errors+1)); }
    got="$(tmp_psql sigtec -tAc "SELECT timeline_id FROM pg_control_checkpoint()")"
    log "  línea de tiempo tras la promoción: $got"

    if node_is_campus "$node"; then
        schema="$(node_schema "$node")"; cid="$(node_campus_id "$node")"
        expected="$(sed -n 's/^conteos=//p' "$dir/info.txt")"
        got="$(layer_counts tmp_psql sigtec "$schema")"
        [ "$expected" = "$got" ] && log "  conteos por capa idénticos a la copia: $got" \
                                 || { log "  FALLA conteos: [$expected] vs [$got]"; errors=$((errors+1)); }
        got="$(tmp_psql sigtec -tA -v schema="$schema" -v campus_id="$cid" -f "$SIGTEC_HOME/sql/checks/validacion_capas.sql" | awk -F'|' '$NF != "OK"' | wc -l)"
        [ "$got" = 0 ] && log "  validación espacial: 8/8 capas OK" || { log "  FALLA validación ($got capas)"; errors=$((errors+1)); }
    fi
    if [ "$errors" = 0 ]; then
        backup_log "$node" restore_test_fisico "${dir#"$BACKUP_ROOT"/}" OK "recovery_target=immediate, promovido, datos verificados"
        log "  RESULTADO $node: copia física RECUPERABLE"
    else
        backup_log "$node" restore_test_fisico "${dir#"$BACKUP_ROOT"/}" ERROR "$errors comprobaciones fallidas"
        tail -20 "$tmp/server.log" >&2
        return 1
    fi
}

rc=0
for node in $(nodes_expand "${@:-all}"); do
    ( test_node "$node" ) || { rc=1; log "  RESULTADO $node: FALLÓ"; }
done
exit "$rc"
