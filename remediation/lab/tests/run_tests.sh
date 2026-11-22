#!/usr/bin/env bash
# =====================================================================
# SIG-TEC · ejecutor de pruebas (host)
#
#   tests/run_tests.sh           healthchecks + pruebas SQL/PostGIS + regresión F-01/F-02/RA-01
#                                (respaldos fallidos, unicidad de ids, migración del nodo
#                                recuperado) + pg-recovery al día (si existe) + higiene del repo
#   tests/run_tests.sh --full    además: idempotencia (migrar/cargar de nuevo) y
#                                persistencia (reinicio de los seis contenedores)
#
# Guarda la salida en evidence/tests/. Código 1 si alguna prueba falla.
# =====================================================================
set -eu
. "$(cd "$(dirname "$0")/.." && pwd)/scripts/lib/host.sh"
load_env

FULL=0
[ "${1:-}" = "--full" ] && FULL=1

LOG="$(evidence_file tests "tests_$(date +%Y%m%d_%H%M%S).log")"
exec > >(tee -a "$LOG") 2>&1
FAILS=0
res() { printf '%-5s %-58s %s\n' "$1" "$2" "$3"; [ "$1" = PASS ] || FAILS=$((FAILS + 1)); }

h_log "== SIG-TEC · pruebas (registro: ${LOG#"$SIGTEC_ROOT"/}) =="

# --- 1. Infraestructura Docker -----------------------------------------
h_log "[1] contenedores, healthchecks, red y volúmenes"
for n in $SIGTEC_NODES; do
    svc="$(node_host "$n")"; st="$(health_of "$svc")"
    [ "$st" = healthy ] && res PASS "docker.$n.healthy" "$svc: $st" || res FAIL "docker.$n.healthy" "$svc: $st"
    cid="$(compose ps -q "$svc")"
    if [ -n "$cid" ]; then
        binds="$(docker inspect -f '{{range $p, $c := .NetworkSettings.Ports}}{{range $c}}{{.HostIp}}:{{.HostPort}} {{end}}{{end}}' "$cid")"
        exp="${SIGTEC_BIND_ADDRESS:-127.0.0.1}:$(node_port "$n")"
        case "$binds" in *"$exp"*) res PASS "docker.$n.puerto" "$binds";; *) res FAIL "docker.$n.puerto" "esperado $exp, hay $binds";; esac
        mounts="$(docker inspect -f '{{range .Mounts}}{{.Name}}:{{.Destination}} {{end}}' "$cid")"
        case "$mounts" in
            *"pgdata_$n:/var/lib/postgresql/data"*"walarchive_$n:/var/lib/postgresql/wal_archive"*|*"walarchive_$n:/var/lib/postgresql/wal_archive"*"pgdata_$n:/var/lib/postgresql/data"*)
                res PASS "docker.$n.volumenes_separados" "$mounts" ;;
            *) res FAIL "docker.$n.volumenes_separados" "$mounts" ;;
        esac
        rp="$(docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$cid")"
        [ "$rp" = unless-stopped ] && res PASS "docker.$n.reinicio_automatico" "$rp" || res FAIL "docker.$n.reinicio_automatico" "$rp"
    fi
done
net="$(docker network inspect -f '{{len .Containers}}' "${COMPOSE_PROJECT_NAME}_net" 2>/dev/null || echo 0)"
[ "$net" -ge 6 ] && res PASS docker.red_compartida "${COMPOSE_PROJECT_NAME}_net con $net contenedores" || res FAIL docker.red_compartida "$net contenedores"

# --- 2. Pruebas SQL / PostGIS (dentro de la red Docker) ----------------
h_log "[2] pruebas SQL y PostGIS en los seis nodos"
if tools tests/container/run_sql_tests.sh all; then :; else FAILS=$((FAILS + 1)); fi

# --- 2b. Regresión de los hallazgos de auditoría F-01 y F-02 -------------
# Ambas suites trabajan en entornos aislados (BACKUP_ROOT temporal, clústeres
# temporales): no escriben en /backups ni en los nodos en servicio.
h_log "[2b] regresión F-01: los respaldos fallidos fallan (negativos y positivos, seis nodos)"
if tools tests/container/test_backup_failures.sh; then :; else FAILS=$((FAILS + 1)); fi
h_log "[2b] regresión F-02: unicidad global de ids, concurrencia y mantenimiento (clústeres temporales)"
if tools tests/container/test_ids_aislado.sh campus; then :; else FAILS=$((FAILS + 1)); fi
h_log "[2b] regresión RA-01: nodo recuperado anterior a 0103 -> make migrate NODE=recovery (PITR en clústeres temporales)"
if tools tests/container/test_recovery_migracion.sh; then :; else FAILS=$((FAILS + 1)); fi

# --- 2c. La instancia recuperada que se entrega también debe estar al día ----
# (RA-01: las pruebas no miraban pg-recovery; un nodo recuperado anterior a 0103
#  admitía ids repetidos entre capas). Solo lectura.
h_log "[2c] instancia recuperada pg-recovery: migraciones al día y registro de ids"
if [ -n "$(compose --profile recovery ps -q --status running pg-recovery 2>/dev/null)" ]; then
    rout="$(tools scripts/db/verify.sh recovery 2>&1)"; rrc=$?
    if [ "$rrc" = 0 ] && echo "$rout" | grep -q 'apta para entregar'; then
        res PASS recovery.migraciones_y_registro "$(echo "$rout" | grep -m1 '^migraciones:')"
    else
        res FAIL recovery.migraciones_y_registro "$(echo "$rout" | grep -E 'PENDIENTES|FALTA|NO APTA|FAIL\|' | head -3 | tr '\n' ' ')"
    fi
