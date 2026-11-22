#!/usr/bin/env bash
# =====================================================================
# SIG-TEC · respaldo FÍSICO (pg_basebackup) de uno o varios nodos
#   uso (en sigtec-tools): scripts/backup/physical_backup.sh [all|campus|<nodo> ...]
#
# Por nodo genera /backups/physical/<nodo>/<UTC>/:
#   data/      copia base en formato plano (-Fp) con el WAL necesario (-X stream)
#              y backup_manifest con sumas SHA-256
#   info.txt   LSN/segmento de inicio, línea de tiempo, conteos por capa, verificación
# Luego ejecuta pg_verifybackup (manifiesto + WAL). La copia sirve como base
# del PITR junto con el WAL archivado continuamente en /archives/<nodo>.
# Se conecta con sigtec_backup (atributo REPLICATION, sin superusuario).
# =====================================================================
. "${SIGTEC_HOME:-/opt/sigtec}/scripts/lib/backup.sh"

backup_node() {
    local node="$1" host dir st label start_wal start_time tli counts size seq
    host="$(node_host "$node")"; st="$(stamp)"
    dir="$BACKUP_ROOT/physical/$node/$st"
    label="sigtec-$node-$st"
    mkdir -p "$dir"
    log "pg_basebackup $node ($host) -> ${dir#"$BACKUP_ROOT"/}/data"
    PGPASSWORD="${SIGTEC_BACKUP_PASSWORD:?}" pg_basebackup -h "$host" -U sigtec_backup \
        -D "$dir/data" -Fp -X stream -c fast -l "$label" --manifest-checksums=SHA256 --no-password 2> "$dir/pg_basebackup.stderr"
    [ -s "$dir/pg_basebackup.stderr" ] || rm -f "$dir/pg_basebackup.stderr"

    pg_verifybackup "$dir/data" > "$dir/pg_verifybackup.txt" 2>&1
    log "  pg_verifybackup: $(tail -1 "$dir/pg_verifybackup.txt")"

    start_wal="$(sed -n 's/^START WAL LOCATION: \(.*\)$/\1/p' "$dir/data/backup_label")"
    start_time="$(sed -n 's/^START TIME: //p' "$dir/data/backup_label")"
    tli="$(sed -n 's/^START TIMELINE: //p' "$dir/data/backup_label")"
    size="$(du -sb "$dir/data" | cut -f1)"
    counts="$(layer_counts psql_backup "$node" "$(node_schema "$node")")"
    seq=""
    node_is_campus "$node" && seq="$(psql_backup "$node" -tAc "SELECT coalesce(pg_sequence_last_value('$(node_schema "$node").objeto_id_seq'), 0)")"
    cat > "$dir/info.txt" <<EOF
tipo=fisico
nodo=$node
host=$host
etiqueta=$label
fecha_utc=$st
inicio=$start_time
wal_inicio=$start_wal
timeline=$tli
formato=plano (-Fp), WAL incluido (-X stream), manifiesto SHA-256
bytes=$size
pg_basebackup=$(pg_basebackup --version)
verificacion=$(tail -1 "$dir/pg_verifybackup.txt")
archivo_wal=/archives/$node
conteos=$counts
secuencia_ultimo=$seq
EOF
    backup_log "$node" pg_basebackup "${dir#"$BACKUP_ROOT"/}" OK "bytes=$size wal_inicio=${start_wal%% *}; $(tail -1 "$dir/pg_verifybackup.txt")"
    log "  OK $node: $(( size / 1024 / 1024 )) MiB, inicio $start_wal"
}

rc=0
for node in $(nodes_expand "${@:-all}"); do
    if ! ( backup_node "$node" ); then
        rc=1
        backup_log "$node" pg_basebackup "-" ERROR "ver salida del comando"
        log "  ERROR respaldando $node"
    fi
done
exit "$rc"
