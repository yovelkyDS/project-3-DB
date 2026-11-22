#!/usr/bin/env bash
# =====================================================================
# SIG-TEC · RA-01: pruebas de la ruta "make migrate NODE=recovery" sobre el
# pg-recovery REAL (contenedor) de un LABORATORIO que contiene una copia
# recuperada ANTERIOR a 0103 (clon del pg-recovery original).
#
#   remediation/RA-01/scripts/test_recovery_lab.sh <directorio-del-laboratorio> <salida.log>
#
# Precondición: pg-recovery del laboratorio promovido, identidad san_carlos,
# sin 0103, con el duplicado de la reproducción RA-01b (dos filas con el mismo id)
# y con la contraseña de postgres del proyecto ORIGINAL (clon), distinta de la
# del laboratorio. Las pruebas ejercen esos estados antes de corregirlos.
# Escribe filas y roles de prueba SOLO en el pg-recovery del laboratorio.
# Salida: PASS|FAIL|<caso>|<detalle>; termina con código 1 si algo falla.
# =====================================================================
set -u
LAB="$(cd "${1:?directorio del laboratorio}" && pwd)"
OUT="${2:?archivo de salida}"
PROJECT="$(sed -n 's/^COMPOSE_PROJECT_NAME=//p' "$LAB/.env")"
[ -n "$PROJECT" ] && [ "$PROJECT" != "sigtec" ] || { echo "negado: se requiere un laboratorio con COMPOSE_PROJECT_NAME propio"; exit 2; }
REC="$PROJECT-pg-recovery-1"
exec > >(tee "$OUT") 2>&1
cd "$LAB" || exit 2

FAILS=0; PASSES=0
rec() { echo "$1|$2|$3"; if [ "$1" = PASS ]; then PASSES=$((PASSES + 1)); else FAILS=$((FAILS + 1)); fi; }
chk() { if [ "$2" = "$3" ]; then rec PASS "$1" "${4:-$2}"; else rec FAIL "$1" "esperado [$3] obtenido [$2] ${4:-}"; fi; }
q()   { docker exec -i -u postgres "$REC" psql -X -q -v ON_ERROR_STOP=1 -d sigtec -tA "$@"; }
err() {   # err <sql> -> NO_ERROR o SQLSTATE
    local o
    o="$(docker exec -i -u postgres "$REC" psql -X -q -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -d sigtec -tA -c "$1" 2>&1)"
    if [ $? = 0 ]; then echo NO_ERROR; else echo "$o" | sed -n 's/^ERROR:  \([0-9A-Z]\{5\}\):.*/\1/p' | head -1; fi
}
mig() {   # mig <NODE> -> deja la salida en MOUT y el código en MRC
    MOUT="$(make migrate NODE="$1" 2>&1)"; MRC=$?
    MOUT="$(echo "$MOUT" | grep -v -E '^ ?Container ')"
    echo "$MOUT" | sed 's/^/    | /'
}
S=local_san_carlos; BASE=3000000000
UNION="SELECT id, 'edificios' c FROM $S.edificios UNION ALL SELECT id,'carreteras' FROM $S.carreteras UNION ALL SELECT id,'aceras' FROM $S.aceras UNION ALL SELECT id,'parqueos' FROM $S.parqueos UNION ALL SELECT id,'zonas_verdes' FROM $S.zonas_verdes UNION ALL SELECT id,'puntos_interes' FROM $S.puntos_interes UNION ALL SELECT id,'iluminacion' FROM $S.iluminacion UNION ALL SELECT id,'accesibilidad' FROM $S.accesibilidad"
# Huella del contenido de las ocho capas (filas completas, incluida la geometría)
fingerprint() {
    q -c "SELECT md5(string_agg(h, '' ORDER BY h)) FROM (
            SELECT md5(t::text) h FROM $S.edificios t UNION ALL SELECT md5(t::text) FROM $S.carreteras t
  UNION ALL SELECT md5(t::text) FROM $S.aceras t UNION ALL SELECT md5(t::text) FROM $S.parqueos t
  UNION ALL SELECT md5(t::text) FROM $S.zonas_verdes t UNION ALL SELECT md5(t::text) FROM $S.puntos_interes t
  UNION ALL SELECT md5(t::text) FROM $S.iluminacion t UNION ALL SELECT md5(t::text) FROM $S.accesibilidad t) x"
}
backups_count() { docker exec "$REC" sh -c 'ls -1d /backups/recovery_pre_migracion/*/ 2>/dev/null | wc -l' | tr -d ' '; }
aplicada() { q -c "SELECT count(*) FROM ops.schema_migrations WHERE version = 'campus/0103_registro_identificadores'"; }

