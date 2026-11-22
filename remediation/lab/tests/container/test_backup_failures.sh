#!/usr/bin/env bash
# =====================================================================
# SIG-TEC · pruebas de regresión F-01: los respaldos fallan de verdad
#   (dentro de sigtec-tools)  tests/container/test_backup_failures.sh [--quick]
#
# Todos los casos escriben en BACKUP_ROOT temporales bajo /tmp del contenedor
# efímero: el volumen real de respaldos (/backups) NO se modifica.
# Los nodos no se detienen: el "servidor inaccesible" se simula redirigiendo
# su nombre en /etc/hosts de ESTE contenedor efímero.
# --quick omite los casos positivos/negativos de seis nodos (solo central/limon).
# Salida: líneas PASS|FAIL|<caso>|<detalle> y resumen; código 1 si alguna falla.
# =====================================================================
. "${SIGTEC_HOME:-/opt/sigtec}/scripts/lib/backup.sh"
set +e   # este archivo evalúa códigos de salida a mano

T="$SIGTEC_HOME/scripts/backup"
ROOT="$(mktemp -d /tmp/sigtec-bt.XXXXXX)"
RESULTS="$ROOT/results"; : > "$RESULTS"
QUICK=0; [ "${1:-}" = "--quick" ] && QUICK=1
ALL_NODES="$SIGTEC_NODES"; [ "$QUICK" = 1 ] && ALL_NODES="central limon"

rec() { echo "$1|$2|$3" | tee -a "$RESULTS"; }

# corre <tipo> <raíz> <env...> -- <nodos...> ; deja RC, OUT
corre() {
    local kind="$1" root="$2"; shift 2
    local -a envs=()
    while [ "$1" != "--" ]; do envs+=("$1"); shift; done; shift
    OUT="$(env BACKUP_ROOT="$root" "${envs[@]}" bash "$T/${kind}_backup.sh" "$@" 2>&1)"; RC=$?
}
publicados() {  # publicados <raíz> <tipo> -> número de respaldos publicados (sin .en-curso/.fallido)
    ls -1d "$1/$2"/*/*/ 2>/dev/null | wc -l | tr -d ' '
}
ok_lines()  { echo "$OUT" | grep -c '  OK ' ; }
log_rows()  { [ -f "$1/backup_log.tsv" ] && awk -F'\t' -v r="$2" 'NR > 1 && $5 == r' "$1/backup_log.tsv" | wc -l | tr -d ' ' || echo 0; }

# Afirma que un caso NEGATIVO falló sin dejar nada publicado ni OK
negativo() {   # negativo <caso> <raíz> <tipo> <errores_esperados>
    local caso="$1" root="$2" kind="$3" n="$4" pub ok err
    pub="$(publicados "$root" "$kind")"; ok="$(ok_lines)"; err="$(log_rows "$root" ERROR)"
    if [ "$RC" != 0 ] && [ "$pub" = 0 ] && [ "$ok" = 0 ] && [ "$(log_rows "$root" OK)" = 0 ] \
       && { [ "$n" = - ] || [ "$err" = "$n" ]; }; then
        rec PASS "$caso" "rc=$RC, 0 publicados, 0 OK, $err ERROR en bitácora"
    else
        rec FAIL "$caso" "rc=$RC publicados=$pub lineas_OK=$ok errores_bitacora=$err (esperados $n)"
        echo "$OUT" | tail -8 | sed 's/^/    /'
    fi
}

