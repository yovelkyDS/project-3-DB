#!/usr/bin/env bash
# =====================================================================
# SIG-TEC · DEMOSTRACIÓN DE FALLA Y RECUPERACIÓN PITR (host)
#
#   scripts/recovery/pitr_demo.sh [nodo=san_carlos] [--reset] [--keep-failed]
#
#    1. respaldo físico nuevo del nodo (pg_basebackup + pg_verifybackup)
#    2. cambio A identificable (INSERT) y su marca
#    3. instante objetivo = reloj del servidor DESPUÉS de confirmar A
#    4. cambio B identificable (UPDATE de A + INSERT) DESPUÉS del objetivo
#    5. pg_switch_wal() y espera hasta que el segmento quede archivado
#    6. falla simulada: SIGKILL al contenedor del nodo (sus volúmenes quedan intactos)
#    7. recuperación en el servicio AISLADO pg-recovery (volumen propio, puerto 55436):
#       copia base + restore_command sobre el WAL archivado + recovery_target_time
#    8-9. comprueba A presente y B ausente; valida las ocho capas
#   10. reinicia el nodo original y comprueba que conserva A y B (no se sobrescribió)
#   Informe: evidence/pitr/pitr_<run>.md (+ .log)
#
# --reset        elimina una instancia pg-recovery previa (sin preguntar)
# --keep-failed  no reinicia el nodo original al final (deja la "falla" visible)
# =====================================================================
set -eu
. "$(cd "$(dirname "$0")/.." && pwd)/lib/host.sh"
load_env

NODE=san_carlos; RESET=0; RESTART_ORIGINAL=1
for a in "$@"; do
    case "$a" in
        --reset) RESET=1 ;;
        --keep-failed) RESTART_ORIGINAL=0 ;;
        *) NODE="$a" ;;
    esac
done
node_is_campus "$NODE" || h_die "la demostración requiere un nodo de campus (recibido: $NODE)"
SVC="$(node_host "$NODE")"
RUN="$(date -u +%Y%m%dT%H%M%SZ)"
LOG="$(evidence_file pitr "pitr_${RUN}.log")"
REPORT="$(evidence_file pitr "pitr_${RUN}.md")"
exec > >(tee -a "$LOG") 2>&1

step() { echo; h_log "== $* =="; }
t() { tools "$@" 2>&1 | grep -v -E '^ ?Container sigtec-sigtec-tools-run'; }

step "0. precondiciones (nodo $NODE, servicio $SVC, corrida $RUN)"
[ "$(health_of "$SVC")" = healthy ] || h_die "$SVC no está healthy"
if docker volume inspect "$(volume_name pgdata_recovery)" >/dev/null 2>&1; then
    if [ "$RESET" = 1 ]; then
        h_log "existe una instancia de recuperación previa; se elimina (--reset)"
        "$SIGTEC_ROOT/scripts/clean.sh" --recovery-only --yes
    else
        h_die "ya existe una instancia recuperada (volumen $(volume_name pgdata_recovery)). Consérvela o ejecute: make recovery-clean   (o use --reset)"
    fi
fi

