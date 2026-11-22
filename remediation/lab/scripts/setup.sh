#!/usr/bin/env bash
# =====================================================================
# SIG-TEC · instalador / bootstrap (Linux, macOS, WSL2, Git Bash)
#
#   scripts/setup.sh            instala o actualiza sin destruir datos
#   scripts/setup.sh --no-seed  no carga datos de prueba
#
# Pasos: 1 requisitos · 2 .env y credenciales · 3 imagen · 4 red/volúmenes y
# seis nodos · 5 espera healthy · 6 migraciones (PostGIS, esquemas, tablas,
# reglas de id, rol de respaldo) · 7 datos de prueba · 8 verificación · 9 resumen
#
# Idempotente: un segundo arranque reutiliza volúmenes, no reaplica
# migraciones registradas y no duplica datos de prueba.
# =====================================================================
set -eu
. "$(cd "$(dirname "$0")" && pwd)/lib/host.sh"

SEED=1
for a in "$@"; do
    case "$a" in
        --no-seed) SEED=0 ;;
        -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
        *) h_die "opción desconocida: $a" ;;
    esac
done

LOG="$(evidence_file setup "setup_$(date +%Y%m%d_%H%M%S).log")"
exec > >(tee -a "$LOG") 2>&1

gen_secret() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -base64 48 | LC_ALL=C tr -dc 'A-Za-z0-9' | cut -c1-32
    else
        LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom 2>/dev/null | dd bs=32 count=1 2>/dev/null
    fi
}

prepare_env() {
    local env="$SIGTEC_ROOT/.env" tmp line key generated=0
    if [ ! -f "$env" ]; then
        cp "$SIGTEC_ROOT/.env.example" "$env"
        h_log ".env creado a partir de .env.example"
    fi
    # Completa solo los marcadores __GENERAR__; nunca reemplaza valores existentes.
    # Variables nuevas de .env.example que falten en .env se agregan al final.
    tmp="$env.tmp.$$"
    : > "$tmp"
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            *=__GENERAR__) key="${line%%=*}"; echo "$key=$(gen_secret)" >> "$tmp"; generated=$((generated + 1)) ;;
            *) printf '%s\n' "$line" >> "$tmp" ;;
        esac
    done < "$env"
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in \#*|"") continue ;; esac
        key="${line%%=*}"
        if ! grep -q "^$key=" "$tmp"; then
            case "$line" in
                *=__GENERAR__) echo "$key=$(gen_secret)" >> "$tmp"; generated=$((generated + 1)) ;;
                *) printf '%s\n' "$line" >> "$tmp" ;;
            esac
        fi
    done < "$SIGTEC_ROOT/.env.example"
    mv "$tmp" "$env"
    chmod 600 "$env" 2>/dev/null || true
    h_log ".env listo ($generated credenciales generadas; los valores no se muestran)"
}

h_log "== SIG-TEC · instalación (registro: ${LOG#"$SIGTEC_ROOT"/}) =="

h_log "[1/9] requisitos del host"
"$SIGTEC_ROOT/scripts/check_prereqs.sh" --start-docker || h_die "corrija los requisitos indicados y vuelva a ejecutar"

h_log "[2/9] configuración local y credenciales"
prepare_env
load_env

h_log "[3/9] imagen ${SIGTEC_IMAGE:-sigtec/postgis:17.12-3.5.4} (PostgreSQL 17.12 + PostGIS 3.5.4)"
compose build pg-central

h_log "[4/9] red, volúmenes e inicio de los seis nodos"
compose up -d $(node_services all)

h_log "[5/9] esperando estado healthy"
wait_healthy 300 $(node_services all) || h_die "algún nodo no quedó healthy; revise: make logs"
compose ps

h_log "[6/9] migraciones (PostGIS, ops, esquemas locales, ocho capas, identificadores, rol de respaldo)"
tools scripts/db/migrate.sh all

if [ "$SEED" = 1 ]; then
    h_log "[7/9] datos de prueba sintéticos"
    tools scripts/db/seed.sh campus
else
    h_log "[7/9] datos de prueba omitidos (--no-seed)"
fi

h_log "[8/9] verificación inicial"
tools scripts/db/verify.sh

h_log "[9/9] resumen"
cat <<EOF

  SIG-TEC desplegado. Conexiones desde esta máquina (base: sigtec, SRID 5367):
    Central     ${SIGTEC_BIND_ADDRESS:-127.0.0.1}:$(node_port central)
    Cartago     ${SIGTEC_BIND_ADDRESS:-127.0.0.1}:$(node_port cartago)     campus_id 1  esquema local_cartago
    San José    ${SIGTEC_BIND_ADDRESS:-127.0.0.1}:$(node_port san_jose)     campus_id 2  esquema local_san_jose
    San Carlos  ${SIGTEC_BIND_ADDRESS:-127.0.0.1}:$(node_port san_carlos)     campus_id 3  esquema local_san_carlos
    Alajuela    ${SIGTEC_BIND_ADDRESS:-127.0.0.1}:$(node_port alajuela)     campus_id 4  esquema local_alajuela
    Limón       ${SIGTEC_BIND_ADDRESS:-127.0.0.1}:$(node_port limon)     campus_id 5  esquema local_limon
  Credenciales: archivo .env (no versionado).
  Siguientes pasos:  make test · make backup · make pitr-demo · make help
EOF