for kind in logical physical; do
    # 1. contraseña incorrecta (todos los nodos)
    r="$ROOT/$kind-clave"; corre "$kind" "$r" SIGTEC_BACKUP_PASSWORD=clave-deliberadamente-invalida -- $ALL_NODES
    negativo "$kind.contrasena_incorrecta[$(echo $ALL_NODES | wc -w | tr -d ' ') nodos]" "$r" "$kind" "$(echo $ALL_NODES | wc -w | tr -d ' ')"
    echo "$OUT" | grep -q 'password authentication failed' \
        && rec PASS "$kind.diagnostico_autenticacion" "mensaje de PostgreSQL mostrado" \
        || rec FAIL "$kind.diagnostico_autenticacion" "no se mostró el error de autenticación"
    echo "$OUT" | grep -q 'clave-deliberadamente-invalida' \
        && rec FAIL "$kind.sin_secretos_en_salida" "la contraseña aparece en la salida" \
        || rec PASS "$kind.sin_secretos_en_salida" "la contraseña no aparece en la salida"

    # 2. usuario inexistente
    r="$ROOT/$kind-usuario"; corre "$kind" "$r" SIGTEC_BACKUP_USER=sigtec_usuario_inexistente -- central
    negativo "$kind.usuario_inexistente" "$r" "$kind" 1

    # 3. servidor inaccesible (nombre redirigido a una dirección sin servidor)
    cp /etc/hosts "$ROOT/hosts.orig"; echo "127.0.0.9 pg-limon" >> /etc/hosts
    r="$ROOT/$kind-inaccesible"; corre "$kind" "$r" PGCONNECT_TIMEOUT=5 -- limon
    cat "$ROOT/hosts.orig" > /etc/hosts
    negativo "$kind.servidor_inaccesible" "$r" "$kind" 1

    # 4. sin permiso de escritura (montaje de solo lectura)
    corre "$kind" "$SIGTEC_HOME/tests/no-escribible" -- central
    if [ "$RC" != 0 ] && [ ! -e "$SIGTEC_HOME/tests/no-escribible" ]; then
        rec PASS "$kind.sin_permiso_escritura" "rc=$RC, nada creado"
    else rec FAIL "$kind.sin_permiso_escritura" "rc=$RC"; fi

    # 5. directorio de salida inválido
    corre "$kind" /dev/null/respaldos -- central
    [ "$RC" != 0 ] && rec PASS "$kind.directorio_invalido" "rc=$RC" || rec FAIL "$kind.directorio_invalido" "rc=$RC"

    # 6. fallo de escritura a mitad de la copia (límite de tamaño de archivo)
    r="$ROOT/$kind-escritura"; mkdir -p "$r"
    OUT="$( (ulimit -f 48; BACKUP_ROOT="$r" bash "$T/${kind}_backup.sh" cartago) 2>&1)"; RC=$?
    negativo "$kind.fallo_escritura_parcial" "$r" "$kind" 1
    resto="$(find "$r/$kind" \( -name sigtec.dump -o -name base -o -name PG_VERSION \) 2>/dev/null | wc -l | tr -d ' ')"
    [ "$resto" = 0 ] && rec PASS "$kind.sin_archivos_parciales" "el directorio .fallido-* no conserva carga útil" \
                     || rec FAIL "$kind.sin_archivos_parciales" "$resto archivos de carga útil quedaron en disco"

    # 7. el código sobrevive a un pipeline (pipefail del llamador)
    r="$ROOT/$kind-pipe"
    ( set -o pipefail; BACKUP_ROOT="$r" SIGTEC_BACKUP_PASSWORD=x bash "$T/${kind}_backup.sh" central 2>&1 | cat > /dev/null ); RC=$?
    [ "$RC" != 0 ] && rec PASS "$kind.codigo_en_pipeline" "rc=$RC a través de | cat" || rec FAIL "$kind.codigo_en_pipeline" "rc=$RC"
done

# 8. positivo: respaldos válidos de los nodos, validación y restauración aislada
P="$ROOT/positivo"; r="$P"
for kind in logical physical; do
    corre "$kind" "$r" -- $ALL_NODES
    n="$(echo $ALL_NODES | wc -w | tr -d ' ')"; pub="$(publicados "$r" "$kind")"
    if [ "$RC" = 0 ] && [ "$pub" = "$n" ] && [ "$(ok_lines)" = "$n" ]; then
        rec PASS "$kind.respaldo_valido[$n nodos]" "rc=0, $pub publicados"
    else rec FAIL "$kind.respaldo_valido" "rc=$RC publicados=$pub"; echo "$OUT" | tail -8; fi
done
for node in $ALL_NODES; do
    d="$(latest_dir "$r/logical/$node")"
    ( set -e; validate_logical_dir "$d" "$node" ) 2>/dev/null && rec PASS "logical.validacion[$node]" "TOC, datos y contenido OK" || rec FAIL "logical.validacion[$node]" "$d"
done
OUT="$(BACKUP_ROOT="$r" bash "$T/logical_restore_test.sh" $ALL_NODES 2>&1)"; RC=$?
[ "$RC" = 0 ] && [ "$(echo "$OUT" | grep -c 'VÁLIDA')" = "$(echo $ALL_NODES | wc -w | tr -d ' ')" ] \
    && rec PASS "logical.restauracion_aislada" "$(echo "$OUT" | grep -c 'VÁLIDA') restauraciones VÁLIDAS" \
    || { rec FAIL "logical.restauracion_aislada" "rc=$RC"; echo "$OUT" | tail -8; }
