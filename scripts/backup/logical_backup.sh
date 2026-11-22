#!/usr/bin/env bash
# =====================================================================
# SIG-TEC · respaldo LÓGICO (pg_dump) de uno o varios nodos
#   uso (en sigtec-tools): scripts/backup/logical_backup.sh [all|campus|<nodo> ...]
#
# Por nodo genera /backups/logical/<nodo>/<UTC>/ con:
#   sigtec.dump   pg_dump formato custom (-Fc) de la base completa sigtec
#   globals.sql   roles del clúster (pg_dumpall --globals-only --no-role-passwords)
#   toc.txt       contenido del archivo (pg_restore --list)
#   manifest.txt  nodo, versiones, tamaño, SHA-256, conteo de filas por capa
# Se conecta con el rol de mínimo privilegio sigtec_backup.
#
# Comportamiento ante fallos (corrección F-01):
#   * cada etapa crítica se comprueba explícitamente y además corre con
#     errexit/pipefail activos (run_step); un fallo aborta SOLO ese nodo;
#   * el respaldo se escribe en .en-curso-*; se valida (TOC + lectura completa
#     de los datos + contenido esperado) y solo entonces se publica con un
#     rename atómico y se registra OK; un fallo deja .fallido-* sin la carga útil;
#   * el código de salida es distinto de 0 si algún nodo falló.
# =====================================================================
. "${SIGTEC_HOME:-/opt/sigtec}/scripts/lib/backup.sh"

backup_node() {
    local node="$1" host base work final st size sha counts server seq toc_n
    host="$(node_host "$node")"; st="$(stamp)"
    base="$BACKUP_ROOT/logical/$node"
    work="$(work_dir_for "$base" "$st")"
    mkdir -p "$base" || fail "no se puede crear $base"
    mkdir "$work" || fail "no se puede crear el directorio de trabajo en $base"
    trap 'discard_work_dir "$work" "$base" "$st" sigtec.dump globals.sql toc.txt manifest.txt' ERR
    log "pg_dump $node ($host) -> ${base#"$BACKUP_ROOT"/}/$st"

    PGPASSWORD="${SIGTEC_BACKUP_PASSWORD:?}" pg_dump -h "$host" -U "$SIGTEC_BACKUP_USER" -d "$SIGTEC_DB" \
        --no-password -Fc -Z 6 -f "$work/sigtec.dump" 2> "$work/pg_dump.stderr" \
        || { show_diag "$work/pg_dump.stderr"; fail "pg_dump terminó con error"; }
    PGPASSWORD="${SIGTEC_BACKUP_PASSWORD:?}" pg_dumpall -h "$host" -U "$SIGTEC_BACKUP_USER" -l "$SIGTEC_DB" \
        --no-password --globals-only --no-role-passwords -f "$work/globals.sql" 2>> "$work/pg_dump.stderr" \
        || { show_diag "$work/pg_dump.stderr"; fail "pg_dumpall --globals-only terminó con error"; }
    [ -s "$work/pg_dump.stderr" ] || rm -f "$work/pg_dump.stderr"

    validate_logical_dir "$work" "$node"

    size="$(stat -c %s "$work/sigtec.dump")"
    sha="$(sha256sum "$work/sigtec.dump" | cut -d' ' -f1)"
    toc_n="$(grep -vc '^;' "$work/toc.txt")"
    # Metadatos informativos del nodo (consultados después de la copia).
    server="$(psql_backup "$node" -tAc "SELECT current_setting('server_version')")"
    counts="$(layer_counts psql_backup "$node" "$(node_schema "$node")")"
    seq=""
    if node_is_campus "$node"; then
        seq="$(psql_backup "$node" -tAc "SELECT coalesce(pg_sequence_last_value('$(node_schema "$node").objeto_id_seq'), 0)")"
    fi
    cat > "$work/manifest.txt" <<EOF
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
objetos_toc=$toc_n
validacion=pg_restore --list + lectura completa de datos + contenido esperado: OK
conteos=$counts
secuencia_ultimo=$seq
EOF
    sync -f "$work/sigtec.dump" 2>/dev/null || true

    final="$(publish_dir "$work" "$base" "$st")"
    trap - ERR
    backup_log "$node" pg_dump "${final#"$BACKUP_ROOT"/}" OK "bytes=$size sha256=${sha:0:16}… toc=$toc_n"
    log "  OK $node: $size bytes, $toc_n entradas TOC, validado${counts:+; $counts}"
}

rc=0
for node in $(nodes_expand "${@:-all}"); do
    run_step backup_node "$node"
    if [ "$RUN_RC" != 0 ]; then
        rc=1
        backup_log_safe "$node" pg_dump "-" ERROR "respaldo NO generado (código $RUN_RC); ver salida del comando"
        log "  ERROR respaldando $node: no se publicó ningún respaldo"
    fi
done
[ "$rc" = 0 ] || log "RESULTADO: uno o más respaldos lógicos FALLARON"
exit "$rc"