else
    h_log "  pg-recovery no está en ejecución: no hay instancia recuperada que verificar"
fi

# --- 3. Higiene del repositorio ----------------------------------------
h_log "[3] higiene del repositorio (secretos, rutas absolutas)"
files="$(cd "$SIGTEC_ROOT" && find . -type f ! -path './.env' ! -path './.git/*' ! -name '.DS_Store' | sed 's|^\./||')"
leaks=0
while IFS= read -r line; do
    case "$line" in *PASSWORD=*) ;; *) continue ;; esac
    val="${line#*=}"
    [ ${#val} -ge 12 ] || continue
    if (cd "$SIGTEC_ROOT" && echo "$files" | tr '\n' '\0' | xargs -0 grep -l -F -- "$val" 2>/dev/null) | grep -q .; then
        leaks=$((leaks + 1))
    fi
done < "$SIGTEC_ROOT/.env"
[ "$leaks" = 0 ] && res PASS repo.sin_secretos "ningún valor de .env aparece en otros archivos" || res FAIL repo.sin_secretos "$leaks secretos encontrados fuera de .env"
# audit/ es evidencia de la auditoría externa (solo lectura, no se modifica): se excluye
abs="$(cd "$SIGTEC_ROOT" && echo "$files" | grep -v -e '^evidence/' -e '^audit/' | tr '\n' '\0' | xargs -0 grep -l -E '/Users/[A-Za-z]|/home/[a-z]|C:\\\\Users' 2>/dev/null || true)"
[ -z "$abs" ] && res PASS repo.sin_rutas_absolutas "sin rutas de usuario en el código" || res FAIL repo.sin_rutas_absolutas "$abs"
if grep -q '^\.env$' "$SIGTEC_ROOT/.gitignore"; then res PASS repo.env_ignorado ".env en .gitignore"; else res FAIL repo.env_ignorado ".env no está en .gitignore"; fi
envperm="$(ls -l "$SIGTEC_ROOT/.env" | cut -c1-10)"
[ "$envperm" = "-rw-------" ] && res PASS repo.env_permisos "$envperm" || res FAIL repo.env_permisos "$envperm (esperado -rw-------)"
floating="$(grep -nE 'image:.*:latest|FROM [^@]*:latest' "$SIGTEC_ROOT/compose.yaml" "$SIGTEC_ROOT/docker/postgis/Dockerfile" || true)"
[ -z "$floating" ] && res PASS repo.sin_etiquetas_flotantes "imágenes fijadas (Dockerfile por digest)" || res FAIL repo.sin_etiquetas_flotantes "$floating"

if [ "$FULL" = 1 ]; then
    snapshot() {
        tools -c '. scripts/lib/db.sh; for n in $SIGTEC_CAMPUS_NODES; do s=$(node_schema $n);
          psql_su $n -tA -c "SELECT '"'"'$n'"'"', count(*), sum(id) FROM (SELECT id FROM $s.edificios UNION ALL SELECT id FROM $s.carreteras UNION ALL SELECT id FROM $s.aceras UNION ALL SELECT id FROM $s.parqueos UNION ALL SELECT id FROM $s.zonas_verdes UNION ALL SELECT id FROM $s.puntos_interes UNION ALL SELECT id FROM $s.iluminacion UNION ALL SELECT id FROM $s.accesibilidad) t" -c "SELECT count(*) FROM ops.schema_migrations"; done' 2>/dev/null
    }
    # --- 4. Idempotencia -----------------------------------------------
    h_log "[4] idempotencia: se repiten migraciones y carga de datos"
    before="$(snapshot)"
    tools scripts/db/migrate.sh all >/dev/null 2>&1 && tools scripts/db/seed.sh campus >/dev/null 2>&1
    after="$(snapshot)"
    [ "$before" = "$after" ] && res PASS reproducibilidad.segundo_arranque_sin_duplicados "$(echo "$after" | grep '|' | tr '\n' ' ')" \
                             || res FAIL reproducibilidad.segundo_arranque_sin_duplicados "antes: $before / después: $after"

    # --- 5. Persistencia tras reinicio ----------------------------------
    h_log "[5] persistencia: reinicio de los seis contenedores"
    before="$(snapshot)"
    compose restart $(node_services all) >/dev/null 2>&1
    sleep 3
    if wait_healthy 240 $(node_services all); then
        after="$(snapshot)"
        [ "$before" = "$after" ] && res PASS persistencia.datos_tras_reinicio "conteos e ids idénticos tras docker compose restart" \
                                 || res FAIL persistencia.datos_tras_reinicio "antes: $before / después: $after"
        res PASS persistencia.healthchecks_tras_reinicio "los seis nodos volvieron a healthy"
    else
        res FAIL persistencia.healthchecks_tras_reinicio "algún nodo no volvió a healthy"
    fi
fi

echo "----"
if [ "$FAILS" = 0 ]; then h_log "RESULTADO: todas las pruebas pasaron"; else h_log "RESULTADO: $FAILS grupo(s)/prueba(s) con fallas"; fi
[ "$FAILS" = 0 ]
