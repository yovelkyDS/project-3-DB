#!/usr/bin/env bash
# =====================================================================
# SIG-TEC · respaldo FÍSICO (pg_basebackup) de uno o varios nodos
#   uso (en sigtec-tools): scripts/backup/physical_backup.sh [all|campus|<nodo> ...]
#
# Por nodo genera /backups/physical/<nodo>/<UTC>/:
#   data/      copia base en formato plano (-Fp) con el WAL necesario (-X stream)
#              y backup_manifest con sumas SHA-256
#   info.txt   LSN/segmento de inicio, línea de tiempo, conteos por capa, verificación
# La copia sirve como base del PITR junto con el WAL archivado en /archives/<nodo>.
# Se conecta con sigtec_backup (atributo REPLICATION, sin superusuario).
#
# Comportamiento ante fallos (corrección F-01): etapas comprobadas
# explícitamente y con errexit/pipefail activos (run_step); la copia se escribe
# en .en-curso-*, se valida (estructura + pg_verifybackup) y solo entonces se
# publica con un rename atómico y se registra OK. Un fallo deja .fallido-*
# sin la carga útil y el script termina con código distinto de 0.
# =====================================================================
. "${SIGTEC_HOME:-/opt/sigtec}/scripts/lib/backup.sh"

backup_node() {
    local node="$1" host base work final st label start_wal start_time tli counts size seq verif
    host="$(node_host "$node")"; st="$(stamp)"
    base="$BACKUP_ROOT/physical/$node"
    work="$(work_dir_for "$base" "$st")"
    label="sigtec-$node-$st"
    mkdir -p "$base" || fail "no se puede crear $base"
    mkdir "$work" || fail "no se puede crear el directorio de trabajo en $base"
    trap 'discard_work_dir "$work" "$base" "$st" data info.txt' ERR
    log "pg_basebackup $node ($host) -> ${base#"$BACKUP_ROOT"/}/$st/data"

    PGPASSWORD="${SIGTEC_BACKUP_PASSWORD:?}" pg_basebackup -h "$host" -U "$SIGTEC_BACKUP_USER" \
        -D "$work/data" -Fp -X stream -c fast -l "$label" --manifest-checksums=SHA256 --no-password \
        2> "$work/pg_basebackup.stderr" \
        || { show_diag "$work/pg_basebackup.stderr"; fail "pg_basebackup terminó con error"; }
    [ -s "$work/pg_basebackup.stderr" ] || rm -f "$work/pg_basebackup.stderr"

    validate_physical_dir "$work"
    verif="$(tail -1 "$work/pg_verifybackup.txt")"
    log "  pg_verifybackup: $verif"

    start_wal="$(sed -n 's/^START WAL LOCATION: \(.*\)$/\1/p' "$work/data/backup_label")"
    start_time="$(sed -n 's/^START TIME: //p' "$work/data/backup_label")"
    tli="$(sed -n 's/^START TIMELINE: //p' "$work/data/backup_label")"
    [ -n "$start_wal" ] && [ -n "$tli" ] || fail "backup_label incompleto"
    size="$(du -sb "$work/data" | cut -f1)"
    # Metadatos informativos del nodo (consultados después de la copia).
    counts="$(layer_counts psql_backup "$node" "$(node_schema "$node")")"
    seq=""
    if node_is_campus "$node"; then
        seq="$(psql_backup "$node" -tAc "SELECT coalesce(pg_sequence_last_value('$(node_schema "$node").objeto_id_seq'), 0)")"
    fi
    cat > "$work/info.txt" <<EOF
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
verificacion=$verif
archivo_wal=/archives/$node
conteos=$counts
secuencia_ultimo=$seq
EOF

    final="$(publish_dir "$work" "$base" "$st")"
    trap - ERR
    backup_log "$node" pg_basebackup "${final#"$BACKUP_ROOT"/}" OK "bytes=$size wal_inicio=${start_wal%% *}; $verif"
    log "  OK $node: $(( size / 1024 / 1024 )) MiB, inicio $start_wal, verificado"
}

rc=0
for node in $(nodes_expand "${@:-all}"); do
    run_step backup_node "$node"
    if [ "$RUN_RC" != 0 ]; then
        rc=1
        backup_log_safe "$node" pg_basebackup "-" ERROR "copia NO generada (código $RUN_RC); ver salida del comando"
        log "  ERROR respaldando $node: no se publicó ninguna copia"
    fi
done
[ "$rc" = 0 ] || log "RESULTADO: una o más copias físicas FALLARON"
exit "$rc"
