#!/usr/bin/env bash
# =====================================================================
# SIG-TEC · regresión RA-01: un nodo recuperado ANTERIOR a 0103 se actualiza
# con "migrate.sh recovery" (= make migrate NODE=recovery) y los fallos se
# informan con código distinto de cero. Todo en clústeres TEMPORALES dentro de
# sigtec-tools (direcciones 127.0.0.x); ningún nodo en servicio se toca.
#
#   1. origen San Carlos con 0101–0102 + datos, archivado WAL, copia base;
#      cambio A; instante objetivo; DESPUÉS: 0103 aplicada al origen y cambio B;
#   2. PITR real (restore_command + recovery_target_time + promote) en otro
#      clúster: A presente, B ausente, esquema anterior a 0103 (vulnerable a F-02);
#   3. negativos con el script real y su código: destino desconocido (2),
#      servidor inaccesible (3), contraseña incorrecta (3),
#      instancia no promovida (4), identidad inconsistente (4), ids repetidos (5),
#      (el caso "pg-recovery no existe" se prueba en el laboratorio: aquí el nombre
#      nunca se deja sin redirigir para no alcanzar un nodo real por el DNS de Docker)
#      error SQL (1), error de permisos (1) — sin cambios parciales;
#   4. migración correcta: respaldo previo validado, 0103 aplicada, datos e
#      identidad preservados, verificación completa, idempotencia, verify apta;
#   5. integridad: ataques del editor, carrera autorizada, 8 conexiones
#      concurrentes, siguiente id, reinicio.
# Salida PASS|FAIL|<caso>|<detalle>.
# =====================================================================
. "${SIGTEC_HOME:-/opt/sigtec}/scripts/lib/db.sh"
set +e

