#!/usr/bin/env bash
# SIG-TEC · inventario de respaldos y WAL archivado (dentro de sigtec-tools)
. "${SIGTEC_HOME:-/opt/sigtec}/scripts/lib/backup.sh"

printf '%-11s %-9s %-18s %10s  %s\n' NODO TIPO FECHA_UTC TAMAÑO DETALLE
for node in $SIGTEC_NODES; do
    for d in $(ls -1d "$BACKUP_ROOT/logical/$node"/*/ 2>/dev/null | sort); do
        d="${d%/}"
        printf '%-11s %-9s %-18s %10s  %s\n' "$node" logico "$(basename "$d")" "$(du -sh "$d" | cut -f1)" \
            "sha256=$(sed -n 's/^sha256=//p' "$d/manifest.txt" | cut -c1-12)…"
    done
    for d in $(ls -1d "$BACKUP_ROOT/physical/$node"/*/ 2>/dev/null | sort); do
        d="${d%/}"
        printf '%-11s %-9s %-18s %10s  %s\n' "$node" fisico "$(basename "$d")" "$(du -sh "$d/data" | cut -f1)" \
            "wal_inicio=$(sed -n 's/^wal_inicio=//p' "$d/info.txt")"
    done
done
echo
printf '%-11s %8s %10s  %s\n' NODO SEGMENTOS TAMAÑO "ÚLTIMO SEGMENTO ARCHIVADO"
for node in $SIGTEC_NODES; do
    a="$ARCHIVE_ROOT/$node"
    n="$(find "$a" -maxdepth 1 -type f -name '[0-9A-F]*' ! -name '*.backup' ! -name '*.history' 2>/dev/null | wc -l)"
    last="$(ls -1 "$a" 2>/dev/null | grep -E '^[0-9A-F]{24}$' | sort | tail -1)"
    printf '%-11s %8s %10s  %s\n' "$node" "$n" "$(du -sh "$a" 2>/dev/null | cut -f1)" "${last:--}"
done
echo
echo "Bitácora: $BACKUP_LOG (últimas 15 líneas)"
tail -15 "$BACKUP_LOG" 2>/dev/null | awk -F'\t' '{ printf "%-25s %-11s %-20s %-6s %s\n", $1, $2, $3, $5, $4 }' || true
