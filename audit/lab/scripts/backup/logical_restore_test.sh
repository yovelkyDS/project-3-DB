#!/usr/bin/env bash
# =====================================================================
# SIG-TEC · PRUEBA DE RESTAURACIÓN LÓGICA en un entorno aislado
#   uso (en sigtec-tools): scripts/backup/logical_restore_test.sh [all|campus|<nodo> ...] [--dump <ruta>]
#
# Para cada nodo toma el pg_dump más reciente (o --dump), crea un clúster
# PostgreSQL temporal dentro de sigtec-tools, restaura globals.sql +
# sigtec.dump con pg_restore y verifica:
#   * SHA-256 del archivo = manifiesto
#   * PostGIS 3.5.4 restaurado, ops.node_info del nodo correcto
#   * conteo de filas por capa = manifiesto; validación espacial OK
#   * secuencia de ids restaurada al mismo valor
# Los nodos en servicio NO se tocan.
# =====================================================================
. "${SIGTEC_HOME:-/opt/sigtec}/scripts/lib/backup.sh"

DUMP_DIR=""; args=()
while [ $# -gt 0 ]; do
    case "$1" in --dump) DUMP_DIR="$(dirname "$2")"; shift 2 ;; *) args+=("$1"); shift ;; esac
done

test_node() {
    local node="$1" dir tmp schema cid expected got sha errors=0 port=5546
    dir="${DUMP_DIR:-$(latest_dir "$BACKUP_ROOT/logical/$node")}"
    [ -n "$dir" ] && [ -f "$dir/sigtec.dump" ] || die "no hay pg_dump para $node (ejecute make backup-logical NODE=$node)"
    log "restauración lógica de prueba: $node <- ${dir#"$BACKUP_ROOT"/}"

    sha="$(sha256sum "$dir/sigtec.dump" | cut -d' ' -f1)"
    [ "$sha" = "$(sed -n 's/^sha256=//p' "$dir/manifest.txt")" ] || die "SHA-256 no coincide con el manifiesto"
    log "  SHA-256 verificado"

    tmp="$(mktemp -d /tmp/sigtec-restore-logico.XXXXXX)"; chown postgres:postgres "$tmp"; chmod 0755 "$tmp"
    trap 'stop_temp_cluster; rm -rf "$tmp"' RETURN
    gosu postgres initdb -D "$tmp/data" -U postgres --auth=trust --data-checksums >/dev/null
    start_temp_cluster "$tmp/data" "$port" "-c wal_level=logical"
    cp "$dir/sigtec.dump" "$dir/globals.sql" "$tmp/"; chown postgres "$tmp/sigtec.dump" "$tmp/globals.sql"

    # Roles: "postgres" ya existe en el clúster nuevo; ese error es esperado e inocuo.
    tmp_psql postgres -v ON_ERROR_STOP=0 -f "$tmp/globals.sql" > "$tmp/globals.out" 2>&1 || true
    tmp_psql postgres -c "CREATE DATABASE sigtec"
    gosu postgres pg_restore -h "$tmp" -p "$port" -U postgres -d sigtec --exit-on-error \
        --no-subscriptions "$tmp/sigtec.dump"
    log "  pg_restore terminado sin errores"

    tmp_psql sigtec -tAc "SELECT postgis_lib_version()" | grep -qx '3.5.4' || { log "  FALLA: PostGIS"; errors=$((errors+1)); }
    got="$(tmp_psql sigtec -tAc "SELECT node_code FROM ops.node_info")"
    [ "$got" = "$node" ] || { log "  FALLA: node_info=$got"; errors=$((errors+1)); }

    if node_is_campus "$node"; then
        schema="$(node_schema "$node")"; cid="$(node_campus_id "$node")"
        expected="$(sed -n 's/^conteos=//p' "$dir/manifest.txt")"
        got="$(layer_counts tmp_psql sigtec "$schema")"
        if [ "$expected" = "$got" ]; then log "  conteos por capa idénticos: $got"
        else log "  FALLA conteos: esperado [$expected] obtenido [$got]"; errors=$((errors+1)); fi
        got="$(tmp_psql sigtec -tA -v schema="$schema" -v campus_id="$cid" -f "$SIGTEC_HOME/sql/checks/validacion_capas.sql" | awk -F'|' '$NF != "OK"' | wc -l)"
        [ "$got" = 0 ] && log "  validación espacial: 8/8 capas OK" || { log "  FALLA validación espacial ($got capas)"; errors=$((errors+1)); }
        expected="$(sed -n 's/^secuencia_ultimo=//p' "$dir/manifest.txt")"
        got="$(tmp_psql sigtec -tAc "SELECT coalesce(pg_sequence_last_value('$schema.objeto_id_seq'),0)")"
        [ "$expected" = "$got" ] && log "  secuencia de ids restaurada (último consecutivo $got)" || { log "  FALLA secuencia $expected != $got"; errors=$((errors+1)); }
        got="$(tmp_psql sigtec -tAc "SELECT count(*) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='$schema' AND NOT t.tgisinternal")"
        [ "$got" = 16 ] && log "  disparadores de identificadores restaurados (16)" || { log "  FALLA disparadores=$got"; errors=$((errors+1)); }
    fi

    if [ "$errors" = 0 ]; then
        backup_log "$node" restore_test_logico "${dir#"$BACKUP_ROOT"/}" OK "clúster temporal; conteos, PostGIS, validación y secuencia verificados"
        log "  RESULTADO $node: restauración lógica VÁLIDA"
    else
        backup_log "$node" restore_test_logico "${dir#"$BACKUP_ROOT"/}" ERROR "$errors comprobaciones fallidas"
        return 1
    fi
}

rc=0
for node in $(nodes_expand "${args[@]:-all}"); do
    ( test_node "$node" ) || { rc=1; log "  RESULTADO $node: FALLÓ"; }
done
exit "$rc"