echo "laboratorio: remediation/lab (proyecto $PROJECT)  fecha: $(date '+%Y-%m-%d %H:%M:%S%z')"
echo "== 0. precondiciones"
chk pre.promovida "$(q -c "SELECT pg_is_in_recovery()")" f
chk pre.identidad "$(q -c "SELECT node_code || '/' || campus_id FROM ops.node_info")" san_carlos/3
chk pre.sin_0103 "$(aplicada)" 0
chk pre.registro_ausente "$(q -c "SELECT to_regclass('ops.identificadores_globales') IS NULL")" t
DUPS0="$(q -c "SELECT count(*) FROM (SELECT id FROM ($UNION) o GROUP BY id HAVING count(*) > 1) d")"
echo "INFO|pre.ids_repetidos|$DUPS0 (duplicado creado por la reproducción RA-01b)"
NODEINFO0="$(q -c "SELECT node_code || '|' || node_host || '|' || campus_id || '|' || local_schema FROM ops.node_info")"
B0="$(backups_count)"

echo "== 1. destinos inválidos"
mig nodo_x;   [ "$MRC" != 0 ] && echo "$MOUT" | grep -q 'destino inválido' && rec PASS f1.nodo_inexistente "make rc=$MRC" || rec FAIL f1.nodo_inexistente "rc=$MRC"
mig "recovery,nodo_x"; [ "$MRC" != 0 ] && rec PASS f1.lista_con_nodo_inexistente "make rc=$MRC" || rec FAIL f1.lista_con_nodo_inexistente "rc=$MRC"
SOUT="$(make seed NODE=recovery 2>&1)"; SRC=$?
[ "$SRC" != 0 ] && rec PASS f1.seed_no_admite_recovery "make rc=$SRC" || rec FAIL f1.seed_no_admite_recovery "rc=$SRC"

echo "== 2. credenciales rechazadas (el clon conserva la contraseña del proyecto original)"
mig recovery
PW="$(sed -n 's/^POSTGRES_PASSWORD=//p' .env)"
[ "$MRC" != 0 ] && echo "$MOUT" | grep -q 'password authentication failed' && rec PASS f2.credenciales_incorrectas "make rc=$MRC" || rec FAIL f2.credenciales_incorrectas "rc=$MRC"
echo "$MOUT" | grep -qF -- "$PW" && rec FAIL f2.sin_secretos_en_salida "la contraseña aparece" || rec PASS f2.sin_secretos_en_salida "la contraseña no aparece en la salida"
chk f2.nada_aplicado "$(aplicada)" 0

echo "== 3. paso de laboratorio: alinear la contraseña de postgres del clon con la del laboratorio"
printf "SET log_statement = 'none';\nALTER ROLE postgres PASSWORD '%s';\n" "$PW" | docker exec -i -u postgres "$REC" psql -X -q -v ON_ERROR_STOP=1 -d sigtec >/dev/null \
    && echo "INFO|lab.contraseña_alineada|hecho (sin mostrarla)" || rec FAIL lab.contraseña_alineada "no se pudo"

echo "== 4. ids repetidos en la copia: la migración se detiene sin modificar nada"
FP_DUP="$(fingerprint)"
mig recovery
[ "$MRC" != 0 ] && echo "$MOUT" | grep -q 'ids repetidos entre capas' && rec PASS i4.duplicados_detienen_migracion "make rc=$MRC" || rec FAIL i4.duplicados_detienen_migracion "rc=$MRC"
chk i4.nada_aplicado "$(aplicada)" 0
chk i4.datos_sin_cambios "$(fingerprint)" "$FP_DUP" "huella de las ocho capas idéntica"
chk i4.sin_respaldo_publicado "$(backups_count)" "$B0"

