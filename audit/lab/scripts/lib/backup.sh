# shellcheck shell=bash
# =====================================================================
# SIG-TEC · utilidades comunes de respaldo (dentro de sigtec-tools)
#
# Estructura del volumen de respaldos (/backups, volumen Docker sigtec_backups):
#   /backups/logical/<nodo>/<UTC>/sigtec.dump      pg_dump -Fc
#                               /globals.sql      roles (sin contraseñas)
#                               /toc.txt          pg_restore --list
#                               /manifest.txt     metadatos, SHA-256, conteos
#   /backups/physical/<nodo>/<UTC>/data/          pg_basebackup -Fp -X stream (+ backup_manifest)
#                                /info.txt        metadatos, LSN, conteos
#   /backups/backup_log.tsv                       bitácora de todas las operaciones
# El WAL archivado de cada nodo está en /archives/<nodo> (solo lectura aquí).
# =====================================================================
. "${SIGTEC_HOME:-/opt/sigtec}/scripts/lib/db.sh"

BACKUP_LOG="$BACKUP_ROOT/backup_log.tsv"

backup_log() {   # backup_log <nodo> <operacion> <ruta> <resultado> <detalle>
    mkdir -p "$BACKUP_ROOT"
    [ -f "$BACKUP_LOG" ] || printf 'fecha\tnodo\toperacion\truta\tresultado\tdetalle\n' > "$BACKUP_LOG"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(ts)" "$1" "$2" "$3" "$4" "$5" >> "$BACKUP_LOG"
}

latest_dir() { ls -1d "$1"/*/ 2>/dev/null | sort | tail -1 | sed 's|/$||'; }

# Conteo de filas por capa ("capa=n ..."); vacío en el central
layer_counts() {   # layer_counts <psql-fn> <nodo|destino> <esquema>
    local fn="$1" target="$2" schema="$3" q="" l
    [ -n "$schema" ] || { echo ""; return 0; }
    for l in $SIGTEC_LAYERS; do
        q="$q${q:+ || ' ' || }'$l=' || (SELECT count(*) FROM $schema.$l)"
    done
    "$fn" "$target" -tAc "SELECT $q"
}

# Arranca un clúster temporal (como postgres) y define tmp_psql
start_temp_cluster() {   # start_temp_cluster <dir-datos> <puerto> [extra -c ...]
    local data="$1" port="$2"; shift 2
    TMP_SOCKET="$(dirname "$data")"; TMP_PORT="$port"; TMP_DATA="$data"
    gosu postgres pg_ctl -D "$data" -l "$TMP_SOCKET/server.log" -w -t 300 \
        -o "-c listen_addresses='' -c unix_socket_directories=$TMP_SOCKET -c port=$port $*" start >/dev/null
}
stop_temp_cluster() { [ -n "${TMP_DATA:-}" ] && gosu postgres pg_ctl -D "$TMP_DATA" -m fast -w stop >/dev/null 2>&1 || true; }
tmp_psql() { local db="$1"; shift; gosu postgres psql -X -q -v ON_ERROR_STOP=1 -h "$TMP_SOCKET" -p "$TMP_PORT" -U postgres -d "$db" "$@"; }
