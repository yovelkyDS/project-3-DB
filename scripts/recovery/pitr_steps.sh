#!/usr/bin/env bash
# =====================================================================
# SIG-TEC · pasos SQL de la demostración PITR (dentro de sigtec-tools)
# Los orquesta scripts/recovery/pitr_demo.sh desde el host.
#
#   pitr_steps.sh cambio-a      <nodo> <run>          -> id_a|commit_ts_a
#   pitr_steps.sh objetivo      <nodo>                -> target_utc|lsn
#   pitr_steps.sh cambio-b      <nodo> <run> <id_a>   -> id_b|commit_ts_b
#   pitr_steps.sh asegurar-wal  <nodo>                -> segmento archivado
#   pitr_steps.sh promovida     <destino>             -> espera fin de recuperación
#   pitr_steps.sh verificar     <destino> <nodo> <run> <id_a>  -> líneas PASS/FAIL
#   pitr_steps.sh marcar-recuperada <nodo> <run> <detalle>
# =====================================================================
. "${SIGTEC_HOME:-/opt/sigtec}/scripts/lib/db.sh"

cmd="${1:?}"; shift
case "$cmd" in
cambio-a)
    node="$1"; run="$2"; s="$(node_schema "$node")"
    psql_su "$node" -tA -v run="$run" -v node="$node" <<SQL
BEGIN;
WITH ref AS (SELECT geom FROM $s.puntos_interes ORDER BY (nombre LIKE 'Punto de referencia del campus%') DESC, id LIMIT 1),
a AS (
  INSERT INTO $s.puntos_interes (nombre, tipo, descripcion, geom)
  SELECT 'PITR-A ' || :'run', 'otro', 'Cambio A: confirmado ANTES del instante objetivo (debe recuperarse).', ST_Translate(geom, 15, 15)
  FROM ref RETURNING id)
INSERT INTO ops.recovery_markers (run_id, marker, detalle, lsn)
SELECT :'run', 'A', 'puntos_interes.id=' || id, pg_current_wal_lsn() FROM a;
COMMIT;
SELECT id || '|' || to_char(pg_xact_commit_timestamp(xmin) AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI:SS.US') || '+00'
FROM $s.puntos_interes WHERE nombre = 'PITR-A ' || :'run';
SQL
    ;;
objetivo)
    node="$1"
    # El instante objetivo se toma del reloj del servidor DESPUÉS de confirmar A.
    psql_su "$node" -tAc "SELECT to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI:SS.US') || '+00' || '|' || pg_current_wal_lsn()"
    ;;
cambio-b)
    node="$1"; run="$2"; id_a="$3"; s="$(node_schema "$node")"
    psql_su "$node" -tA -v run="$run" <<SQL
BEGIN;
UPDATE $s.puntos_interes SET descripcion = 'MODIFICADO POR EL CAMBIO B (no debe recuperarse).' WHERE id = $id_a;
WITH b AS (
  INSERT INTO $s.puntos_interes (nombre, tipo, descripcion, geom)
  SELECT 'PITR-B ' || :'run', 'otro', 'Cambio B: confirmado DESPUÉS del instante objetivo (no debe recuperarse).', ST_Translate(geom, 10, 0)
  FROM $s.puntos_interes WHERE id = $id_a RETURNING id)
INSERT INTO ops.recovery_markers (run_id, marker, detalle, lsn)
SELECT :'run', 'B', 'puntos_interes.id=' || id || '; además actualiza la descripción de $id_a', pg_current_wal_lsn() FROM b;
COMMIT;
SELECT id || '|' || to_char(pg_xact_commit_timestamp(xmin) AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI:SS.US') || '+00'
FROM $s.puntos_interes WHERE nombre = 'PITR-B ' || :'run';
SQL
    ;;
asegurar-wal)
    node="$1"
    seg="$(sql_value "$node" "SELECT pg_walfile_name(pg_switch_wal())")"
    for _ in $(seq 1 90); do
        last="$(sql_value "$node" "SELECT coalesce(last_archived_wal, '') FROM pg_stat_archiver")"
        if [ -n "$last" ] && [[ ! "$last" < "$seg" ]] && [ -f "$ARCHIVE_ROOT/$node/$seg" ]; then
            echo "$seg"; exit 0
        fi
        sleep 1
    done
    die "el segmento $seg no se archivó a tiempo"
    ;;