echo "== 5. resolución del conflicto (procedimiento documentado; filas de prueba de la reproducción)"
q -c "DELETE FROM $S.puntos_interes WHERE nombre = 'RA01 sesion 1'; DELETE FROM $S.iluminacion WHERE codigo = 'RA01-S2';" >/dev/null
chk i5.sin_repetidos "$(q -c "SELECT count(*) FROM (SELECT id FROM ($UNION) o GROUP BY id HAVING count(*) > 1) d")" 0
FP0="$(fingerprint)"; N0="$(q -c "SELECT count(*) FROM ($UNION) o")"
SEQ0="$(q -c "SELECT last_value FROM $S.objeto_id_seq")"

echo "== 6. pg-recovery detenida / inaccesible"
docker compose --profile recovery stop pg-recovery >/dev/null 2>&1
mig recovery
[ "$MRC" != 0 ] && echo "$MOUT" | grep -q 'no existe o no está en ejecución' && rec PASS f6.recovery_detenida "make rc=$MRC" || rec FAIL f6.recovery_detenida "rc=$MRC"
docker compose --profile recovery start pg-recovery >/dev/null 2>&1
for _ in $(seq 1 60); do [ "$(q -c 'SELECT 1' 2>/dev/null)" = 1 ] && break; sleep 1; done
chk f6.sin_cambios_tras_fallo "$(aplicada)" 0

echo "== 7. make migrate NODE=recovery aplica 0103"
mig recovery
chk f7.rc_cero "$MRC" 0
chk f7.0103_aplicada "$(aplicada)" 1
echo "$MOUT" | grep -q 'respaldo previo validado' && rec PASS f7.respaldo_previo "$(echo "$MOUT" | sed -n 's/.*respaldo previo validado: //p')" || rec FAIL f7.respaldo_previo "no se informó"
chk f7.respaldo_publicado "$(backups_count)" "$((B0 + 1))"
chk f7.datos_preservados "$(fingerprint)" "$FP0" "huella de las ocho capas idéntica ($N0 objetos)"
chk f7.identidad_conservada "$(q -c "SELECT node_code || '|' || node_host || '|' || campus_id || '|' || local_schema FROM ops.node_info")" "$NODEINFO0"
chk f7.registro_completo "$(q -c "SELECT count(*) FROM ops.identificadores_globales")" "$N0"
chk f7.verificacion_posterior "$(echo "$MOUT" | grep -c 'PASS|')" 10
echo "$MOUT" | grep -q 'FAIL|' && rec FAIL f7.sin_fail "hay FAIL" || rec PASS f7.sin_fail "0 FAIL en verificar_0103"
chk f7.secuencia_no_retrocede "$(q -c "SELECT last_value >= $SEQ0 FROM $S.objeto_id_seq")" t

echo "== 8. segunda ejecución (idempotencia)"
mig recovery
chk f8.rc_cero "$MRC" 0
echo "$MOUT" | grep -q ': aplicada ' && rec FAIL f8.nada_reaplicado "se aplicó algo" || rec PASS f8.nada_reaplicado "ninguna migración reaplicada"
chk f8.sin_nuevo_respaldo "$(backups_count)" "$((B0 + 1))" "sin pendientes no se respalda"
chk f8.datos_preservados "$(fingerprint)" "$FP0"

echo "== 9. make verify NODE=recovery"
VOUT="$(make verify NODE=recovery 2>&1)"; VRC=$?
chk v9.rc_cero "$VRC" 0
echo "$VOUT" | grep -q 'apta para entregar' && rec PASS v9.apta "pg-recovery declarada apta" || rec FAIL v9.apta "no se declaró apta"

