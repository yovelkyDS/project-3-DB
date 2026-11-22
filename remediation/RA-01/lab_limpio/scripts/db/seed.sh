#!/usr/bin/env bash
# =====================================================================
# SIG-TEC · carga los datos de prueba sintéticos en los campus (idempotente)
#   uso (en sigtec-tools):  scripts/db/seed.sh [campus|<nodo> ...]
#
# Un conjunto ya registrado en ops.seed_runs NO se vuelve a cargar, aunque
# se hayan borrado o editado filas (así un segundo "setup" no duplica ni
# resucita datos que el Integrante 2 haya modificado en sus pruebas).
# =====================================================================
. "${SIGTEC_HOME:-/opt/sigtec}/scripts/lib/db.sh"

SEED_NAME="datos_sinteticos_v1"
SEED_FILE="$SIGTEC_HOME/sql/seed/$SEED_NAME.sql"

main() {
    local node schema lon lat filas targets
    # Asignación separada: un destino inválido detiene el script (en "for x in $(...)" se perdía)
    targets="$(nodes_expand "${@:-campus}")" || die "destino inválido: ${*:-campus}"
    for node in $targets; do
        node_is_campus "$node" || { log "omitido $node: el nodo central no tiene capas originales"; continue; }
        wait_node "$node" 120
        if [ "$(sql_value "$node" "SELECT count(*) FROM ops.seed_runs WHERE seed_name = '$SEED_NAME'")" != "0" ]; then
            log "$node: $SEED_NAME ya estaba cargado (sin cambios)"
            continue
        fi
        schema="$(node_schema "$node")"
        read -r lon lat <<<"$(node_anchor "$node")"
        psql_su "$node" --single-transaction \
            -v schema="$schema" -v campus_id="$(node_campus_id "$node")" \
            -v campus_lon="$lon" -v campus_lat="$lat" \
            -v campus_code="$(node_code_prefix "$node")" -v campus_corto="$(node_corto "$node")" \
            -v seed_name="$SEED_NAME" \
            -f "$SEED_FILE" \
            -f - <<'SQL'
INSERT INTO ops.seed_runs (seed_name, filas, descripcion)
SELECT :'seed_name',
       (SELECT count(*) FROM (
            SELECT id FROM :"schema".edificios      UNION ALL SELECT id FROM :"schema".carreteras
  UNION ALL SELECT id FROM :"schema".aceras         UNION ALL SELECT id FROM :"schema".parqueos
  UNION ALL SELECT id FROM :"schema".zonas_verdes   UNION ALL SELECT id FROM :"schema".puntos_interes
  UNION ALL SELECT id FROM :"schema".iluminacion    UNION ALL SELECT id FROM :"schema".accesibilidad) t),
       'Datos SINTÉTICOS de prueba (no representan infraestructura real del TEC), generados alrededor de una coordenada aproximada del campus y transformados de EPSG:4326 a EPSG:5367.';
SQL
        filas="$(sql_value "$node" "SELECT filas FROM ops.seed_runs WHERE seed_name = '$SEED_NAME'")"
        log "$node: $SEED_NAME cargado ($filas objetos)"
    done
}

main "$@"
