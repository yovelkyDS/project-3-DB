#!/usr/bin/env bash
# =====================================================================
# SIG-TEC · retención de respaldos físicos y WAL archivado (HOST)
#   scripts/backup/wal_retention.sh [all|<nodo> ...] [--keep N] [--apply]
#
# Conserva los N respaldos físicos más recientes de cada nodo (por omisión 2)
# y el WAL archivado necesario para recuperar desde el MÁS ANTIGUO de ellos
# (es decir, la ventana PITR va desde ese respaldo hasta el último WAL).
# Sin --apply solo muestra lo que se eliminaría (simulación con
# pg_archivecleanup -n). Con --apply borra respaldos sobrantes y ejecuta
# pg_archivecleanup dentro del contenedor del nodo (dueño del archivo WAL).
# =====================================================================
set -eu
. "$(cd "$(dirname "$0")/.." && pwd)/lib/host.sh"
load_env

KEEP=2; APPLY=0; targets=""
while [ $# -gt 0 ]; do
    case "$1" in
        --keep) KEEP="$2"; shift 2 ;;
        --apply) APPLY=1; shift ;;
        *) targets="$targets $1"; shift ;;
    esac
done
[ "$KEEP" -ge 1 ] 2>/dev/null || h_die "--keep debe ser >= 1"

for node in $(nodes_expand ${targets:-all}); do
    # Respaldos ordenados; el más antiguo conservado define el corte del WAL
    info="$(tools -c "ls -1d /backups/physical/$node/*/ 2>/dev/null | sort" 2>/dev/null || true)"
    total="$(echo "$info" | grep -c / || true)"
    if [ "$total" -eq 0 ]; then h_log "$node: sin respaldos físicos; no se depura WAL"; continue; fi
    drop="$(echo "$info" | awk -v n=$(( total > KEEP ? total - KEEP : 0 )) 'NR <= n')"
    oldest_kept="$(echo "$info" | awk -v n=$(( total > KEEP ? total - KEEP : 0 )) 'NR == n + 1' | sed 's|/$||')"
    seg="$(tools -c "sed -n 's/^START WAL LOCATION: .*(file \([0-9A-F]*\)).*/\1/p' $oldest_kept/data/backup_label" 2>/dev/null)"
    h_log "$node: $total respaldos, se conservan $KEEP; primer segmento WAL necesario: $seg"
    for d in $drop; do h_log "  respaldo sobrante: ${d#/backups/}"; done
    removable="$(tools -c "pg_archivecleanup -n /archives/$node $seg | wc -l" 2>/dev/null)"
    h_log "  segmentos WAL anteriores a $seg (eliminables): $removable"
    if [ "$APPLY" = 1 ]; then
        for d in $drop; do tools -c "rm -rf '${d%/}'" >/dev/null 2>&1 && h_log "  eliminado ${d#/backups/}"; done
        compose exec -T -u postgres "$(node_host "$node")" pg_archivecleanup /var/lib/postgresql/wal_archive "$seg"
        h_log "  pg_archivecleanup aplicado en $(node_host "$node")"
    fi
done
[ "$APPLY" = 1 ] || h_log "Simulación: no se eliminó nada (use --apply para aplicar)"
