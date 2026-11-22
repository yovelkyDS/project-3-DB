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
# Usuario de respaldo (configurable solo para pruebas negativas)
SIGTEC_BACKUP_USER="${SIGTEC_BACKUP_USER:-sigtec_backup}"

backup_log() {   # backup_log <nodo> <operacion> <ruta> <resultado> <detalle>
    mkdir -p "$BACKUP_ROOT"
    [ -f "$BACKUP_LOG" ] || printf 'fecha\tnodo\toperacion\truta\tresultado\tdetalle\n' > "$BACKUP_LOG"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(ts)" "$1" "$2" "$3" "$4" "$5" >> "$BACKUP_LOG"
}
# Variante que nunca aborta (para registrar un ERROR aun si la bitácora no es escribible)
backup_log_safe() { ( backup_log "$@" ) 2>/dev/null || log "  AVISO: no se pudo escribir $BACKUP_LOG"; }

# Último respaldo PUBLICADO. Los directorios de trabajo (.en-curso-*) y los
# fallidos (.fallido-*) empiezan con punto y el patrón * no los incluye.
latest_dir() { ls -1d "$1"/*/ 2>/dev/null | sort | tail -1 | sed 's|/$||'; }

# Error de una etapa: mensaje y código 1 (dentro de run_step aborta el nodo)
fail() { printf '[%s]   FALLA: %s\n' "$(ts)" "$*" >&2; return 1; }

# Muestra un archivo de diagnóstico (stderr de pg_dump, etc.) sangrado.
# Los mensajes de libpq no incluyen la contraseña.
show_diag() { [ -s "$1" ] && sed 's/^/      | /' "$1" >&2 || true; }

# --- Directorios de trabajo y publicación atómica ---------------------
# El respaldo se escribe en <base>/.en-curso-<UTC>-<pid>; solo tras validar se
# renombra a <base>/<UTC> (rename en el mismo sistema de archivos = atómico).
# Un fallo lo convierte en <base>/.fallido-<UTC>-<pid> sin la carga útil,
# conservando únicamente los archivos de diagnóstico.
work_dir_for() { echo "$1/.en-curso-$2-$$"; }

publish_dir() {   # publish_dir <dir-trabajo> <base> <stamp>  -> imprime destino
    local work="$1" base="$2" st="$3" final
    final="$base/$st"
    [ -e "$final" ] && final="$base/$st-$$"
    [ -e "$final" ] && { fail "el destino $final ya existe"; return 1; }
    mv -T "$work" "$final" || { fail "no se pudo publicar $final"; return 1; }
    sync -f "$final" 2>/dev/null || true
    echo "$final"
}

discard_work_dir() {   # discard_work_dir <dir-trabajo> <base> <stamp> <carga...>
    local work="$1" base="$2" st="$3" f; shift 3
    [ -d "$work" ] || return 0
    for f in "$@"; do rm -rf "${work:?}/$f" 2>/dev/null || true; done
    mv -T "$work" "$base/.fallido-$st-$$" 2>/dev/null || rm -rf "$work" 2>/dev/null || true
}

# --- Validación de un respaldo lógico ----------------------------------
# validate_logical_dir <dir> <nodo>
#   * sigtec.dump legible: pg_restore --list (TOC) y lectura COMPLETA de todos
#     los bloques de datos (pg_restore -f /dev/null), que detecta truncamiento
#   * contenido mínimo esperado: PostGIS, ops.node_info y, en campus, los datos
#     de las ocho capas del esquema local
#   * globals.sql generado por pg_dumpall
# Escribe toc.txt en <dir>.
validate_logical_dir() {
    local dir="$1" node="$2" schema l missing=""
    [ -s "$dir/sigtec.dump" ] || { fail "sigtec.dump no existe o está vacío"; return 1; }
    pg_restore --list "$dir/sigtec.dump" > "$dir/toc.txt" 2> "$dir/validacion.stderr" \
        || { show_diag "$dir/validacion.stderr"; fail "pg_restore --list no pudo leer el TOC"; return 1; }
    pg_restore --file=/dev/null "$dir/sigtec.dump" 2>> "$dir/validacion.stderr" \
        || { show_diag "$dir/validacion.stderr"; fail "pg_restore no pudo leer todos los bloques de datos (archivo dañado o truncado)"; return 1; }
    grep -qE ' EXTENSION - postgis ?$' "$dir/toc.txt" || missing="$missing extension_postgis"
    grep -qE ' TABLE DATA ops node_info ' "$dir/toc.txt" || missing="$missing ops.node_info"
    if node_is_campus "$node"; then
        schema="$(node_schema "$node")"
        for l in $SIGTEC_LAYERS; do
            grep -qE " TABLE DATA $schema $l " "$dir/toc.txt" || missing="$missing $schema.$l"
        done
    fi
    [ -z "$missing" ] || { fail "el TOC no contiene:$missing"; return 1; }
    [ -s "$dir/globals.sql" ] && grep -q '^CREATE ROLE ' "$dir/globals.sql" \
        || { fail "globals.sql vacío o sin roles"; return 1; }
    rm -f "$dir/validacion.stderr"
}

# --- Validación de un respaldo físico ----------------------------------
# validate_physical_dir <dir>  (contiene data/)
#   * estructura: PG_VERSION 17, backup_label, backup_manifest
#   * pg_verifybackup: sumas SHA-256 del manifiesto y WAL necesario
# Escribe pg_verifybackup.txt en <dir>.
validate_physical_dir() {
    local dir="$1" f
    for f in PG_VERSION backup_label backup_manifest global/pg_control; do
        [ -s "$dir/data/$f" ] || { fail "falta $f en la copia base"; return 1; }
    done
    [ "$(cat "$dir/data/PG_VERSION")" = 17 ] || { fail "PG_VERSION inesperado: $(cat "$dir/data/PG_VERSION")"; return 1; }
    grep -q '^START WAL LOCATION: ' "$dir/data/backup_label" || { fail "backup_label sin START WAL LOCATION"; return 1; }
    pg_verifybackup "$dir/data" > "$dir/pg_verifybackup.txt" 2>&1 \
        || { show_diag "$dir/pg_verifybackup.txt"; fail "pg_verifybackup rechazó la copia"; return 1; }
    grep -q 'backup successfully verified' "$dir/pg_verifybackup.txt" \
        || { show_diag "$dir/pg_verifybackup.txt"; fail "pg_verifybackup no confirmó la verificación"; return 1; }
}

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
