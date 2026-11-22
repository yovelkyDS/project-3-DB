#!/usr/bin/env bash
# =====================================================================
# SIG-TEC · aplica migraciones versionadas a los nodos (idempotente)
#   uso (en sigtec-tools):  scripts/db/migrate.sh [all|campus|recovery|<nodo> ...]
#   desde el host:          make migrate [NODE=...]      make migrate NODE=recovery
#
# * sql/bootstrap/*          se ejecuta siempre (IF NOT EXISTS)
# * sql/migrations/common/*  en los seis nodos
# * sql/migrations/campus/*  solo en los cinco campus (y en una copia recuperada de un campus)
# Cada migración corre en UNA transacción y queda registrada con su SHA-256
# en ops.schema_migrations; una migración registrada no se vuelve a aplicar.
#
# "all" y "campus" son los nodos en servicio. La instancia recuperada
# (pg-recovery) se migra SOLO cuando se nombra explícitamente ("recovery"):
#   1. debe existir, aceptar conexiones y estar PROMOVIDA (no en recuperación);
#   2. su identidad lógica se toma de la propia copia (ops.node_info) y se
#      contrasta con SIGTEC_RECOVERY_INFO; nunca se usa la del nodo en servicio;
#   3. se inspecciona (migraciones, conteos, ids repetidos entre capas,
#      disparadores, secuencia) y, si hay ids repetidos, NO se migra;
#   4. antes de aplicar migraciones pendientes se toma y valida un pg_dump en
#      $BACKUP_ROOT/recovery_pre_migracion/<UTC>/;
#   5. no se reescribe ops.node_info (conserva la identidad del campus restaurado).
# Después de migrar un campus (o su copia recuperada) se exige que no queden
# migraciones pendientes y que sql/checks/verificar_0103.sql pase completo.
#
# Códigos de salida: 0 correcto · 1 error SQL / migración / verificación
#   2 destino inválido · 3 nodo inexistente, inaccesible o credenciales rechazadas
#   4 estado incompatible (no promovida, identidad inconsistente) · 5 ids repetidos
# =====================================================================
. "${SIGTEC_HOME:-/opt/sigtec}/scripts/lib/db.sh"
# Un fallo dentro de $(...) también detiene el script (sin esto Bash lo ignora)
shopt -s inherit_errexit

SQL="$SIGTEC_HOME/sql"
WAIT_TIMEOUT="${SIGTEC_WAIT_TIMEOUT:-120}"
CURRENT=""

fail() { local code="${2:-1}"; log "ERROR: $1"; exit "$code"; }
trap 'rc=$?; [ "$rc" = 0 ] || log "RESULTADO: migración FALLIDA${CURRENT:+ en $CURRENT} (código $rc). Cada migración se aplica en una sola transacción: ninguna queda a medias"' EXIT

# Destinos: catálogo de nodos en servicio + "recovery" (solo si se nombra)
expand_targets() {
    local n rest="" out="" list
    for n in $(echo "${*:-all}" | tr ',' ' '); do
        if [ "$n" = recovery ]; then out="$out recovery"; else rest="$rest $n"; fi
    done
    if [ -n "$rest" ]; then
        list="$(nodes_expand $rest)" || return 2
        out="$list$out"
    fi
    [ -n "$out" ] || return 2
    echo $out
}

wait_ready() {
    local host i=0
    host="$(target_host "$1")"
    until pg_isready -q -h "$host" -p 5432 -d "$SIGTEC_DB" -U postgres; do
        i=$((i + 1)); [ "$i" -ge "$WAIT_TIMEOUT" ] && return 1; sleep 1
    done
}

# Comprueba que el destino existe, responde y acepta las credenciales
check_reachable() {
    local t="$1" host out
    host="$(target_host "$t")"
    getent hosts "$host" >/dev/null 2>&1 || {
        [ "$t" = recovery ] && fail "pg-recovery no existe o no está en ejecución en este proyecto (estado: make recovery-status; crear: make pitr-demo o docker compose --profile recovery up -d pg-recovery)" 3
        fail "el nodo $t ($host) no existe o no está en ejecución" 3; }
    wait_ready "$t" || fail "el nodo $t ($host) no aceptó conexiones en ${WAIT_TIMEOUT}s" 3
    out="$(psql_su "$t" -tAc "SELECT 1" 2>&1)" || fail "no se pudo conectar a $host como postgres: $(echo "$out" | grep -m1 -E 'FATAL|error' | sed 's/.*FATAL: *//')" 3
}