RESULTS="$(mktemp)"
rec() { echo "$1|$2|$3" | tee -a "$RESULTS"; }
chk() { if [ "$2" = "$3" ]; then rec PASS "$1" "${4:-$2}"; else rec FAIL "$1" "esperado [$3] obtenido [$2] ${4:-}"; fi; }
cp /etc/hosts /tmp/sigtec-hosts.rec
TMP="$(mktemp -d /tmp/sigtec-rec.XXXXXX)"; chown postgres:postgres "$TMP"; chmod 0755 "$TMP"
export BACKUP_ROOT="$TMP/backups"; mkdir -p "$BACKUP_ROOT"
SRC_IP=127.0.0.2; REC_IP=127.0.0.3; STBY_IP=127.0.0.4
S=local_san_carlos; BASE=3000000000
cleanup() {
    local d
    for d in src rec stby; do [ -f "$TMP/$d/postmaster.pid" ] && gosu postgres pg_ctl -D "$TMP/$d" -m immediate -w stop >/dev/null 2>&1; done
    cat /tmp/sigtec-hosts.rec > /etc/hosts; rm -rf "$TMP"
}
trap cleanup EXIT
set_host() {   # set_host <nombre> <ip|-> : redirige un nombre de servicio
    grep -v -E "[[:space:]]$1\$" /etc/hosts > "$TMP/hosts"; cat "$TMP/hosts" > /etc/hosts
    [ "$2" = - ] || echo "$2 $1" >> /etc/hosts
}
qa() { PGPASSWORD="$POSTGRES_PASSWORD" psql -X -q -v ON_ERROR_STOP=1 -h "$1" -p 5432 -U postgres -d "${DB:-sigtec}" -tA "${@:2}"; }
qr() { qa "$REC_IP" "$@"; }
err() {
    local o
    o="$(PGPASSWORD="$POSTGRES_PASSWORD" psql -X -q -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -h "$REC_IP" -p 5432 -U postgres -d sigtec -tA -c "$1" 2>&1)"
    if [ $? = 0 ]; then echo NO_ERROR; else echo "$o" | sed -n 's/^ERROR:  \([0-9A-Z]\{5\}\):.*/\1/p' | head -1; fi
}
start_pg() {   # start_pg <dir> <ip> <cluster_name> [opciones]   (socket propio por clúster)
    install -d -o postgres -g postgres "$TMP/$1.sock"
    gosu postgres pg_ctl -D "$TMP/$1" -l "$TMP/$1.log" -w -t 120 -o \
        "-c listen_addresses=$2 -c port=5432 -c unix_socket_directories=$TMP/$1.sock -c cluster_name=$3 ${4:-}" start >/dev/null
}
guard() {   # el nombre debe resolver al clúster temporal esperado
    local cn
    cn="$(qa "$(getent hosts "$1" | awk '{print $1}')" -d postgres -c "SHOW cluster_name" 2>/dev/null)"
    [ "$cn" = "$2" ] || { echo "ABORTO: $1 no apunta al clúster temporal $2 (cluster_name='$cn')"; exit 2; }
}
mig() { MOUT="$(env SIGTEC_HOME="${HOME_MIG:-$SIGTEC_HOME}" bash "${HOME_MIG:-$SIGTEC_HOME}/scripts/db/migrate.sh" "$@" 2>&1)"; MRC=$?; }
fingerprint() {
    qr -c "SELECT md5(string_agg(h, '' ORDER BY h)) FROM (
            SELECT md5(t::text) h FROM $S.edificios t UNION ALL SELECT md5(t::text) FROM $S.carreteras t
  UNION ALL SELECT md5(t::text) FROM $S.aceras t UNION ALL SELECT md5(t::text) FROM $S.parqueos t
  UNION ALL SELECT md5(t::text) FROM $S.zonas_verdes t UNION ALL SELECT md5(t::text) FROM $S.puntos_interes t
  UNION ALL SELECT md5(t::text) FROM $S.iluminacion t UNION ALL SELECT md5(t::text) FROM $S.accesibilidad t) x"
}
UNION="SELECT id, 'edificios' c FROM $S.edificios UNION ALL SELECT id,'carreteras' FROM $S.carreteras UNION ALL SELECT id,'aceras' FROM $S.aceras UNION ALL SELECT id,'parqueos' FROM $S.parqueos UNION ALL SELECT id,'zonas_verdes' FROM $S.zonas_verdes UNION ALL SELECT id,'puntos_interes' FROM $S.puntos_interes UNION ALL SELECT id,'iluminacion' FROM $S.iluminacion UNION ALL SELECT id,'accesibilidad' FROM $S.accesibilidad"
aplicada() { qr -c "SELECT count(*) FROM ops.schema_migrations WHERE version = 'campus/0103_registro_identificadores'"; }
nbackups() { ls -1d "$BACKUP_ROOT"/recovery_pre_migracion/*/ 2>/dev/null | wc -l | tr -d ' '; }
pt() { echo "ST_SetSRID(ST_MakePoint(${1:-510000}, 1090000), 5367)"; }

# ---------------------------------------------------------------- 1. origen
# Los nombres de servicio que usan los scripts reales SIEMPRE apuntan a un
# clúster temporal o a una dirección sin servidor (127.0.0.9), nunca a un nodo
# en servicio de la red Docker (el DNS de Docker los resolvería si se quitaran).
set_host pg-recovery 127.0.0.9; set_host pg-san-carlos 127.0.0.9
printf '%s\n' "$POSTGRES_PASSWORD" > "$TMP/pw"; chown postgres "$TMP/pw"; chmod 600 "$TMP/pw"
gosu postgres initdb -D "$TMP/src" -U postgres --auth=scram-sha-256 --pwfile="$TMP/pw" --data-checksums >/dev/null
rm -f "$TMP/pw"
cat > "$TMP/src/pg_hba.conf" <<'HBA'
local all all scram-sha-256
host all all 127.0.0.0/8 scram-sha-256
host replication all 127.0.0.0/8 scram-sha-256
HBA
install -d -o postgres -g postgres "$TMP/archive"
start_pg src "$SRC_IP" sigtec-prueba-rec-origen "-c wal_level=logical -c archive_mode=on -c archive_command='cp %p $TMP/archive/%f.tmp && mv $TMP/archive/%f.tmp $TMP/archive/%f' -c max_connections=40"
set_host pg-san-carlos "$SRC_IP"; guard pg-san-carlos sigtec-prueba-rec-origen
qa "$SRC_IP" -d postgres -c "CREATE DATABASE sigtec" >/dev/null
H0102="$TMP/home0102"; mkdir -p "$H0102"; cp -a "$SIGTEC_HOME/scripts" "$SIGTEC_HOME/sql" "$H0102/"
rm -f "$H0102"/sql/migrations/campus/0103_*.sql
SIGTEC_HOME="$H0102" bash "$H0102/scripts/db/migrate.sh" san_carlos > "$TMP/m0.log" 2>&1 && \
SIGTEC_HOME="$H0102" bash "$H0102/scripts/db/seed.sh" san_carlos >> "$TMP/m0.log" 2>&1
chk pitr.origen_sin_0103 "$(qa "$SRC_IP" -c "SELECT string_agg(version, ',' ORDER BY version) FROM ops.schema_migrations WHERE version LIKE 'campus/%'")" "campus/0101_capas_locales,campus/0102_identificadores"
PGPASSWORD="$POSTGRES_PASSWORD" pg_basebackup -h "$SRC_IP" -U postgres -w -D "$TMP/base" -X stream --checkpoint=fast >/dev/null 2>&1
chk pitr.copia_base "$?" 0
ID_A="$(qa "$SRC_IP" -c "INSERT INTO $S.puntos_interes(nombre,tipo,geom) VALUES ('REC-A','otro',$(pt)) RETURNING id" | tail -1)"
sleep 1
TARGET="$(qa "$SRC_IP" -c "SELECT clock_timestamp()")"
sleep 1
bash "$SIGTEC_HOME/scripts/db/migrate.sh" san_carlos > "$TMP/m1.log" 2>&1
chk pitr.origen_migrado_despues_del_objetivo "$(qa "$SRC_IP" -c "SELECT count(*) FROM ops.schema_migrations WHERE version = 'campus/0103_registro_identificadores'")" 1
ID_B="$(qa "$SRC_IP" -c "INSERT INTO $S.puntos_interes(nombre,tipo,geom) VALUES ('REC-B','otro',$(pt)) RETURNING id" | tail -1)"
SEG="$(qa "$SRC_IP" -c "SELECT pg_walfile_name(pg_switch_wal())")"
for _ in $(seq 1 60); do
    last="$(qa "$SRC_IP" -c "SELECT coalesce(last_archived_wal, '') FROM pg_stat_archiver")"
    [ -n "$last" ] && [[ ! "$last" < "$SEG" ]] && [ -f "$TMP/archive/$SEG" ] && break; sleep 1
done
chk pitr.wal_archivado "$([ -f "$TMP/archive/$SEG" ] && echo si)" si "$SEG"
gosu postgres pg_ctl -D "$TMP/src" -m immediate -w stop >/dev/null 2>&1   # falla simulada
set_host pg-san-carlos 127.0.0.9

# ---------------------------------------------------------------- 2. PITR
cp -a "$TMP/base" "$TMP/rec"; cp -a "$TMP/base" "$TMP/stby"; chown -R postgres:postgres "$TMP/rec" "$TMP/stby"
cat >> "$TMP/rec/postgresql.auto.conf" <<CONF
restore_command = 'cp $TMP/archive/%f "%p"'
recovery_target_time = '$TARGET'
recovery_target_action = 'promote'
CONF
touch "$TMP/rec/recovery.signal"
printf 'source_node=san_carlos\nbase_backup=%s\n' "$TMP/base" > "$TMP/rec/SIGTEC_RECOVERY_INFO"; chown postgres "$TMP/rec"/*.signal "$TMP/rec/SIGTEC_RECOVERY_INFO"
start_pg rec "$REC_IP" sigtec-prueba-rec-recuperada
for _ in $(seq 1 90); do [ "$(qr -c 'SELECT pg_is_in_recovery()' 2>/dev/null)" = f ] && break; sleep 1; done
chk pitr.promovida "$(qr -c 'SELECT pg_is_in_recovery()')" f
[ "$(qr -c 'SELECT pg_is_in_recovery()' 2>/dev/null)" = f ] || { echo "registro del clúster recuperado:"; tail -25 "$TMP/rec.log"; }
chk pitr.cambio_a_presente "$(qr -c "SELECT count(*) FROM $S.puntos_interes WHERE id = $ID_A")" 1
chk pitr.cambio_b_ausente "$(qr -c "SELECT count(*) FROM $S.puntos_interes WHERE id = $ID_B")" 0
chk pitr.esquema_anterior_a_0103 "$(aplicada):$(qr -c "SELECT to_regclass('ops.identificadores_globales') IS NULL")" "0:t" "el instante restaurado es anterior a 0103"
chk pitr.identidad_restaurada "$(qr -c "SELECT node_code || '/' || campus_id FROM ops.node_info")" san_carlos/3
set_host pg-recovery "$REC_IP"; guard pg-recovery sigtec-prueba-rec-recuperada

# La copia recuperada sin migrar es vulnerable a F-02 (estado de RA-01)
qr -c "CREATE ROLE t_editor NOLOGIN; GRANT USAGE ON SCHEMA $S TO t_editor; GRANT SELECT, INSERT ON ALL TABLES IN SCHEMA $S TO t_editor;" >/dev/null
DUP=$((BASE + $(qr -c "SELECT nextval('$S.objeto_id_seq')")))
# dos conexiones con transacciones superpuestas (las comprobaciones EXISTS de 0102 no ven la otra)
printf "BEGIN; SET LOCAL ROLE t_editor; SET LOCAL sigtec.permitir_id_explicito = on;\nINSERT INTO $S.puntos_interes(id,nombre,tipo,geom) VALUES ($DUP,'REC-DUP1','otro',$(pt));\nSELECT pg_sleep(3); COMMIT;\n" > "$TMP/d1.sql"
printf "BEGIN; SET LOCAL ROLE t_editor; SET LOCAL sigtec.permitir_id_explicito = on;\nINSERT INTO $S.iluminacion(id,codigo,potencia,estado,geom) VALUES ($DUP,'REC-DUP2',100,'funcional',$(pt));\nCOMMIT;\n" > "$TMP/d2.sql"
( qr -f "$TMP/d1.sql" > "$TMP/d1.out" 2>&1 ) &
P1=$!; sleep 1
qr -f "$TMP/d2.sql" > "$TMP/d2.out" 2>&1
wait "$P1"
chk ra01.sin_0103_admite_duplicado "$(qr -c "SELECT count(*) FROM ($UNION) o WHERE id = $DUP")" 2 "antes de migrar, dos conexiones del editor confirmaron $DUP en dos capas (RA-01 reproducido)"

# ---------------------------------------------------------------- 3. negativos
FP_DUP="$(fingerprint)"
mig nodo_x;                         chk neg.destino_desconocido "$MRC" 2 "$(echo "$MOUT" | grep -m1 -o 'destino inválido[^.]*')"
mig "recovery,nodo_x";              chk neg.lista_con_desconocido "$MRC" 2
SIGTEC_HOME="$H0102" bash "$H0102/scripts/db/seed.sh" recovery >/dev/null 2>&1; r=$?
[ "$r" != 0 ] && rec PASS neg.seed_rechaza_recovery "rc=$r" || rec FAIL neg.seed_rechaza_recovery "rc=$r"
set_host pg-recovery 127.0.0.9;     SIGTEC_WAIT_TIMEOUT=3 mig recovery; chk neg.servidor_inaccesible "$MRC" 3 "$(echo "$MOUT" | grep -m1 -o 'no aceptó conexiones.*')"
set_host pg-recovery "$REC_IP"
POSTGRES_PASSWORD="clave-incorrecta-ra01" mig recovery
chk neg.contrasena_incorrecta "$MRC" 3 "$(echo "$MOUT" | grep -m1 -o 'password authentication failed[^\"]*')"
echo "$MOUT" | grep -qF -- "$POSTGRES_PASSWORD" && rec FAIL neg.sin_secretos "la contraseña aparece en la salida" || rec PASS neg.sin_secretos "la contraseña no aparece en la salida"
# no promovida: la misma copia como standby (solo lectura, en recuperación)
touch "$TMP/stby/standby.signal"; chown postgres "$TMP/stby/standby.signal"
echo "restore_command = 'cp $TMP/archive/%f \"%p\"'" >> "$TMP/stby/postgresql.auto.conf"
start_pg stby "$STBY_IP" sigtec-prueba-rec-standby
set_host pg-recovery "$STBY_IP"
[ "$(qa "$STBY_IP" -d postgres -c 'SHOW cluster_name' 2>/dev/null)" = sigtec-prueba-rec-standby ] || { echo "registro del standby:"; tail -20 "$TMP/stby.log"; }
guard pg-recovery sigtec-prueba-rec-standby
mig recovery; chk neg.no_promovida "$MRC" 4 "$(echo "$MOUT" | grep -m1 -o 'sigue en recuperación[^.]*')"
gosu postgres pg_ctl -D "$TMP/stby" -m fast -w stop >/dev/null 2>&1
set_host pg-recovery "$REC_IP"; guard pg-recovery sigtec-prueba-rec-recuperada
# identidad inconsistente
printf 'source_node=limon\n' > "$TMP/rec/SIGTEC_RECOVERY_INFO"
mig recovery; chk neg.identidad_inconsistente "$MRC" 4 "$(echo "$MOUT" | grep -m1 -o 'identidad inconsistente[^)]*)')"
printf 'source_node=san_carlos\nbase_backup=%s\n' "$TMP/base" > "$TMP/rec/SIGTEC_RECOVERY_INFO"
# ids repetidos
mig recovery; chk neg.ids_repetidos "$MRC" 5 "$(echo "$MOUT" | grep -m1 -o 'ids repetidos entre capas: [0-9]* en [a-z_+]*')"
chk neg.sin_cambios "$(aplicada):$(qr -c "SELECT to_regclass('ops.identificadores_globales') IS NULL"):$(fingerprint)" "0:t:$FP_DUP" "0103, registro y datos sin cambios"
chk neg.sin_respaldo_publicado "$(nbackups)" 0
# resolución del conflicto de prueba (procedimiento documentado)
qr -c "DELETE FROM $S.iluminacion WHERE codigo = 'REC-DUP2'; DELETE FROM $S.puntos_interes WHERE nombre = 'REC-DUP1'" >/dev/null

# ---------------------------------------------------------------- 4. migración
FP0="$(fingerprint)"; N0="$(qr -c "SELECT count(*) FROM ($UNION) o")"
NI0="$(qr -c "SELECT node_code || '|' || node_host || '|' || campus_id || '|' || local_schema FROM ops.node_info")"
mig recovery
chk mig.rc_cero "$MRC" 0
chk mig.0103_aplicada "$(aplicada)" 1
chk mig.respaldo_previo_publicado "$(nbackups)" 1
B="$(ls -1d "$BACKUP_ROOT"/recovery_pre_migracion/*/ | head -1)"
pg_restore --list "$B/sigtec.dump" >/dev/null 2>&1; chk mig.respaldo_previo_legible "$?" 0
grep -q 'migraciones_registradas=.*0102' "$B/manifest.txt" && ! grep -q 'migraciones_registradas=.*0103' "$B/manifest.txt" \
    && rec PASS mig.respaldo_previo_anterior_a_0103 "manifest: $(grep migraciones "$B/manifest.txt")" || rec FAIL mig.respaldo_previo_anterior_a_0103 "$(cat "$B/manifest.txt")"
