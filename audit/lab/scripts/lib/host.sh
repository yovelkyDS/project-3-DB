# shellcheck shell=bash
# =====================================================================
# SIG-TEC · utilidades para scripts que corren en el HOST
# Compatible con bash 3.2 (macOS). Solo requiere Docker + Compose v2.
# =====================================================================
set -eu

SIGTEC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=nodes.sh
. "$SIGTEC_ROOT/scripts/lib/nodes.sh"

h_ts()   { date '+%Y-%m-%d %H:%M:%S%z'; }
h_log()  { printf '[%s] %s\n' "$(h_ts)" "$*"; }
h_warn() { printf '[%s] AVISO: %s\n' "$(h_ts)" "$*" >&2; }
h_die()  { printf '[%s] ERROR: %s\n' "$(h_ts)" "$*" >&2; exit 1; }

load_env() {
    [ -f "$SIGTEC_ROOT/.env" ] || h_die "No existe .env. Ejecute primero: scripts/setup.sh"
    set -a
    # shellcheck disable=SC1091
    . "$SIGTEC_ROOT/.env"
    set +a
    COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-sigtec}"
}

compose() { docker compose --project-directory "$SIGTEC_ROOT" -f "$SIGTEC_ROOT/compose.yaml" "$@"; }

# Ejecuta un comando dentro del contenedor efímero de herramientas
tools() { compose --profile tools run --rm -T sigtec-tools "$@"; }

# Nombre real de un volumen del proyecto
volume_name() { echo "${COMPOSE_PROJECT_NAME:-sigtec}_$1"; }

health_of() {
    local cid
    cid="$(compose --profile recovery ps -a -q "$1" 2>/dev/null || true)"
    [ -n "$cid" ] || { echo "ausente"; return 0; }
    docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$cid" 2>/dev/null || echo "desconocido"
}

# Espera a que los servicios indicados estén "healthy"
wait_healthy() {
    local timeout="$1"; shift
    local start svc st pending
    start=$(date +%s)
    while :; do
        pending=""
        for svc in "$@"; do
            st="$(health_of "$svc")"
            [ "$st" = "healthy" ] || pending="$pending $svc($st)"
        done
        [ -z "$pending" ] && return 0
        if [ $(( $(date +%s) - start )) -ge "$timeout" ]; then
            h_warn "servicios sin estado healthy tras ${timeout}s:$pending"
            return 1
        fi
        sleep 2
    done
}

node_services() {
    local n out=""
    for n in $(nodes_expand "${1:-all}"); do out="$out $(node_host "$n")"; done
    echo $out
}

evidence_file() {
    # evidence_file <categoria> <nombre>  -> ruta (crea el directorio)
    mkdir -p "$SIGTEC_ROOT/evidence/$1"
    echo "$SIGTEC_ROOT/evidence/$1/$2"
}
