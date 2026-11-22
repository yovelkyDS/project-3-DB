#!/usr/bin/env bash
# =====================================================================
# SIG-TEC · pruebas automatizadas que corren DENTRO de sigtec-tools
#   tests/container/run_sql_tests.sh [all|campus|<nodo> ...]
# Imprime una línea PASS|FAIL por prueba y un resumen. Código 1 si alguna falla.
# =====================================================================
. "${SIGTEC_HOME:-/opt/sigtec}/scripts/lib/db.sh"
T="$SIGTEC_HOME/tests"
RESULTS="$(mktemp)"

run_sql() {   # run_sql <nodo> <archivo> [vars...]
    local node="$1" file="$2"; shift 2
    PGOPTIONS="-c client_min_messages=warning" psql_su "$node" -tA "$@" \
        -f "$T/sql/00_helpers.sql" -f "$file" 2>&1 \
      | grep -E '^(PASS|FAIL)\|' >> "$RESULTS" \
      || echo "FAIL|$node.$(basename "$file")|el archivo no produjo resultados (error de ejecución)" >> "$RESULTS"
}

record() { echo "$1|$2|$3" >> "$RESULTS"; }

nodes="$(nodes_expand "${@:-all}")"
for node in $nodes; do
    wait_node "$node" 60
    cid="$(node_campus_id "$node")"
    run_sql "$node" "$T/sql/10_infra.sql" -v node="$node" -v campus_id="$cid"
    if node_is_campus "$node"; then
        run_sql "$node" "$T/sql/20_modelo.sql" -v node="$node" -v schema="$(node_schema "$node")" \
            -v campus_id="$cid" -v code_prefix="$(node_code_prefix "$node")"
        run_sql "$node" "$T/sql/30_reglas_identificadores.sql" -v node="$node" \
            -v schema="$(node_schema "$node")" -v campus_id="$cid"
    fi
done

# --- Unicidad global de identificadores entre los cinco campus -----------
campus_in_run=""
for node in $nodes; do node_is_campus "$node" && campus_in_run="$campus_in_run $node"; done
if [ "$(echo $campus_in_run | wc -w)" -eq 5 ]; then
    all_ids="$(mktemp)"
    for node in $campus_in_run; do
        s="$(node_schema "$node")"
        psql_su "$node" -tA -c "SELECT id || '|' || campus_id || '|$node' FROM (
              SELECT id, campus_id FROM $s.edificios UNION ALL SELECT id, campus_id FROM $s.carreteras
    UNION ALL SELECT id, campus_id FROM $s.aceras UNION ALL SELECT id, campus_id FROM $s.parqueos
    UNION ALL SELECT id, campus_id FROM $s.zonas_verdes UNION ALL SELECT id, campus_id FROM $s.puntos_interes
    UNION ALL SELECT id, campus_id FROM $s.iluminacion UNION ALL SELECT id, campus_id FROM $s.accesibilidad) t" >> "$all_ids"
    done
    total="$(wc -l < "$all_ids" | tr -d ' ')"
    dups="$(cut -d'|' -f1 "$all_ids" | sort | uniq -d | wc -l | tr -d ' ')"
    bad_prefix="$(awk -F'|' '{ if (int($1 / 1000000000) != $2) n++ } END { print n + 0 }' "$all_ids")"
    if [ "$dups" = 0 ] && [ "$bad_prefix" = 0 ] && [ "$total" -gt 0 ]; then
        record PASS global.ids_unicos_entre_campus "$total ids en 5 campus, 0 duplicados, prefijo = campus_id en todos"
    else
        record FAIL global.ids_unicos_entre_campus "$total ids, $dups duplicados, $bad_prefix con prefijo incorrecto"
    fi
    rm -f "$all_ids"
fi

# --- Compatibilidad de la plantilla de tablas destino del central --------
if [ "$(echo $campus_in_run | wc -w)" -eq 5 ]; then
    if out="$(bash "$T/container/test_template_central.sh" 2>&1)"; then
        record PASS global.plantilla_central_compatible "$(echo "$out" | tail -1)"
    else
        record FAIL global.plantilla_central_compatible "$(echo "$out" | tail -3 | tr '\n' ' ')"
    fi
fi

# --- Resumen ------------------------------------------------------------
awk -F'|' '{ printf "%-5s %-58s %s\n", $1, $2, $3 }' "$RESULTS"
pass="$(grep -c '^PASS|' "$RESULTS" || true)"
fail="$(grep -c '^FAIL|' "$RESULTS" || true)"
echo "----"
echo "RESUMEN: $pass PASS, $fail FAIL"
rm -f "$RESULTS"
[ "$fail" = 0 ]