chk mig.datos_preservados "$(fingerprint)" "$FP0" "huella idéntica, $N0 objetos"
chk mig.identidad_conservada "$(qr -c "SELECT node_code || '|' || node_host || '|' || campus_id || '|' || local_schema FROM ops.node_info")" "$NI0"
chk mig.registro_completo "$(qr -c "SELECT count(*) FROM ops.identificadores_globales")" "$N0"
chk mig.verificacion_0103 "$(echo "$MOUT" | grep -c 'PASS|'):$(echo "$MOUT" | grep -c 'FAIL|')" "10:0"
OUT0103="$(qr -v schema=$S -v campus_id=3 -f "$SIGTEC_HOME/sql/checks/verificar_0103.sql")"
for c in registro_primary_key ids_unicos_entre_capas objetos_registrados disparadores_habilitados modo_de_seguridad_funciones permisos_mantenimiento secuencia_cubre_ids siguiente_id_libre; do
    l="$(echo "$OUT0103" | grep "|$c|")"; chk "mig.$c" "${l%%|*}" PASS "${l#*|*|}"
done
mig recovery
chk mig.segunda_ejecucion_rc "$MRC" 0
chk mig.segunda_ejecucion_nada "$(echo "$MOUT" | grep -c ': aplicada ')" 0 "ninguna migración reaplicada"
chk mig.segunda_ejecucion_sin_respaldo "$(nbackups)" 1
VOUT="$(bash "$SIGTEC_HOME/scripts/db/verify.sh" recovery 2>&1)"; chk mig.verify_recovery "$?" 0
echo "$VOUT" | grep -q 'apta para entregar' && rec PASS mig.verify_apta "declarada apta" || rec FAIL mig.verify_apta "no declarada apta"

