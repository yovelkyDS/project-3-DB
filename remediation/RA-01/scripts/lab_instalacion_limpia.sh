#!/usr/bin/env bash
# =====================================================================
# RA-01 · instalación limpia del LABORATORIO (nunca de los originales)
#   uso: remediation/RA-01/scripts/lab_instalacion_limpia.sh <directorio_evidencia> [lab] [proyecto]
#   lab/proyecto por omisión: remediation/lab / sigtec_remed. El laboratorio
#   remediation/RA-01/lab_limpio (sigtec_ra01) se crea con --nuevo desde el
#   código actual y la plantilla de .env del laboratorio, SIN .env: setup.sh
#   genera los secretos (instalación desde cero real).
# clean --yes -> setup -> run_tests --full -> backup -> restore-test ->
# pitr_demo san_carlos --reset (incluye el paso 9b: migrate recovery) ->
# recovery-status -> objetivo PITR retirado de postgresql.auto.conf ->
# run_tests --full (con [2c]) -> wal-retention (simulación)
# =====================================================================
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
EV="${1:?directorio de evidencia}"; mkdir -p "$EV"; EV="$(cd "$EV" && pwd)"
LAB="${2:-$ROOT/remediation/lab}"; PROJECT="${3:-sigtec_remed}"
case "$PROJECT" in sigtec_remed|sigtec_ra01) ;; *) echo "ABORTADO: solo laboratorios (sigtec_remed, sigtec_ra01)"; exit 2 ;; esac
if [ "$PROJECT" = sigtec_ra01 ]; then
    # Laboratorio nuevo: código actual + plantilla con proyecto/puertos/imagen propios, sin .env
    LAB="$ROOT/remediation/RA-01/lab_limpio"; mkdir -p "$LAB"
    for d in scripts sql tests docker; do rsync -a --delete "$ROOT/$d/" "$LAB/$d/"; done
    cp "$ROOT/compose.yaml" "$ROOT/Makefile" "$ROOT/.gitignore" "$LAB/"
    sed -e 's/^COMPOSE_PROJECT_NAME=.*/COMPOSE_PROJECT_NAME=sigtec_ra01/' \
        -e 's#^SIGTEC_IMAGE=.*#SIGTEC_IMAGE=sigtec-ra01/postgis:17.12-3.5.4#' \
        -e 's/^\(SIGTEC_PORT_[A-Z_]*\)=5743\([0-9]\)$/\1=5744\2/' \
        "$ROOT/remediation/lab/.env.example" > "$LAB/.env.example"
fi
cd "$LAB" || exit 2
ENVF=.env; [ -f .env ] || ENVF=.env.example
grep -qx "COMPOSE_PROJECT_NAME=$PROJECT" "$ENVF" || { echo "ABORTADO: $LAB/$ENVF no es el laboratorio $PROJECT"; exit 2; }
export SIGTEC_EVIDENCE_DIR="$EV"
unset SIGTEC_PORT_CENTRAL SIGTEC_PORT_CARTAGO SIGTEC_PORT_SAN_JOSE SIGTEC_PORT_SAN_CARLOS SIGTEC_PORT_ALAJUELA SIGTEC_PORT_LIMON SIGTEC_PORT_RECOVERY
FAILS=0
step() { local name="$1"; shift; "$@"; local rc=$?; echo "== $name rc=$rc"; [ "$rc" = 0 ] || FAILS=$((FAILS+1)); }
[ "$PROJECT" = sigtec_remed ] && bash "$ROOT/remediation/scripts/sync_lab.sh"
echo "laboratorio: $LAB (proyecto $PROJECT; .env existente: $([ -f .env ] && echo sí || echo no))"
step clean        bash scripts/clean.sh --yes
step setup        bash scripts/setup.sh
step test-full    bash tests/run_tests.sh --full
step backup       make backup
step restore-test make restore-test
step pitr         bash scripts/recovery/pitr_demo.sh san_carlos --reset
step recovery-status make recovery-status
autoconf() {
    local c; c="$(docker compose --profile recovery ps -q pg-recovery)"
    echo "postgresql.auto.conf de pg-recovery (laboratorio):"
    docker exec -u postgres "$c" cat /var/lib/postgresql/data/postgresql.auto.conf | sed 's/^/  /'
    echo "parámetros de recuperación con valor no predeterminado:"
    docker exec -u postgres "$c" psql -XAtq -d sigtec -c "SELECT name||'='||setting||' ('||source||')' FROM pg_settings WHERE (name LIKE 'recovery_target%' OR name='restore_command') AND source NOT IN ('default','override')" | sed 's/^/  /'
    ! docker exec -u postgres "$c" grep -Eq '^(recovery_target|restore_command)' /var/lib/postgresql/data/postgresql.auto.conf
}
step autoconf-sin-objetivo autoconf
step test-full-con-recovery bash tests/run_tests.sh --full
step wal-retention make wal-retention
echo "PIPELINE_EXIT=$FAILS"
exit "$FAILS"
