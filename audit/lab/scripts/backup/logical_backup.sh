#!/usr/bin/env bash
# =====================================================================
# SIG-TEC · respaldo LÓGICO (pg_dump) de uno o varios nodos
#   uso (en sigtec-tools): scripts/backup/logical_backup.sh [all|campus|<nodo> ...]
#
# Por nodo genera /backups/logical/<nodo>/<UTC>/ con:
#   sigtec.dump   pg_dump formato custom (-Fc) de la base completa sigtec
#   globals.sql   roles del clúster (pg_dumpall --globals-only --no-role-passwords)
#   toc.txt       contenido del archivo (pg_restore --list): prueba de legibilidad
#   manifest.txt  nodo, versiones, tamaño, SHA-256, conteo de filas por capa
# Se conecta con el rol de mínimo privilegio sigtec_backup.
# =====================================================================
. "${SIGTEC_HOME:-/opt/sigtec}/scripts/lib/backup.sh"

backup_node() {
    local node="$1" host dir st size sha counts server seq
    host="$(node_host "$node")"; st="$(stamp)"
    dir="$BACKUP_ROOT/logical/$node/$st"
    mkdir -p "$dir"
    log "pg_dump $node ($host) -> ${dir#"$BACKUP_ROOT"/}"
    export PGPASSWORD="${SIGTEC_BACKUP_PASSWORD:?}"
    pg_dump -h "$host" -U sigtec_backup -d "$SIGTEC_DB" -Fc -Z 6 -f "$dir/sigtec.dump" 2> "$dir/pg_dump.stderr"
    pg_dumpall -h "$host" -U sigtec_backup -l "$SIGTEC_DB" --globals-only --no-role-passwords -f "$dir/globals.sql" 2>> "$dir/pg_dump.stderr"
    pg_restore --list "$dir/sigtec.dump" > "$dir/toc.txt"
    unset PGPASSWORD
    [ -s "$dir/pg_dump.stderr" ] || rm -f "$dir/pg_dump.stderr"

    size="$(stat -c %s "$dir/sigtec.dump")"
    sha="$(sha256sum "$dir/sigtec.dump" | cut -d' ' -f1)"
    server="$(psql_backup "$node" -tAc "SELECT current_setting('server_version')")"
    counts="$(layer_counts psql_backup "$node" "$(node_schema "$node")")"
    seq=""
    node_is_campus "$node" && seq="$(psql_backup "$node" -tAc "SELECT coalesce(pg_sequence_last_value('$(node_schema "$node").objeto_id_seq'), 0)")"
    cat > "$dir/manifest.txt" <<EOF
tipo=logico
nodo=$node
host=$host
base=$SIGTEC_DB
fecha_utc=$st
servidor=$server
pg_dump=$(pg_dump --version)
formato=custom (-Fc -Z 6)
archivo=sigtec.dump
bytes=$size
sha256=$sha
objetos_toc=$(grep -vc '^;' "$dir/toc.txt")
conteos=$counts
secuencia_ultimo=$seq
EOF
    backup_log "$node" pg_dump "${dir#"$BACKUP_ROOT"/}" OK "bytes=$size sha256=${sha:0:16}…"
    log "  OK $node: $size bytes, $(grep -vc '^;' "$dir/toc.txt") entradas TOC${counts:+; $counts}"
}

rc=0
for node in $(nodes_expand "${@:-all}"); do
    if ! ( backup_node "$node" ); then
        rc=1
        backup_log "$node" pg_dump "-" ERROR "ver salida del comando"
        log "  ERROR respaldando $node"
    fi
done
exit "$rc"
