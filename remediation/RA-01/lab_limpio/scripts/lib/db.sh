# shellcheck shell=bash
# =====================================================================
# SIG-TEC · utilidades para scripts que corren DENTRO del contenedor
# sigtec-tools (bash 5, cliente PostgreSQL 17, red Docker interna).
# =====================================================================
set -Eeuo pipefail

SIGTEC_HOME="${SIGTEC_HOME:-/opt/sigtec}"
# shellcheck source=nodes.sh
. "$SIGTEC_HOME/scripts/lib/nodes.sh"

BACKUP_ROOT="${BACKUP_ROOT:-/backups}"
ARCHIVE_ROOT="${ARCHIVE_ROOT:-/archives}"

ts()   { date '+%Y-%m-%d %H:%M:%S%z'; }
log()  { printf '[%s] %s\n' "$(ts)" "$*" >&2; }
die()  { printf '[%s] ERROR: %s\n' "$(ts)" "$*" >&2; exit 1; }
stamp(){ date -u '+%Y%m%dT%H%M%SZ'; }

# Ejecuta "$@" en una subshell con errexit/pipefail REALMENTE activos y deja el
# código en RUN_RC. Debe invocarse como orden simple (nunca en if, !, && o ||):
# Bash ignora set -e dentro de cualquier función o subshell evaluada en un
# contexto condicional, incluso si la subshell vuelve a ejecutar set -e
# (causa raíz de F-01: "if ! ( backup_node ... )" ocultaba los fallos).
run_step() {
    set +e
    ( set -Eeuo pipefail; "$@" )
    RUN_RC=$?
    set -e
}

# Host destino: nodo del catálogo o "recovery"
target_host() {
    if [ "$1" = "recovery" ]; then echo "pg-recovery"; else node_host "$1"; fi
}

# psql como superusuario postgres (administración: migraciones, datos, pruebas)
psql_su() {
    local node="$1"; shift
    PGPASSWORD="${POSTGRES_PASSWORD:?}" psql -X -q -v ON_ERROR_STOP=1 \
        -h "$(target_host "$node")" -p 5432 -U postgres -d "${SIGTEC_DB}" "$@"
}

# psql como rol de respaldo (solo lectura)
psql_backup() {
    local node="$1"; shift
    PGPASSWORD="${SIGTEC_BACKUP_PASSWORD:?}" psql -X -q -v ON_ERROR_STOP=1 \
        -h "$(target_host "$node")" -p 5432 -U "${SIGTEC_BACKUP_USER:-sigtec_backup}" -w -d "${SIGTEC_DB}" "$@"
}

# Valor escalar
sql_value() { local node="$1"; shift; psql_su "$node" -tAc "$*"; }

wait_node() {
    local node="$1" timeout="${2:-120}" i=0 host
    host="$(target_host "$node")"
    until pg_isready -q -h "$host" -p 5432 -d "$SIGTEC_DB" -U postgres; do
        i=$((i + 1))
        [ "$i" -ge "$timeout" ] && die "el nodo $node ($host) no respondió en ${timeout}s"
        sleep 1
    done
}
