#!/usr/bin/env bash
# =====================================================================
# SIG-TEC · reproducción de RA-01 contra el pg-recovery de un LABORATORIO
#
#   remediation/RA-01/scripts/reproduce_ra01.sh <directorio-del-laboratorio> <salida.log>
#
#   RA-01a  "make migrate NODE=recovery": código de salida y si 0103 quedó aplicada.
#   RA-01b  F-02 sobre la instancia recuperada: un rol de edición sin privilegios
#           de secuencia activa sigtec.permitir_id_explicito y dos conexiones
#           independientes insertan el MISMO id en puntos_interes e iluminacion.
# Imprime por caso: DEFECTO REPRODUCIDO / DEFECTO NO REPRODUCIDO.
# Crea un rol y filas de prueba en pg-recovery: nunca lo apunte al proyecto original.
# =====================================================================
set -u
LAB="$(cd "${1:?directorio del laboratorio}" && pwd)"
OUT="${2:?archivo de salida}"
PROJECT="$(sed -n 's/^COMPOSE_PROJECT_NAME=//p' "$LAB/.env")"
[ -n "$PROJECT" ] && [ "$PROJECT" != "sigtec" ] || { echo "negado: el laboratorio debe tener un COMPOSE_PROJECT_NAME propio (no 'sigtec')"; exit 2; }
REC="$PROJECT-pg-recovery-1"
exec > >(tee "$OUT") 2>&1
say() { printf '\n=== %s ===\n' "$*"; }
q() { docker exec -i -u postgres "$REC" psql -X -v ON_ERROR_STOP=1 -d sigtec "$@"; }

echo "laboratorio: remediation/lab  (proyecto $PROJECT)  fecha: $(date '+%Y-%m-%d %H:%M:%S%z')"
say "estado de pg-recovery"
q -tA -c "SELECT 'nodo=' || node_code || ' campus_id=' || campus_id FROM ops.node_info" \
      -c "SELECT 'en_recuperacion=' || pg_is_in_recovery()" \
      -c "SELECT 'migraciones=' || string_agg(version, ',' ORDER BY version) FROM ops.schema_migrations" \
      -c "SELECT 'registro_0103=' || (to_regclass('ops.identificadores_globales') IS NOT NULL)"
S="$(q -tA -c "SELECT local_schema FROM ops.node_info")"
CID="$(q -tA -c "SELECT campus_id FROM ops.node_info")"

say "RA-01a: make migrate NODE=recovery"
( cd "$LAB" && make migrate NODE=recovery ) 2>&1 | grep -v -E '^ ?Container '
RC=${PIPESTATUS[0]}
APLICADA="$(q -tA -c "SELECT count(*) FROM ops.schema_migrations WHERE version = 'campus/0103_registro_identificadores'")"
echo "MAKE_MIGRATE_RECOVERY_RC=$RC  0103_aplicada=$APLICADA"
if [ "$RC" = 0 ] && [ "$APLICADA" != 1 ]; then
    echo "RESULTADO RA-01a: DEFECTO REPRODUCIDO (código 0 sin aplicar 0103)"
elif [ "$RC" = 0 ] && [ "$APLICADA" = 1 ]; then
    echo "RESULTADO RA-01a: DEFECTO NO REPRODUCIDO (código 0 y 0103 aplicada)"
else
    echo "RESULTADO RA-01a: DEFECTO NO REPRODUCIDO (código $RC: el fallo se informa)"
fi

say "RA-01b: editor sin privilegios + GUC, mismo id en dos capas desde dos conexiones"
q -q <<SQL
DO \$\$BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='ra01_editor') THEN CREATE ROLE ra01_editor NOLOGIN; END IF; END\$\$;
GRANT USAGE ON SCHEMA $S TO ra01_editor;
GRANT SELECT, INSERT ON $S.puntos_interes, $S.iluminacion TO ra01_editor;
SQL
echo "editor_usa_secuencia=$(q -tA -c "SELECT has_sequence_privilege('ra01_editor','$S.objeto_id_seq','USAGE')")"
ID=$((CID * 1000000000 + $(q -tA -c "SELECT nextval('$S.objeto_id_seq')")))
echo "id elegido (emitido por la secuencia y sin usar): $ID"
TMPD="$(mktemp -d)"
( q <<SQL > "$TMPD/s1" 2>&1
BEGIN; SET ROLE ra01_editor; SET LOCAL sigtec.permitir_id_explicito = on;
INSERT INTO $S.puntos_interes(id,nombre,tipo,geom) VALUES ($ID,'RA01 sesion 1','otro',ST_SetSRID(ST_MakePoint(510000,1090000),5367));
SELECT pg_sleep(4); COMMIT;
SQL
  echo "rc=$?" >> "$TMPD/s1" ) &
S1=$!
sleep 1
t0=$(date +%s)
q <<SQL > "$TMPD/s2" 2>&1
BEGIN; SET ROLE ra01_editor; SET LOCAL sigtec.permitir_id_explicito = on;
INSERT INTO $S.iluminacion(id,codigo,potencia,estado,geom) VALUES ($ID,'RA01-S2',100,'funcional',ST_SetSRID(ST_MakePoint(510000,1090000),5367)); COMMIT;
SQL
echo "rc=$?" >> "$TMPD/s2"
t1=$(date +%s)
wait "$S1"
echo "sesión 1:"; sed 's/^/  /' "$TMPD/s1"
echo "sesión 2 (duró $((t1 - t0)) s):"; sed 's/^/  /' "$TMPD/s2"
N="$(q -tA -c "SELECT (SELECT count(*) FROM $S.puntos_interes WHERE id=$ID) + (SELECT count(*) FROM $S.iluminacion WHERE id=$ID)")"
echo "filas confirmadas con id $ID: $N"
rm -rf "$TMPD"
if [ "$N" -ge 2 ]; then echo "RESULTADO RA-01b: DEFECTO REPRODUCIDO ($N filas con el mismo id)"
else echo "RESULTADO RA-01b: DEFECTO NO REPRODUCIDO ($N fila(s))"; fi
