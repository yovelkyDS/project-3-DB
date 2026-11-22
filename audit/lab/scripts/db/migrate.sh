#!/usr/bin/env bash
# =====================================================================
# SIG-TEC · aplica migraciones versionadas a los nodos (idempotente)
#   uso (en sigtec-tools):  scripts/db/migrate.sh [all|campus|<nodo> ...]
#
# * sql/bootstrap/*          se ejecuta siempre (IF NOT EXISTS)
# * sql/migrations/common/*  en los seis nodos
# * sql/migrations/campus/*  solo en los cinco campus
# Cada migración corre en UNA transacción y queda registrada con su SHA-256
# en ops.schema_migrations; una migración registrada no se vuelve a aplicar.
# Al final se sincroniza la identidad del nodo (ops.node_info) y el rol de respaldo.
# =====================================================================
. "${SIGTEC_HOME:-/opt/sigtec}/scripts/lib/db.sh"

SQL="$SIGTEC_HOME/sql"

apply_migration() {
    local node="$1" file="$2" version checksum applied
    version="${file#"$SQL/migrations/"}"; version="${version%.sql}"
    # El checksum incluye los archivos incluidos con \ir (p. ej. sql/schema/capas_locales.sql)
    checksum="$( { cat "$file"
                   sed -n 's/^\\ir[[:space:]]\{1,\}//p' "$file" | while read -r inc; do
                       cat "$(dirname "$file")/$inc"; done
                 } | sha256sum | cut -d' ' -f1)"
    applied="$(sql_value "$node" "SELECT checksum FROM ops.schema_migrations WHERE version = '$version'")"
    if [ -n "$applied" ]; then
        if [ "$applied" != "$checksum" ]; then
            log "  AVISO $node: $version ya aplicada pero el archivo cambió (no se reaplica; cree una migración nueva)"
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
    psql_su "$node" --single-transaction "${vars[@]}" \
        -f "$file" \
        -c "INSERT INTO ops.schema_migrations(version, checksum) VALUES ('$version', '$checksum')"
    log "  $node: aplicada $version"
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

main() {
    local node f
    for node in $(nodes_expand "${@:-all}"); do
        log "migrando $node ($(node_host "$node"))"
        wait_node "$node" 120
        psql_su "$node" -f "$SQL/bootstrap/00_ops_migraciones.sql" >/dev/null
        for f in "$SQL"/migrations/common/*.sql; do apply_migration "$node" "$f"; done
        if node_is_campus "$node"; then
            for f in "$SQL"/migrations/campus/*.sql; do apply_migration "$node" "$f"; done
        fi
        sync_node_info "$node"
        psql_su "$node" -f "$SQL/roles/sigtec_backup.sql" >/dev/null
        log "  $node: $(sql_value "$node" "SELECT count(*) FROM ops.schema_migrations") migraciones registradas; rol sigtec_backup sincronizado"
    done
}

main "$@"