# errores SQL y de permisos en una migración posterior: rc=1, sin estado parcial
for kind in sql permisos; do
    H="$TMP/home_$kind"; mkdir -p "$H"; cp -a "$SIGTEC_HOME/scripts" "$SIGTEC_HOME/sql" "$H/"
    if [ "$kind" = sql ]; then
        printf 'CREATE TABLE ops.prueba_ra01_%s(x int);\nSELECT 1/0;\n' "$kind" > "$H/sql/migrations/campus/0199_prueba_ra01.sql"
    else
        printf 'CREATE TABLE ops.prueba_ra01_%s(x int);\nSET ROLE t_editor;\nCREATE TABLE %s.prueba_ra01(x int);\n' "$kind" "$S" > "$H/sql/migrations/campus/0199_prueba_ra01.sql"
    fi
    HOME_MIG="$H" SIGTEC_HOME="$H" mig recovery
    chk "neg.error_$kind" "$MRC" 1 "$(echo "$MOUT" | grep -m1 -E 'ERROR: ' | sed 's/.*ERROR: *//' | cut -c1-80)"
    chk "neg.error_${kind}_sin_parcial" "$(qr -c "SELECT count(*) FROM ops.schema_migrations WHERE version LIKE 'campus/0199%'"):$(qr -c "SELECT to_regclass('ops.prueba_ra01_$kind') IS NULL")" "0:t" "ni registrada ni objetos a medias"
    VOUT="$(SIGTEC_HOME="$H" bash "$H/scripts/db/verify.sh" recovery 2>&1)"; r=$?
    [ "$r" != 0 ] && echo "$VOUT" | grep -q 'MIGRACIONES PENDIENTES: campus/0199' && echo "$VOUT" | grep -q 'NO APTA' \
        && rec PASS "neg.verify_detecta_pendiente_$kind" "verify rc=$r: no apta mientras falte campus/0199" || rec FAIL "neg.verify_detecta_pendiente_$kind" "rc=$r"