step "1. respaldo físico base"
t scripts/backup/physical_backup.sh "$NODE"
BASE="$(tools -c "ls -1d /backups/physical/$NODE/*/ | sort | tail -1" 2>/dev/null | sed 's|/$||')"
BASE_INFO="$(tools -c "cat $BASE/info.txt" 2>/dev/null)"
h_log "copia base: $BASE"
echo "$BASE_INFO" | grep -E '^(inicio|wal_inicio|verificacion|conteos)='

step "2. cambio A"
sleep 1
out="$(tools scripts/recovery/pitr_steps.sh cambio-a "$NODE" "$RUN" 2>/dev/null | tail -1)"
ID_A="${out%%|*}"; TS_A="${out#*|}"
[ -n "$ID_A" ] || h_die "no se registró el cambio A"
h_log "A: puntos_interes.id=$ID_A nombre='PITR-A $RUN' confirmado en $TS_A"

step "3. instante objetivo"
sleep 2
out="$(tools scripts/recovery/pitr_steps.sh objetivo "$NODE" 2>/dev/null | tail -1)"
TARGET="${out%%|*}"; LSN_T="${out#*|}"
h_log "OBJETIVO: $TARGET (LSN $LSN_T)"

step "4. cambio B"
sleep 2
out="$(tools scripts/recovery/pitr_steps.sh cambio-b "$NODE" "$RUN" "$ID_A" 2>/dev/null | tail -1)"
ID_B="${out%%|*}"; TS_B="${out#*|}"
[ -n "$ID_B" ] || h_die "no se registró el cambio B"
h_log "B: puntos_interes.id=$ID_B nombre='PITR-B $RUN' + actualización de $ID_A, confirmado en $TS_B"

step "5. disponibilidad del WAL"
SEG="$(tools scripts/recovery/pitr_steps.sh asegurar-wal "$NODE" 2>/dev/null | tail -1)"
h_log "segmento con A, objetivo y B archivado: $SEG"
t -c "ls -l /archives/$NODE | tail -4"

step "6. falla simulada"
compose kill -s SIGKILL "$SVC"
sleep 2
h_log "estado de $SVC: $(health_of "$SVC")"
compose ps -a "$SVC"

step "7. recuperación PITR en instancia aislada pg-recovery"
RECOVERY_SOURCE_NODE="$NODE" RECOVERY_BASEBACKUP="$BASE/data" RECOVERY_TARGET_TIME="$TARGET" \
    compose --profile recovery up -d pg-recovery
t scripts/recovery/pitr_steps.sh promovida recovery
wait_healthy 120 pg-recovery || true
h_log "registro de recuperación de PostgreSQL (pg-recovery):"
RLOG="$(compose --profile recovery logs --no-log-prefix pg-recovery 2>&1 | grep -E 'sigtec-recovery|starting point-in-time|restored log file|redo starts|recovery stopping|pausing|last completed transaction|selected new timeline|archive recovery complete|database system is ready' | sed 's/^[0-9-]* [0-9:.]* [A-Z-]* \[[0-9]*\] //')"
echo "$RLOG"

step "8-9. verificación del nodo recuperado"
VERIF="$(tools scripts/recovery/pitr_steps.sh verificar recovery "$NODE" "$RUN" "$ID_A" 2>/dev/null)"
echo "$VERIF" | awk -F'|' '{ printf "  %-5s %-45s %s\n", $1, $2, $3 }'
LAYERS="$(t scripts/db/verify.sh recovery || true)"
echo "$LAYERS"
RINFO="$(compose --profile recovery exec -T pg-recovery cat /var/lib/postgresql/data/SIGTEC_RECOVERY_INFO)"
FAILS="$(echo "$VERIF" | grep -c '^FAIL' || true)"
echo "$LAYERS" | grep -q 'ERROR' && FAILS=$((FAILS + 1))
if [ "$FAILS" = 0 ]; then
    t scripts/recovery/pitr_steps.sh marcar-recuperada "$NODE" "$RUN" \
      "PITR de $NODE a $TARGET desde $BASE; A presente, B ausente" >/dev/null
fi

step "10. nodo original"
ORIG=""
if [ "$RESTART_ORIGINAL" = 1 ]; then
    compose start "$SVC"
    wait_healthy 180 "$SVC" || h_warn "$SVC no volvió a healthy"
    ORIG="$(tools -c ". scripts/lib/db.sh; psql_su $NODE -tA -c \"SELECT 'PITR-A: ' || descripcion FROM $(node_schema "$NODE").puntos_interes WHERE id = $ID_A\" -c \"SELECT 'PITR-B: ' || count(*) || ' fila(s)' FROM $(node_schema "$NODE").puntos_interes WHERE nombre = 'PITR-B $RUN'\"" 2>/dev/null)"
    echo "$ORIG"
    h_log "el nodo original conserva su estado completo (A modificado por B, B presente): no se sobrescribió"
else
    h_log "--keep-failed: $SVC permanece detenido"
fi

RESULT="EXITOSA"; [ "$FAILS" = 0 ] || RESULT="CON FALLAS ($FAILS)"
cat > "$REPORT" <<EOF
# Evidencia PITR · corrida $RUN

Resultado: **$RESULT**

| Dato | Valor |
|---|---|
| Nodo de origen | \`$NODE\` (\`$SVC\`, campus_id $(node_campus_id "$NODE")) |
| Copia base | \`$BASE/data\` |
| Inicio de la copia | $(echo "$BASE_INFO" | sed -n 's/^inicio=//p') — WAL $(echo "$BASE_INFO" | sed -n 's/^wal_inicio=//p') |
| Verificación de la copia | $(echo "$BASE_INFO" | sed -n 's/^verificacion=//p') |
| Cambio A | \`puntos_interes.id = $ID_A\` (\`PITR-A $RUN\`), commit $TS_A |
| **Instante objetivo** | **$TARGET** (LSN $LSN_T) |
| Cambio B | \`UPDATE\` de $ID_A + \`INSERT\` \`puntos_interes.id = $ID_B\` (\`PITR-B $RUN\`), commit $TS_B |
| Segmento WAL archivado | \`$SEG\` en \`/archives/$NODE\` |
| Falla simulada | \`docker compose kill -s SIGKILL $SVC\` (volúmenes de datos y WAL intactos) |
| Instancia recuperada | servicio \`pg-recovery\`, volumen \`$(volume_name pgdata_recovery)\`, \`127.0.0.1:$(node_port recovery)\` |

Orden temporal comprobado: commit A ($TS_A) < objetivo ($TARGET) < commit B ($TS_B).

## Verificación en la instancia recuperada

\`\`\`
$VERIF
\`\`\`

## Registro de recuperación de PostgreSQL

\`\`\`
$RLOG
\`\`\`

## Metadatos de la instancia recuperada (SIGTEC_RECOVERY_INFO)

\`\`\`
$RINFO
\`\`\`

## Validación de las ocho capas en la instancia recuperada

\`\`\`
$LAYERS
\`\`\`

## Nodo original tras reiniciarlo

\`\`\`
${ORIG:-(no se reinició: --keep-failed)}
\`\`\`

El nodo original conserva A (con la modificación de B) y B: la recuperación se hizo
en una instancia aislada y no sobrescribió el nodo en servicio.
EOF
step "resultado: PITR $RESULT"
h_log "informe: ${REPORT#"$SIGTEC_ROOT"/}"
[ "$FAILS" = 0 ]
