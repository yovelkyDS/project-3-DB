#!/usr/bin/env bash
# =====================================================================
# SIG-TEC · reproducción de los defectos F-01 y F-02 de la auditoría
#
#   remediation/scripts/reproduce_audit_defects.sh <directorio-del-laboratorio> <salida.log>
#
# Ejecuta, CONTRA UN LABORATORIO AISLADO (proyecto Compose propio), los mismos
# escenarios que la auditoría (audit/adversarial.py):
#   F-01  respaldo lógico y físico con la contraseña de sigtec_backup incorrecta,
#         escribiendo en un BACKUP_ROOT temporal del contenedor efímero.
#   F-02  rol de edición sin privilegios de secuencia que activa
#         sigtec.permitir_id_explicito y dos sesiones concurrentes que insertan el
#         mismo id explícito en dos capas distintas de Cartago.
# Imprime por caso: DEFECTO REPRODUCIDO / DEFECTO NO REPRODUCIDO.
# Nunca apunte este script al proyecto original: crea un rol y filas de prueba.
# =====================================================================
set -u
LAB="$(cd "${1:?directorio del laboratorio}" && pwd)"
OUT="${2:?archivo de salida}"
PROJECT="$(sed -n 's/^COMPOSE_PROJECT_NAME=//p' "$LAB/.env")"
[ -n "$PROJECT" ] && [ "$PROJECT" != "sigtec" ] || { echo "negado: el laboratorio debe tener un COMPOSE_PROJECT_NAME propio (no 'sigtec')"; exit 2; }
DC=(docker compose --project-directory "$LAB" -f "$LAB/compose.yaml")
CART="$PROJECT-pg-cartago-1"
exec > >(tee "$OUT") 2>&1

say() { printf '\n=== %s ===\n' "$*"; }
psql_c() { docker exec -i -u postgres "$CART" psql -X -v ON_ERROR_STOP=1 -d sigtec "$@"; }

echo "laboratorio: remediation/lab  (proyecto $PROJECT)  fecha: $(date '+%Y-%m-%d %H:%M:%S%z')"

# ------------------------------------------------------------------ F-01
for kind in logical physical; do
    say "F-01 $kind: contraseña de sigtec_backup incorrecta (nodo central)"
    out="$("${DC[@]}" --profile tools run --rm -T \
        -e SIGTEC_BACKUP_PASSWORD=remediacion-clave-invalida \
        -e BACKUP_ROOT=/tmp/neg-$kind sigtec-tools -c "
          scripts/backup/${kind}_backup.sh central; rc=\$?
          echo \"rc_script=\$rc\"
          echo \"directorios_publicados=\$(ls -1d /tmp/neg-$kind/$kind/central/*/ 2>/dev/null | wc -l)\"
          echo \"bitacora:\"; cut -f2-5 /tmp/neg-$kind/backup_log.tsv 2>/dev/null | tail -n +2" 2>&1 | grep -v -E '^ ?Container ')"
    echo "$out"
    rc="$(echo "$out" | sed -n 's/^rc_script=//p')"
    pub="$(echo "$out" | sed -n 's/^directorios_publicados=//p')"
    if [ "$rc" = 0 ] || echo "$out" | grep -q "  OK central" || [ "${pub:-0}" != 0 ]; then
        echo "RESULTADO F-01 $kind: DEFECTO REPRODUCIDO (rc=$rc, publicados=$pub)"
    else
        echo "RESULTADO F-01 $kind: DEFECTO NO REPRODUCIDO (rc=$rc, publicados=$pub)"
    fi
done

# ------------------------------------------------------------------ F-02
say "F-02 preparación: rol remed_editor sin privilegios de secuencia; consecutivos emitidos sin usar"
psql_c <<'SQL'
DO $$BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='remed_editor') THEN CREATE ROLE remed_editor NOSUPERUSER NOLOGIN; END IF; END$$;
GRANT USAGE ON SCHEMA local_cartago TO remed_editor;
GRANT SELECT, INSERT ON local_cartago.puntos_interes, local_cartago.iluminacion TO remed_editor;
-- Simula consecutivos emitidos y no usados (p. ej. inserciones revertidas)
SELECT nextval('local_cartago.objeto_id_seq') FROM generate_series(1,3);
SELECT has_sequence_privilege('remed_editor','local_cartago.objeto_id_seq','USAGE') AS editor_usa_secuencia,
       pg_sequence_last_value('local_cartago.objeto_id_seq') AS ultimo;
SQL
LAST="$(psql_c -tA -c "SELECT pg_sequence_last_value('local_cartago.objeto_id_seq')")"
ID1=$((1000000000 + LAST - 2)); ID2=$((1000000000 + LAST - 1))