# Identidad lógica de pg-recovery, tomada de la copia restaurada.
# Deja LOGICAL (nodo de origen) en la variable global.
resolve_recovery() {
    local info code cid schema src tl
    [ "$(sql_value recovery "SELECT pg_is_in_recovery()")" = f ] ||
        fail "pg-recovery sigue en recuperación (reproduciendo WAL o en pausa; solo lectura). Espere a que termine o promuévala (SELECT pg_promote()) antes de migrar" 4
    [ "$(sql_value recovery "SELECT to_regclass('ops.node_info') IS NOT NULL")" = t ] ||
        fail "pg-recovery no contiene ops.node_info: no es una copia de un nodo SIG-TEC" 4
    info="$(sql_value recovery "SELECT coalesce(node_code,'') || '|' || coalesce(campus_id::text,'') || '|' || coalesce(local_schema,'') FROM ops.node_info")"
    code="${info%%|*}"; info="${info#*|}"; cid="${info%%|*}"; schema="${info#*|}"
    node_valid "$code" || fail "pg-recovery: ops.node_info indica un nodo desconocido ('$code')" 4
    [ "$cid" = "$(node_campus_id "$code")" ] || fail "pg-recovery: campus_id '$cid' no corresponde al nodo '$code'" 4
    [ "$schema" = "$(node_schema "$code")" ] || fail "pg-recovery: esquema '$schema' no corresponde al nodo '$code'" 4
    if [ -n "$schema" ] && [ "$(sql_value recovery "SELECT to_regnamespace('$schema') IS NOT NULL")" != t ]; then
        fail "pg-recovery: el esquema $schema no existe en la copia" 4
    fi
    src="$(sql_value recovery "SELECT coalesce(substring(pg_read_file('SIGTEC_RECOVERY_INFO', true) from 'source_node=([a-z_]+)'), '')")"
    if [ -n "$src" ] && [ "$src" != "$code" ]; then
        fail "pg-recovery: identidad inconsistente (SIGTEC_RECOVERY_INFO: $src; ops.node_info: $code)" 4
    fi
    tl="$(sql_value recovery "SELECT timeline_id FROM pg_control_checkpoint()")"
    LOGICAL="$code"
    log "  pg-recovery: copia promovida de $code (campus_id ${cid:--}, esquema ${schema:--}; SIGTEC_RECOVERY_INFO: ${src:-no disponible}; línea de tiempo $tl)"
}