echo "== 10. ataques F-02 sobre la recuperación migrada"
q -c "DO \$\$BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='ra01_editor') THEN CREATE ROLE ra01_editor NOLOGIN; END IF;
      IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='ra01_mant') THEN CREATE ROLE ra01_mant NOLOGIN IN ROLE sigtec_mantenimiento_id; END IF; END\$\$;
      GRANT USAGE ON SCHEMA $S TO ra01_editor, ra01_mant;
      GRANT SELECT, INSERT ON ALL TABLES IN SCHEMA $S TO ra01_editor, ra01_mant;" >/dev/null
LIBRE=$((BASE + $(q -c "SELECT nextval('$S.objeto_id_seq')")))
chk i10.editor_sin_secuencia "$(q -c "SELECT has_sequence_privilege('ra01_editor','$S.objeto_id_seq','USAGE')")" f
chk i10.editor_guc_id_explicito "$(err "SET ROLE ra01_editor; SET sigtec.permitir_id_explicito = on; INSERT INTO $S.puntos_interes(id,nombre,tipo,geom) VALUES ($LIBRE,'X','otro',ST_SetSRID(ST_MakePoint(510000,1090000),5367))")" 42501
chk i10.editor_no_autoriza "$(err "SET ROLE ra01_editor; SELECT $S.sigtec_id_autorizar_explicito($LIBRE)")" 42501
chk i10.editor_no_escribe_registro "$(err "SET ROLE ra01_editor; INSERT INTO ops.identificadores_globales(id,campus_id,capa,origen) VALUES ($LIBRE,3,'edificios','insercion')")" 42501
chk i10.editor_no_deshabilita "$(err "SET ROLE ra01_editor; ALTER TABLE $S.puntos_interes DISABLE TRIGGER USER")" 42501
chk i10.editor_no_modo_replica "$(err "SET ROLE ra01_editor; SET session_replication_role = replica")" 42501
chk i10.editor_no_se_concede_mant "$(err "SET ROLE ra01_editor; GRANT sigtec_mantenimiento_id TO ra01_editor")" 42501
LAST="$(q -c "SELECT last_value FROM $S.objeto_id_seq")"
ID="$(q -c "SET ROLE ra01_editor; INSERT INTO $S.puntos_interes(nombre,tipo,geom) VALUES ('RA01 normal','otro',ST_SetSRID(ST_MakePoint(510000,1090000),5367)) RETURNING id" | tail -1)"
chk i10.siguiente_id_automatico "$ID" "$((BASE + LAST + 1))"
chk i10.registrado "$(q -c "SELECT capa || '/' || origen FROM ops.identificadores_globales WHERE id = $ID")" puntos_interes/insercion
chk i10.id_existente_rechazado "$(err "SET ROLE ra01_mant; SET sigtec.permitir_id_explicito = on; INSERT INTO $S.iluminacion(id,codigo,potencia,estado,geom) VALUES ($ID,'X',100,'funcional',ST_SetSRID(ST_MakePoint(510000,1090000),5367))")" 23505

echo "== 11. carrera autorizada: mismo id en dos capas desde dos conexiones"
RID=$((BASE + $(q -c "SELECT nextval('$S.objeto_id_seq')")))
T="$(mktemp -d)"
( q <<SQL > "$T/s1" 2>&1
BEGIN; SET ROLE ra01_mant; SET LOCAL sigtec.permitir_id_explicito = on;
INSERT INTO $S.puntos_interes(id,nombre,tipo,geom) VALUES ($RID,'RA01 carrera 1','otro',ST_SetSRID(ST_MakePoint(510000,1090000),5367));
SELECT pg_sleep(4); COMMIT;
SQL
  echo "rc=$?" >> "$T/s1" ) &