OUT="$(BACKUP_ROOT="$r" bash "$T/physical_restore_test.sh" $ALL_NODES 2>&1)"; RC=$?
[ "$RC" = 0 ] && [ "$(echo "$OUT" | grep -c 'RECUPERABLE')" = "$(echo $ALL_NODES | wc -w | tr -d ' ')" ] \
    && rec PASS "physical.recuperacion_aislada" "$(echo "$OUT" | grep -c 'RECUPERABLE') copias RECUPERABLES" \
    || { rec FAIL "physical.recuperacion_aislada" "rc=$RC"; echo "$OUT" | tail -8; }

# 9. un fallo posterior conserva el respaldo válido anterior como el más reciente
for kind in logical physical; do
    before="$(latest_dir "$r/$kind/central")"
    sleep 1
    corre "$kind" "$r" SIGTEC_BACKUP_PASSWORD=x -- central
    after="$(latest_dir "$r/$kind/central")"
    [ "$RC" != 0 ] && [ -n "$before" ] && [ "$before" = "$after" ] && [ -d "$before" ] \
        && rec PASS "$kind.conserva_respaldo_anterior" "el último publicado sigue siendo $(basename "$before")" \
        || rec FAIL "$kind.conserva_respaldo_anterior" "antes=$before después=$after rc=$RC"
done

# 10. fallo parcial: un nodo cae y el resto se respalda; código global ≠ 0
cp /etc/hosts "$ROOT/hosts.orig"; echo "127.0.0.9 pg-limon" >> /etc/hosts
r="$ROOT/mixto"; corre logical "$r" PGCONNECT_TIMEOUT=5 -- central limon
cat "$ROOT/hosts.orig" > /etc/hosts
[ "$RC" != 0 ] && [ "$(publicados "$r" logical)" = 1 ] && [ -n "$(latest_dir "$r/logical/central")" ] && [ -z "$(latest_dir "$r/logical/limon")" ] \
    && rec PASS "logical.fallo_parcial" "rc=$RC; central publicado, limon no" \
    || rec FAIL "logical.fallo_parcial" "rc=$RC publicados=$(publicados "$r" logical)"

# 11. la validación rechaza artefactos dañados
c="$ROOT/danado"; mkdir -p "$c/l" "$c/p"
d="$(latest_dir "$P/logical/cartago")"
[ -n "$d" ] || rec FAIL logical.rechaza_dump_truncado "no hay respaldo positivo de cartago para alterar"
if [ -n "$d" ]; then
    cp "$d/globals.sql" "$c/l/"; head -c "$(( $(stat -c %s "$d/sigtec.dump") * 6 / 10 ))" "$d/sigtec.dump" > "$c/l/sigtec.dump"
    ( set -e; validate_logical_dir "$c/l" cartago ) 2>/dev/null && rec FAIL logical.rechaza_dump_truncado "aceptado" \
        || rec PASS logical.rechaza_dump_truncado "pg_restore detectó el truncamiento"
fi
d="$(latest_dir "$P/physical/central")"
[ -n "$d" ] || rec FAIL physical.rechaza_copia_alterada "no hay copia positiva de central para alterar"
if [ -n "$d" ]; then
    cp -a "$d/data" "$c/p/data"
    f="$(find "$c/p/data/base" -type f -size +8k | head -1)"
    printf 'X' | dd of="$f" bs=1 seek=100 conv=notrunc 2>/dev/null
    ( set -e; validate_physical_dir "$c/p" ) 2>/dev/null && rec FAIL physical.rechaza_copia_alterada "aceptada" \
        || rec PASS physical.rechaza_copia_alterada "pg_verifybackup detectó la alteración"
    rm -f "$c/p/data/backup_manifest"
    ( set -e; validate_physical_dir "$c/p" ) 2>/dev/null && rec FAIL physical.rechaza_sin_manifiesto "aceptada" \
        || rec PASS physical.rechaza_sin_manifiesto "falta backup_manifest"
fi

rm -rf "$ROOT"/positivo "$ROOT"/danado "$ROOT"/*-* 2>/dev/null
pass="$(grep -c '^PASS|' "$RESULTS")"; fail="$(grep -c '^FAIL|' "$RESULTS")"
echo "----"
echo "RESUMEN respaldos: $pass PASS, $fail FAIL"
[ "$fail" = 0 ]
