#!/usr/bin/env bash
# =====================================================================
# SIG-TEC · RA-01: recrea el pg-recovery de un LABORATORIO a partir de una
# copia física de la recuperación ORIGINAL anterior a 0103.
#
#   remediation/RA-01/scripts/clone_recovery_into_lab.sh <laboratorio> <AAAAMMDDTHHMMSSZ>
#
#   1. copia (solo lectura sobre el origen) /backups/recovery_pre_ra01/<stamp>
#      del volumen sigtec_backups al volumen de respaldos del laboratorio;
#   2. en la copia del laboratorio retira de postgresql.auto.conf el objetivo
#      PITR heredado de la recuperación original (si no, la nueva recuperación
#      falla: "multiple recovery targets" / "target not reached");
#   3. elimina SOLO el pg-recovery del laboratorio y lo recrea con el entrypoint
#      real (RECOVERY_TARGET_LSN = fin de la copia) -> nueva línea de tiempo;
#   4. espera la promoción;
#   5. con --alinear-clave, pone a postgres la contraseña del .env del
#      laboratorio (el clon trae la del proyecto original).
# Nunca escribe en volúmenes del proyecto original.
# =====================================================================
set -Eeuo pipefail
LAB="$(cd "${1:?laboratorio}" && pwd)"; ST="${2:?marca del respaldo (AAAAMMDDTHHMMSSZ)}"; ALIGN="${3:-}"
PROJECT="$(sed -n 's/^COMPOSE_PROJECT_NAME=//p' "$LAB/.env")"
IMAGE="$(sed -n 's/^SIGTEC_IMAGE=//p' "$LAB/.env")"
[ -n "$PROJECT" ] && [ "$PROJECT" != sigtec ] || { echo "negado: laboratorio sin COMPOSE_PROJECT_NAME propio"; exit 2; }
[ -n "$IMAGE" ] || { echo "negado: el laboratorio debe definir SIGTEC_IMAGE propio"; exit 2; }
SRC=/src/recovery_pre_ra01/$ST; DST=/dst/legado_recovery_original/${ST}_sin_objetivo
cd "$LAB"

echo "== 1-2. copia de laboratorio del respaldo $ST (origen en solo lectura)"
docker run --rm --entrypoint bash -v sigtec_backups:/src:ro -v "${PROJECT}_backups:/dst" "$IMAGE" -c "
  set -e; [ -s $SRC/data/PG_VERSION ] || { echo 'no existe $SRC'; exit 3; }
  rm -rf $DST; mkdir -p \$(dirname $DST); cp -a $SRC $DST
  sed -i '/^recovery_target/d;/^restore_command/d;/^# --- SIG-TEC: recuperación PITR/d' $DST/data/postgresql.auto.conf
  grep -c '^recovery_target' $DST/data/postgresql.auto.conf || true"
END_LSN="$(docker run --rm --entrypoint bash -v "${PROJECT}_backups:/dst:ro" "$IMAGE" -c "sed -n 's/.*\"End-LSN\": \"\\([0-9A-F/]*\\)\".*/\\1/p' $DST/data/backup_manifest | tail -1")"
[ -n "$END_LSN" ] || { echo "no se pudo leer End-LSN del manifiesto"; exit 3; }
echo "fin de la copia (End-LSN del manifiesto): $END_LSN"

echo "== 3. se recrea SOLO el pg-recovery del laboratorio"
bash scripts/clean.sh --recovery-only --yes
RECOVERY_SOURCE_NODE=san_carlos RECOVERY_BASEBACKUP="/backups/legado_recovery_original/${ST}_sin_objetivo/data" \
RECOVERY_TARGET_LSN="$END_LSN" docker compose --profile recovery up -d pg-recovery

echo "== 4. promoción"
r=""
for _ in $(seq 1 90); do
    r="$(docker exec -u postgres "$PROJECT-pg-recovery-1" psql -X -d sigtec -tAc 'SELECT pg_is_in_recovery()' 2>/dev/null || true)"
    [ "$r" = f ] && break; sleep 2
done
[ "$r" = f ] || { docker compose --profile recovery logs --tail 30 pg-recovery; echo "pg-recovery no se promovió"; exit 4; }
docker exec -u postgres "$PROJECT-pg-recovery-1" psql -X -d sigtec -tA \
    -c "SELECT 'nodo=' || node_code || ' campus_id=' || campus_id FROM ops.node_info" \
    -c "SELECT 'migraciones=' || string_agg(version, ',' ORDER BY version) FROM ops.schema_migrations" \
    -c "SELECT 'registro_0103=' || (to_regclass('ops.identificadores_globales') IS NOT NULL)" \
    -c "SELECT 'linea_de_tiempo=' || timeline_id FROM pg_control_checkpoint()"

if [ "$ALIGN" = --alinear-clave ]; then
    echo "== 5. contraseña de postgres del clon = la del laboratorio (no se muestra)"
    PW="$(sed -n 's/^POSTGRES_PASSWORD=//p' .env)"
    printf "SET log_statement = 'none';\nALTER ROLE postgres PASSWORD '%s';\n" "$PW" |
        docker exec -i -u postgres "$PROJECT-pg-recovery-1" psql -X -q -v ON_ERROR_STOP=1 -d sigtec >/dev/null
    echo "hecho"
fi
echo "CLON_LISTO"