P1=$!
sleep 1
t0=$(date +%s)
docker exec -i -u postgres "$REC" psql -X -q -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -d sigtec <<SQL > "$T/s2" 2>&1
BEGIN; SET ROLE ra01_mant; SET LOCAL sigtec.permitir_id_explicito = on;
INSERT INTO $S.iluminacion(id,codigo,potencia,estado,geom) VALUES ($RID,'RA01-C2',100,'funcional',ST_SetSRID(ST_MakePoint(510000,1090000),5367)); COMMIT;
SQL
echo "rc=$?" >> "$T/s2"; t1=$(date +%s)
wait "$P1"
WAITED=$((t1 - t0))
chk i11.primera_confirma "$(tail -1 "$T/s1")" rc=0
grep -q '23505' "$T/s2" && rec PASS i11.segunda_23505 "$(grep -m1 ERROR "$T/s2" | cut -c1-120)" || rec FAIL i11.segunda_23505 "$(cat "$T/s2")"
[ "$WAITED" -ge 2 ] && rec PASS i11.segunda_espero "esperó $WAITED s a la primera" || rec FAIL i11.segunda_espero "$WAITED s"
chk i11.una_fila "$(q -c "SELECT count(*) FROM ($UNION) o WHERE id = $RID")" 1

echo "== 12. concurrencia: 8 conexiones independientes × 25 inserciones automáticas"
N1="$(q -c "SELECT count(*) FROM ops.identificadores_globales")"
PIDS=""
for k in 1 2 3 4 5 6 7 8; do
    ( q -c "SET ROLE ra01_editor; BEGIN; INSERT INTO $S.puntos_interes(nombre,tipo,geom) SELECT 'RA01 conc $k','otro',ST_SetSRID(ST_MakePoint(510000+g,1090000),5367) FROM generate_series(1,25) g; SELECT pg_sleep(5); COMMIT;" > "$T/c$k" 2>&1; echo "rc=$?" >> "$T/c$k" ) &
    PIDS="$PIDS $!"
done
sleep 3
OVER="$(q -c "SELECT count(*) FROM pg_stat_activity WHERE query LIKE '%RA01 conc%' AND state <> 'idle' AND pid <> pg_backend_pid()")"
for p in $PIDS; do wait "$p"; done
OK8=0; for k in 1 2 3 4 5 6 7 8; do [ "$(tail -1 "$T/c$k")" = rc=0 ] && OK8=$((OK8 + 1)); done
chk i12.sesiones_superpuestas "$OVER" 8 "transacciones abiertas a la vez según pg_stat_activity"
chk i12.sesiones_confirmadas "$OK8" 8
chk i12.filas_registradas "$(( $(q -c "SELECT count(*) FROM ops.identificadores_globales") - N1 ))" 200
chk i12.ids_unicos "$(q -c "SELECT count(*) FROM (SELECT id FROM ($UNION) o GROUP BY id HAVING count(*) > 1) d")" 0
chk i12.sin_registro "$(q -c "SELECT count(*) FROM ($UNION) o LEFT JOIN ops.identificadores_globales g USING (id) WHERE g.id IS NULL OR g.capa <> o.c")" 0
rm -rf "$T"

echo "== 13. reinicio de pg-recovery"
FP1="$(fingerprint)"
docker compose --profile recovery restart pg-recovery >/dev/null 2>&1
for _ in $(seq 1 60); do [ "$(q -c 'SELECT 1' 2>/dev/null)" = 1 ] && break; sleep 1; done
chk r13.datos_tras_reinicio "$(fingerprint)" "$FP1"
chk r13.0103_tras_reinicio "$(aplicada)" 1
VOUT="$(make verify NODE=recovery 2>&1)"; VRC=$?
chk r13.verify_tras_reinicio "$VRC" 0
LAST="$(q -c "SELECT last_value FROM $S.objeto_id_seq")"
ID2="$(q -c "INSERT INTO $S.aceras(material,ancho,condicion,geom) VALUES ('concreto',2,'buena',ST_GeomFromText('LINESTRING(510000 1090000,510005 1090005)',5367)) RETURNING id" | tail -1)"
[ "$ID2" -gt "$((BASE + LAST))" ] && rec PASS r13.insercion_tras_reinicio "id=$ID2 (> último emitido)" || rec FAIL r13.insercion_tras_reinicio "id=$ID2 último=$LAST"

echo "----"
echo "RESUMEN RA-01 laboratorio: $PASSES PASS, $FAILS FAIL"
[ "$FAILS" = 0 ]