done

# ---------------------------------------------------------------- 5. integridad
qr -c "CREATE ROLE t_mant NOLOGIN IN ROLE sigtec_mantenimiento_id; GRANT USAGE ON SCHEMA $S TO t_mant; GRANT SELECT, INSERT ON ALL TABLES IN SCHEMA $S TO t_mant, t_editor;" >/dev/null
LIBRE=$((BASE + $(qr -c "SELECT nextval('$S.objeto_id_seq')")))
chk int.editor_guc "$(err "SET ROLE t_editor; SET sigtec.permitir_id_explicito = on; INSERT INTO $S.puntos_interes(id,nombre,tipo,geom) VALUES ($LIBRE,'X','otro',$(pt))")" 42501
chk int.editor_no_autoriza "$(err "SET ROLE t_editor; SELECT $S.sigtec_id_autorizar_explicito($LIBRE)")" 42501
chk int.editor_no_registro "$(err "SET ROLE t_editor; INSERT INTO ops.identificadores_globales(id,campus_id,capa,origen) VALUES ($LIBRE,3,'edificios','insercion')")" 42501
chk int.editor_no_deshabilita "$(err "SET ROLE t_editor; ALTER TABLE $S.puntos_interes DISABLE TRIGGER USER")" 42501
chk int.mant_mismo_id_dos_capas "$(err "BEGIN; SET LOCAL ROLE t_mant; SET LOCAL sigtec.permitir_id_explicito = on; INSERT INTO $S.puntos_interes(id,nombre,tipo,geom) VALUES ($LIBRE,'X','otro',$(pt)); INSERT INTO $S.iluminacion(id,codigo,potencia,estado,geom) VALUES ($LIBRE,'X',100,'funcional',$(pt)); COMMIT")" 23505
RID=$((BASE + $(qr -c "SELECT nextval('$S.objeto_id_seq')")))
printf "BEGIN; SET LOCAL ROLE t_mant; SET LOCAL sigtec.permitir_id_explicito = on;\nINSERT INTO $S.puntos_interes(id,nombre,tipo,geom) VALUES ($RID,'REC-C1','otro',$(pt));\nSELECT pg_sleep(4); COMMIT;\n" > "$TMP/c1.sql"
printf "BEGIN; SET LOCAL ROLE t_mant; SET LOCAL sigtec.permitir_id_explicito = on;\nINSERT INTO $S.iluminacion(id,codigo,potencia,estado,geom) VALUES ($RID,'REC-C2',100,'funcional',$(pt));\nCOMMIT;\n" > "$TMP/c2.sql"
( qr -v VERBOSITY=verbose -f "$TMP/c1.sql" > "$TMP/c1.out" 2>&1; echo "rc=$?" >> "$TMP/c1.out" ) &
P1=$!; sleep 1; t0=$(date +%s)
qr -v VERBOSITY=verbose -f "$TMP/c2.sql" > "$TMP/c2.out" 2>&1; echo "rc=$?" >> "$TMP/c2.out"; t1=$(date +%s)
wait "$P1"
chk int.carrera_primera_confirma "$(tail -1 "$TMP/c1.out")" rc=0
grep -q '23505' "$TMP/c2.out" && [ $((t1 - t0)) -ge 2 ] && rec PASS int.carrera_segunda_espera_y_falla "esperó $((t1 - t0)) s, 23505" || rec FAIL int.carrera_segunda_espera_y_falla "$(cat "$TMP/c2.out")"
chk int.carrera_una_fila "$(qr -c "SELECT count(*) FROM ($UNION) o WHERE id = $RID")" 1
N1="$(qr -c "SELECT count(*) FROM ops.identificadores_globales")"
for k in 1 2 3 4 5 6 7 8; do
    printf "SET ROLE t_editor; BEGIN; INSERT INTO $S.puntos_interes(nombre,tipo,geom) SELECT 'REC conc $k','otro',$(pt 510000+g) FROM generate_series(1,25) g; SELECT pg_sleep(4); COMMIT;\n" > "$TMP/k$k.sql"