say "F-02a: remed_editor + SET LOCAL sigtec.permitir_id_explicito=on inserta id explícito $ID1"
if psql_c <<SQL
BEGIN;
SET ROLE remed_editor;
SET LOCAL sigtec.permitir_id_explicito = on;
INSERT INTO local_cartago.puntos_interes(id,nombre,tipo,geom)
VALUES ($ID1,'REMED manual','otro',ST_SetSRID(ST_MakePoint(510000,1090000),5367)) RETURNING id;
COMMIT;
SQL
then echo "RESULTADO F-02a: DEFECTO REPRODUCIDO (un rol sin privilegios insertó un id explícito)"
else echo "RESULTADO F-02a: DEFECTO NO REPRODUCIDO (rechazado)"; fi

say "F-02b: dos sesiones concurrentes, mismo id $ID2 en puntos_interes e iluminacion (remed_editor)"
( psql_c <<SQL
BEGIN; SET ROLE remed_editor; SET LOCAL sigtec.permitir_id_explicito = on;
INSERT INTO local_cartago.puntos_interes(id,nombre,tipo,geom)
VALUES ($ID2,'REMED concurrente','otro',ST_SetSRID(ST_MakePoint(510000,1090000),5367));
SELECT pg_sleep(4); COMMIT;
SQL
echo "sesion1_rc=$?" ) &
S1=$!
sleep 1
psql_c <<SQL
BEGIN; SET ROLE remed_editor; SET LOCAL sigtec.permitir_id_explicito = on;
INSERT INTO local_cartago.iluminacion(id,codigo,potencia,estado,geom)
VALUES ($ID2,'REMED-RACE',100,'funcional',ST_SetSRID(ST_MakePoint(510000,1090000),5367)); COMMIT;
SQL
echo "sesion2_rc=$?"
wait "$S1"

say "F-02 resultado: ids repetidos entre capas de Cartago"
DUPS="$(psql_c -tA -c "SELECT id || ' x' || count(*) FROM (
    SELECT id FROM local_cartago.edificios UNION ALL SELECT id FROM local_cartago.carreteras
    UNION ALL SELECT id FROM local_cartago.aceras UNION ALL SELECT id FROM local_cartago.parqueos
    UNION ALL SELECT id FROM local_cartago.zonas_verdes UNION ALL SELECT id FROM local_cartago.puntos_interes
    UNION ALL SELECT id FROM local_cartago.iluminacion UNION ALL SELECT id FROM local_cartago.accesibilidad) t
  GROUP BY id HAVING count(*) > 1")"
echo "duplicados: ${DUPS:-ninguno}"
if [ -n "$DUPS" ]; then echo "RESULTADO F-02b: DEFECTO REPRODUCIDO (id confirmado en dos capas)"
else echo "RESULTADO F-02b: DEFECTO NO REPRODUCIDO"; fi

# ------------------------------------------------------------------ F-02c
# Solo si existe el rol de mantenimiento (código corregido): la misma carrera
# con un rol AUTORIZADO. Debe confirmarse a lo sumo una de las dos inserciones.
if [ "$(psql_c -tA -c "SELECT count(*) FROM pg_roles WHERE rolname='sigtec_mantenimiento_id'")" = 1 ]; then
    say "F-02c: carrera con rol autorizado (miembro de sigtec_mantenimiento_id)"
    psql_c -q <<'SQL'
DO $$BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='remed_mant') THEN CREATE ROLE remed_mant NOLOGIN IN ROLE sigtec_mantenimiento_id; END IF; END$$;
SELECT nextval('local_cartago.objeto_id_seq');
SQL
    ID3=$((1000000000 + $(psql_c -tA -c "SELECT pg_sequence_last_value('local_cartago.objeto_id_seq')")))
    ( psql_c <<SQL
BEGIN; SET ROLE remed_mant; SET LOCAL sigtec.permitir_id_explicito = on;
INSERT INTO local_cartago.puntos_interes(id,nombre,tipo,geom)
VALUES ($ID3,'REMED mant 1','otro',ST_SetSRID(ST_MakePoint(510000,1090000),5367));
SELECT pg_sleep(4); COMMIT;
SQL
    echo "sesion1_rc=$?" ) &
    S1=$!
    sleep 1
    t0=$(date +%s)
    psql_c <<SQL
BEGIN; SET ROLE remed_mant; SET LOCAL sigtec.permitir_id_explicito = on;
INSERT INTO local_cartago.iluminacion(id,codigo,potencia,estado,geom)
VALUES ($ID3,'REMED-MANT-2',100,'funcional',ST_SetSRID(ST_MakePoint(510000,1090000),5367)); COMMIT;
SQL
    echo "sesion2_rc=$? (esperó $(( $(date +%s) - t0 )) s a la sesión 1)"
    wait "$S1"
    N="$(psql_c -tA -c "SELECT (SELECT count(*) FROM local_cartago.puntos_interes WHERE id=$ID3) + (SELECT count(*) FROM local_cartago.iluminacion WHERE id=$ID3)")"
    echo "filas confirmadas con id $ID3: $N"
    [ "$N" = 1 ] && echo "RESULTADO F-02c: DEFECTO NO REPRODUCIDO (una sola inserción confirmada)" \
                 || echo "RESULTADO F-02c: DEFECTO REPRODUCIDO ($N filas)"
fi