migration_files() {   # migration_files <nodo lógico>
    local f
    for f in "$SQL"/migrations/common/*.sql; do echo "$f"; done
    if node_is_campus "$1"; then for f in "$SQL"/migrations/campus/*.sql; do echo "$f"; done; fi
}
version_of() { local v="${1#"$SQL/migrations/"}"; echo "${v%.sql}"; }

pending_migrations() {   # pending_migrations <destino> <nodo lógico>
    local t="$1" l="$2" applied="" f v
    if [ "$(sql_value "$t" "SELECT to_regclass('ops.schema_migrations') IS NOT NULL")" = t ]; then
        applied=" $(sql_value "$t" "SELECT coalesce(string_agg(version, ' '), '') FROM ops.schema_migrations") "
    fi
    for f in $(migration_files "$l"); do
        v="$(version_of "$f")"
        case "$applied" in *" $v "*) ;; *) echo "$v" ;; esac
    done
}

union_ids() {
    local s="$1" l u=""
    for l in $SIGTEC_LAYERS; do u="$u${u:+ UNION ALL }SELECT id, '$l'::text AS capa FROM $s.$l"; done
    echo "$u"
}

# Inspección previa (solo lectura) de la instancia recuperada. Devuelve 5 si hay ids repetidos.
inspect_recovery() {
    local l="$1" s c dups
    s="$(node_schema "$l")"
    log "  inspección previa de pg-recovery:"
    log "    migraciones registradas: $(sql_value recovery "SELECT coalesce(string_agg(version, ', ' ORDER BY version), 'ninguna') FROM ops.schema_migrations")"
    log "    migraciones pendientes: $(pending_migrations recovery "$l" | tr '\n' ' ' | sed 's/ $//;s/^$/ninguna/')"
    [ -n "$s" ] || return 0
    c="$(sql_value recovery "SELECT string_agg(capa || '=' || n, ' ' ORDER BY capa) || ' (total ' || sum(n) || ')' FROM (SELECT capa, count(*) AS n FROM ($(union_ids "$s")) o GROUP BY capa) x")"
    log "    objetos por capa: $c"
    log "    disparadores habilitados en $s: $(sql_value recovery "SELECT count(*) FILTER (WHERE t.tgenabled = 'O') || ' de ' || count(*) FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid WHERE c.relnamespace = '$s'::regnamespace AND NOT t.tgisinternal")"
    log "    secuencia $s.objeto_id_seq: $(sql_value recovery "SELECT 'último ' || last_value || CASE WHEN is_called THEN '' ELSE ' (sin usar)' END FROM $s.objeto_id_seq"); consecutivo máximo usado: $(sql_value recovery "SELECT coalesce(max(id) % 1000000000, 0) FROM ($(union_ids "$s")) o")"
    log "    registro global de ids: $(sql_value recovery "SELECT CASE WHEN to_regclass('ops.identificadores_globales') IS NULL THEN 'ausente (anterior a 0103)' ELSE 'presente' END")"
    dups="$(sql_value recovery "SELECT coalesce(string_agg(id || ' en ' || capas, '; '), '') FROM (SELECT id, string_agg(capa, '+' ORDER BY capa) AS capas FROM ($(union_ids "$s")) o GROUP BY id HAVING count(*) > 1 ORDER BY id LIMIT 20) d")"
    if [ -n "$dups" ]; then
        log "    ids repetidos entre capas: $dups"
        fail "pg-recovery tiene ids repetidos entre capas: no se migra ni se modifica ningún dato. Resuélvalo según docs/BACKUP_RECOVERY.md (\"Conflictos de identificadores\") y repita" 5
    fi
    log "    ids repetidos entre capas: 0"
}

# Respaldo lógico validado de pg-recovery antes de modificarla (publicación atómica)
backup_recovery() {
    local l="$1" s st base work final layer
    s="$(node_schema "$l")"; st="$(stamp)"
    base="$BACKUP_ROOT/recovery_pre_migracion"; work="$base/.en-curso-$st-$$"; final="$base/$st"
    mkdir -p "$work" || fail "no se pudo crear $work" 1
    PGPASSWORD="${POSTGRES_PASSWORD:?}" pg_dump -h pg-recovery -p 5432 -U postgres -w -d "$SIGTEC_DB" -Fc -f "$work/sigtec.dump" ||
        { rm -rf "$work"; fail "pg_dump de pg-recovery falló: no se migra" 1; }
    pg_restore --list "$work/sigtec.dump" > "$work/toc.txt" ||
        { rm -rf "$work"; fail "el respaldo previo de pg-recovery no tiene un TOC legible: no se migra" 1; }
    pg_restore --file=/dev/null "$work/sigtec.dump" ||
        { rm -rf "$work"; fail "el respaldo previo de pg-recovery no se pudo leer completo: no se migra" 1; }
    grep -q ' TABLE DATA ops node_info ' "$work/toc.txt" || { rm -rf "$work"; fail "el respaldo previo no contiene ops.node_info" 1; }
    if [ -n "$s" ]; then
        for layer in $SIGTEC_LAYERS; do
            grep -q " TABLE DATA $s $layer " "$work/toc.txt" || { rm -rf "$work"; fail "el respaldo previo no contiene $s.$layer" 1; }
        done
    fi
    { echo "nodo_logico=$l"; echo "destino=pg-recovery"; echo "fecha_utc=$st"
      echo "sha256=$(sha256sum "$work/sigtec.dump" | cut -d' ' -f1)"; echo "entradas_toc=$(grep -c '^[0-9]' "$work/toc.txt")"
      echo "migraciones_registradas=$(sql_value recovery "SELECT string_agg(version, ',' ORDER BY version) FROM ops.schema_migrations")"
    } > "$work/manifest.txt"
    mv -T "$work" "$final" || { rm -rf "$work"; fail "no se pudo publicar el respaldo previo" 1; }
    log "  respaldo previo validado: ${final#"$BACKUP_ROOT"/} ($(du -h "$final/sigtec.dump" | cut -f1))"
}

apply_migration() {
    local target="$1" node="$2" file="$3" version checksum applied
    version="$(version_of "$file")"
    # El checksum incluye los archivos incluidos con \ir (p. ej. sql/schema/capas_locales.sql)
    checksum="$( { cat "$file"
                   sed -n 's/^\\ir[[:space:]]\{1,\}//p' "$file" | while read -r inc; do
                       cat "$(dirname "$file")/$inc"; done
                 } | sha256sum | cut -d' ' -f1)"
    applied="$(sql_value "$target" "SELECT checksum FROM ops.schema_migrations WHERE version = '$version'")"
    if [ -n "$applied" ]; then
        if [ "$applied" != "$checksum" ]; then
            log "  AVISO $target: $version ya aplicada pero el archivo cambió (no se reaplica; cree una migración nueva)"
        fi
        return 0
    fi
    local -a vars=()
    if node_is_campus "$node"; then
        local schema; schema="$(node_schema "$node")"
        vars=(-v "schema=$schema" -v "campus_id=$(node_campus_id "$node")"
              -v "seq=$schema.objeto_id_seq"
              -v "schema_comment=SIG-TEC: tablas originales de $(node_nombre "$node") (campus_id $(node_campus_id "$node")).")
    fi
    psql_su "$target" --single-transaction "${vars[@]}" \
        -f "$file" \
        -c "INSERT INTO ops.schema_migrations(version, checksum) VALUES ('$version', '$checksum')" ||
        fail "$target: la migración $version falló; se revirtió completa y no quedó registrada" 1
    log "  $target: aplicada $version"
}

sync_node_info() {
    local node="$1" cid schema nombre
    cid="$(node_campus_id "$node")"; schema="$(node_schema "$node")"; nombre="$(node_nombre "$node")"
    psql_su "$node" -v node="$node" -v host="$(node_host "$node")" -v cid="$cid" \
        -v schema="$schema" -v nombre="$nombre" <<'SQL'
INSERT INTO ops.node_info AS n (node_code, node_host, campus_id, campus_nombre, local_schema)
VALUES (:'node', :'host', NULLIF(:'cid','')::smallint, :'nombre', NULLIF(:'schema',''))
ON CONFLICT (singleton) DO UPDATE
   SET node_code = EXCLUDED.node_code, node_host = EXCLUDED.node_host,
       campus_id = EXCLUDED.campus_id, campus_nombre = EXCLUDED.campus_nombre,
       local_schema = EXCLUDED.local_schema, updated_at = clock_timestamp()
 WHERE (n.node_code, n.node_host, n.campus_id, n.campus_nombre, n.local_schema)
       IS DISTINCT FROM (EXCLUDED.node_code, EXCLUDED.node_host, EXCLUDED.campus_id,
                         EXCLUDED.campus_nombre, EXCLUDED.local_schema);
SQL
}

# Verificación posterior: sin migraciones pendientes y 0103 operativa (campus)
post_check() {
    local t="$1" l="$2" pend out
    pend="$(pending_migrations "$t" "$l" | tr '\n' ' ' | sed 's/ $//')"
    [ -z "$pend" ] || fail "$t: siguen pendientes: $pend" 1
    node_is_campus "$l" || return 0
    # Solo si la versión del código incluye 0103 (p. ej. no en una copia anterior)
    [ -f "$SQL/migrations/campus/0103_registro_identificadores.sql" ] || return 0
    out="$(psql_su "$t" -v schema="$(node_schema "$l")" -v campus_id="$(node_campus_id "$l")" \
            -f "$SQL/checks/verificar_0103.sql")" || fail "$t: la verificación de 0103 no se pudo ejecutar" 1
    echo "$out" | sed 's/^/    /' >&2
    if echo "$out" | grep -q '^FAIL'; then fail "$t: la verificación posterior de 0103 falló" 1; fi
    [ "$(echo "$out" | grep -c '^PASS')" -ge 10 ] || fail "$t: la verificación posterior de 0103 no produjo las 10 comprobaciones" 1
}

recovery_notice() {   # aviso (no fatal) cuando "all" deja fuera una pg-recovery atrasada
    local n
    getent hosts pg-recovery >/dev/null 2>&1 || return 0
    pg_isready -q -h pg-recovery -p 5432 -d "$SIGTEC_DB" -U postgres || return 0
    n="$(sql_value recovery "SELECT node_code FROM ops.node_info" 2>/dev/null)" || return 0
    node_valid "$n" || return 0
    n="$(pending_migrations recovery "$n" 2>/dev/null | wc -l | tr -d ' ')" || return 0
    if [ "${n:-0}" != 0 ]; then
        log "AVISO: pg-recovery tiene $n migración(es) pendiente(s) y no se incluye en NODE=all. Ejecute: make migrate NODE=recovery"
    fi
}

main() {
    local targets t logical pend
    targets="$(expand_targets "$@")" || fail "destino inválido: '${*:-all}'. Use all, campus, recovery o uno de: $SIGTEC_NODES" 2
    for t in $targets; do
        CURRENT="$t"
        log "migrando $t ($(target_host "$t"))"
        check_reachable "$t"
        if [ "$t" = recovery ]; then
            resolve_recovery
            logical="$LOGICAL"
            inspect_recovery "$logical"
            pend="$(pending_migrations recovery "$logical")"
            [ -z "$pend" ] || backup_recovery "$logical"
        else
            logical="$t"
        fi
        psql_su "$t" -f "$SQL/bootstrap/00_ops_migraciones.sql" >/dev/null || fail "$t: bootstrap de ops falló" 1
        for f in $(migration_files "$logical"); do apply_migration "$t" "$logical" "$f"; done
        [ "$t" = recovery ] || sync_node_info "$t"
        psql_su "$t" -f "$SQL/roles/sigtec_backup.sql" >/dev/null || fail "$t: no se pudo sincronizar el rol sigtec_backup" 1
        post_check "$t" "$logical"
        log "  $t: $(sql_value "$t" "SELECT count(*) FROM ops.schema_migrations") migraciones registradas, ninguna pendiente; rol sigtec_backup sincronizado"
    done
    CURRENT=""
    case " $targets " in *" recovery "*) ;; *) recovery_notice ;; esac
}

main "$@"