done
for k in 1 2 3 4 5 6 7 8; do ( PGAPPNAME=ra01_concurrencia qr -f "$TMP/k$k.sql" > "$TMP/k$k.out" 2>&1; echo "rc=$?" >> "$TMP/k$k.out" ) & done
sleep 2
OVER="$(qr -c "SELECT count(*) FROM pg_stat_activity WHERE application_name = 'ra01_concurrencia' AND xact_start IS NOT NULL")"
wait
chk int.concurrencia_superpuesta "$OVER" 8 "8 transacciones abiertas a la vez"
chk int.concurrencia_confirmadas "$(cat "$TMP"/k?.out | grep -c '^rc=0$')" 8
chk int.concurrencia_registradas "$(( $(qr -c "SELECT count(*) FROM ops.identificadores_globales") - N1 ))" 200
chk int.ids_unicos "$(qr -c "SELECT count(*) FROM (SELECT id FROM ($UNION) o GROUP BY id HAVING count(*) > 1) d")" 0
LAST="$(qr -c "SELECT last_value FROM $S.objeto_id_seq")"
ID="$(qr -c "SET ROLE t_editor; INSERT INTO $S.aceras(material,ancho,condicion,geom) VALUES ('concreto',2,'buena',ST_GeomFromText('LINESTRING(510000 1090000,510005 1090005)',5367)) RETURNING id" | tail -1)"
chk int.siguiente_id "$ID" "$((BASE + LAST + 1))"
FP1="$(fingerprint)"
gosu postgres pg_ctl -D "$TMP/rec" -m fast -w restart -o "-c listen_addresses=$REC_IP -c port=5432 -c unix_socket_directories=$TMP/rec.sock -c cluster_name=sigtec-prueba-rec-recuperada" >/dev/null 2>&1
chk int.reinicio_datos "$(fingerprint)" "$FP1"
bash "$SIGTEC_HOME/scripts/db/verify.sh" recovery >/dev/null 2>&1; chk int.reinicio_verify "$?" 0
ID2="$(qr -c "INSERT INTO $S.parqueos(capacidad,tipo,disponibilidad,geom) VALUES (5,'general',5,ST_MakeEnvelope(510000,1090000,510010,1090010,5367)) RETURNING id" | tail -1)"
[ "$ID2" -gt "$ID" ] && rec PASS int.reinicio_insercion "id=$ID2 (> $ID)" || rec FAIL int.reinicio_insercion "id=$ID2 previo=$ID"

pass="$(grep -c '^PASS|' "$RESULTS")"; fail="$(grep -c '^FAIL|' "$RESULTS")"
echo "----"
echo "RESUMEN recuperación RA-01: $pass PASS, $fail FAIL"
rm -f "$RESULTS"
[ "$fail" = 0 ]
