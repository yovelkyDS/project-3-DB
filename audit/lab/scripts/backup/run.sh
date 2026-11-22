#!/usr/bin/env bash
# =====================================================================
# SIG-TEC · ejecuta un script de respaldo dentro de sigtec-tools y guarda
# la salida como evidencia (evidence/backups/<script>_<fecha>.log).
#   scripts/backup/run.sh <logical_backup.sh|physical_backup.sh|
#                          logical_restore_test.sh|physical_restore_test.sh> [nodos]
# =====================================================================
set -eu
. "$(cd "$(dirname "$0")/.." && pwd)/lib/host.sh"
load_env

script="${1:?indique el script}"; shift
[ -f "$SIGTEC_ROOT/scripts/backup/$script" ] || h_die "script desconocido: $script"
LOG="$(evidence_file backups "${script%.sh}_$(date +%Y%m%d_%H%M%S).log")"
h_log "scripts/backup/$script ${*:-all}  (registro: ${LOG#"$SIGTEC_ROOT"/})" | tee -a "$LOG"
set +e
tools "scripts/backup/$script" "${@:-all}" 2>&1 | grep -v -E '^ ?Container sigtec-sigtec-tools-run' | tee -a "$LOG"
rc=${PIPESTATUS[0]}
set -e
[ "$rc" = 0 ] && h_log "resultado: OK" | tee -a "$LOG" || h_log "resultado: ERROR (código $rc)" | tee -a "$LOG"
exit "$rc"