promovida)
    target="$1"
    for _ in $(seq 1 180); do
        r="$(psql_su "$target" -tAc "SELECT pg_is_in_recovery()" 2>/dev/null || true)"
        if [ "$r" = "f" ]; then
            # Ya promovida: se retiran de postgresql.auto.conf los parámetros del
            # PITR. Si quedaran, un respaldo físico de esta instancia los heredaría
            # y una recuperación posterior desde él fallaría ("recovery ended
            # before configured recovery target was reached" / "multiple recovery
            # targets specified"). No afectan a la instancia en servicio.
            for p in restore_command recovery_target_timeline recovery_target_time recovery_target_name \
                     recovery_target_lsn recovery_target_inclusive recovery_target_action; do
                psql_su "$target" -q -c "ALTER SYSTEM RESET $p" || die "no se pudo retirar $p de postgresql.auto.conf"
            done
            psql_su "$target" -q -tAc "SELECT pg_reload_conf()" >/dev/null
            echo "promovida"; exit 0
        fi
        sleep 1
    done
    die "la instancia $target no terminó la recuperación"
    ;;
verificar)
    target="$1"; node="$2"; run="$3"; id_a="$4"; s="$(node_schema "$node")"
    psql_su "$target" -tA -v run="$run" <<SQL
SELECT CASE WHEN count(*) = 1 THEN 'PASS' ELSE 'FAIL' END || '|cambio A presente|' || coalesce(string_agg(id || ' ' || nombre, ''), 'ausente')
FROM $s.puntos_interes WHERE id = $id_a AND nombre = 'PITR-A ' || :'run';
SELECT CASE WHEN count(*) = 1 THEN 'PASS' ELSE 'FAIL' END || '|A conserva su valor previo al objetivo|' || coalesce(string_agg(descripcion, ''), '-')
FROM $s.puntos_interes WHERE id = $id_a AND descripcion LIKE 'Cambio A:%';
SELECT CASE WHEN count(*) = 0 THEN 'PASS' ELSE 'FAIL' END || '|cambio B ausente (inserción)|' || count(*) || ' filas PITR-B'
FROM $s.puntos_interes WHERE nombre = 'PITR-B ' || :'run';
SELECT CASE WHEN count(*) = 0 THEN 'PASS' ELSE 'FAIL' END || '|cambio B ausente (actualización de A)|' || count(*) || ' filas modificadas por B'
FROM $s.puntos_interes WHERE id = $id_a AND descripcion LIKE 'MODIFICADO POR EL CAMBIO B%';
SELECT CASE WHEN string_agg(marker, ',' ORDER BY id) = 'A' THEN 'PASS' ELSE 'FAIL' END || '|marcas ops.recovery_markers|' || coalesce(string_agg(marker, ',' ORDER BY id), 'ninguna')
FROM ops.recovery_markers WHERE run_id = :'run';
SELECT CASE WHEN NOT pg_is_in_recovery() THEN 'PASS' ELSE 'FAIL' END || '|instancia promovida (lectura/escritura)|pg_is_in_recovery=' || pg_is_in_recovery();
SELECT 'INFO|línea de tiempo|' || timeline_id FROM pg_control_checkpoint();
SELECT 'INFO|nodo recuperado|' || node_code || ' (campus_id ' || campus_id || ')' FROM ops.node_info;
SQL
    ;;
marcar-recuperada)
    node="$1"; run="$2"; detalle="$3"
    # Las variables :'run' / :'det' solo se interpolan en SQL leído por psql
    # (stdin o archivo), no en -c (causa del hallazgo F-03).
    psql_su recovery -q -v run="$run" -v det="$detalle" >/dev/null <<'SQL'
INSERT INTO ops.recovery_markers (run_id, marker, detalle, lsn)
VALUES (:'run', 'RECUPERADA', :'det', pg_current_wal_lsn());
SQL
    [ "$(psql_su recovery -tA -v run="$run" <<'SQL'
SELECT count(*) FROM ops.recovery_markers WHERE run_id = :'run' AND marker = 'RECUPERADA';
SQL
)" = 1 ] || die "la marca RECUPERADA no quedó registrada"
    echo ok
    ;;
*) die "subcomando desconocido: $cmd" ;;
esac
