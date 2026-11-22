#!/usr/bin/env bash
# =====================================================================
# SIG-TEC · pruebas de regresión F-02 (identificadores globales) en
# clústeres PostgreSQL TEMPORALES dentro de sigtec-tools.
#   tests/container/test_ids_aislado.sh [all|campus|<nodo> ...]
#
# Para cada campus:
#   * levanta un clúster nuevo en 127.0.0.1:5432 DENTRO de este contenedor
#     efímero y redirige el nombre pg-<campus> a él en /etc/hosts; antes de
#     ejecutar los scripts reales (migrate.sh, seed.sh) comprueba que el
#     destino es el clúster temporal (cluster_name) y aborta si no lo es;
#   * instalación limpia con TODAS las migraciones + datos de prueba;
#   * concurrencia REAL: varias conexiones psql independientes con
#     transacciones superpuestas;
#   * roles, mantenimiento, rollback, eliminación, reinicio, pg_dump/restore,
#     publicación lógica;
#   * ruta de actualización: base con 0101–0102 + datos + un id repetido
#     entre capas -> 0103 aborta sin cambios; resuelto -> 0103 se aplica.
# Ningún nodo en servicio se toca. Salida PASS|FAIL|<caso>|<detalle>.
# =====================================================================
. "${SIGTEC_HOME:-/opt/sigtec}/scripts/lib/db.sh"
set +e

RESULTS="$(mktemp)"
rec() { echo "$1|$2|$3" | tee -a "$RESULTS"; }
chk() { if [ "$2" = "$3" ]; then rec PASS "$1" "${4:-$2}"; else rec FAIL "$1" "esperado [$3] obtenido [$2] ${4:-}"; fi; }

PGPORT=5432; DBH=127.0.0.1
cp /etc/hosts /tmp/sigtec-hosts.orig
# pg-recovery nunca debe resolver a la instancia real (migrate.sh la consulta
# para avisar de migraciones pendientes): se dirige a una dirección sin servidor
restore_hosts() { cat /tmp/sigtec-hosts.orig > /etc/hosts; echo "127.0.0.9 pg-recovery" >> /etc/hosts; }
restore_hosts

q()   { psql -X -q -v ON_ERROR_STOP=1 -h "$DBH" -p "$PGPORT" -U postgres -d "${DB:-sigtec}" -tA "$@"; }
# err <sql>  -> "NO_ERROR" o el SQLSTATE del primer error (sesión propia)
err() {
    local out
    out="$(psql -X -q -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -h "$DBH" -p "$PGPORT" -U postgres -d "${DB:-sigtec}" -tA -c "$1" 2>&1)"
    if [ $? = 0 ]; then echo NO_ERROR; else echo "$out" | sed -n 's/^ERROR:  \([0-9A-Z]\{5\}\):.*/\1/p' | head -1; fi
}
# bg <salida> <archivo.sql> : ejecuta el SQL en una conexión independiente, en segundo plano
# (se invoca como orden simple, nunca dentro de un pipeline, para que "wait" la espere)
bg() { ( psql -X -q -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -h "$DBH" -p "$PGPORT" -U postgres -d "${DB:-sigtec}" -tA -f "$2" > "$1" 2>&1; echo "rc=$?" >> "$1" ) & }

start_cluster() {
    TMP="$(mktemp -d /tmp/sigtec-ids.XXXXXX)"; chown postgres:postgres "$TMP"; chmod 0755 "$TMP"
    gosu postgres initdb -D "$TMP/data" -U postgres --auth=trust --data-checksums >/dev/null
    gosu postgres pg_ctl -D "$TMP/data" -l "$TMP/log" -w -o \
        "-c listen_addresses=127.0.0.1 -c port=$PGPORT -c unix_socket_directories=$TMP -c cluster_name=sigtec-prueba-ids -c wal_level=logical -c max_connections=60" start >/dev/null
}
stop_cluster() { gosu postgres pg_ctl -D "$TMP/data" -m fast -w stop >/dev/null 2>&1; rm -rf "$TMP"; restore_hosts; }
guard() {   # el nombre del nodo DEBE resolver al clúster temporal
    local cn
    cn="$(PGPASSWORD=x psql -X -h "$(node_host "$1")" -p 5432 -U postgres -d postgres -tAc "SHOW cluster_name" 2>/dev/null)"
    [ "$cn" = "sigtec-prueba-ids" ] || { echo "ABORTO: $(node_host "$1") no apunta al clúster temporal (cluster_name='$cn')"; stop_cluster; exit 2; }
}
prepare_node() {   # prepare_node <nodo> [sin0103]
    local node="$1" home="$SIGTEC_HOME"
    start_cluster
    echo "127.0.0.1 $(node_host "$node")" >> /etc/hosts
    guard "$node"
    q -d postgres -c "CREATE DATABASE sigtec" >/dev/null
    if [ "${2:-}" = sin0103 ]; then
        home="$TMP/home"; mkdir -p "$home"; cp -a "$SIGTEC_HOME/scripts" "$SIGTEC_HOME/sql" "$home/"
        rm -f "$home"/sql/migrations/campus/0103_*.sql
    fi
    SIGTEC_HOME="$home" bash "$home/scripts/db/migrate.sh" "$node" > "$TMP/migrate.log" 2>&1 || { cat "$TMP/migrate.log"; return 1; }
    SIGTEC_HOME="$home" bash "$home/scripts/db/seed.sh" "$node" > "$TMP/seed.log" 2>&1 || { cat "$TMP/seed.log"; return 1; }
}

UNION_IDS() {  # SQL: todas las filas (id, capa) del esquema
    local s="$1" l u=""
    for l in $SIGTEC_LAYERS; do u="$u${u:+ UNION ALL }SELECT id, '$l' AS capa FROM $s.$l"; done
    echo "$u"
}
invariantes() {   # invariantes <caso> <esquema> : ids únicos entre capas y todos registrados con su capa
    local s="$1" r
    r="$(q -c "WITH o AS ($(UNION_IDS "$s"))
              SELECT (SELECT count(*) FROM o) || ':' ||
                     (SELECT count(*) FROM (SELECT id FROM o GROUP BY id HAVING count(*) > 1) d) || ':' ||
                     (SELECT count(*) FROM o LEFT JOIN ops.identificadores_globales g USING (id)
                       WHERE g.id IS NULL OR g.capa <> o.capa)")"
    echo "$r"
}

pt() { echo "ST_SetSRID(ST_MakePoint(${1:-500000}, ${2:-1100000}), 5367)"; }

run_campus() {
    local node="$1" s cid base n last id r f1 f2 t0 waited
    s="$(node_schema "$node")"; cid="$(node_campus_id "$node")"; base=$((cid * 1000000000))
    local P="$node"
    if ! prepare_node "$node"; then rec FAIL "$P.instalacion_limpia" "migrate/seed falló"; stop_cluster; return; fi
    chk "$P.instalacion_limpia" "$(q -c "SELECT count(*) FROM ops.schema_migrations WHERE version LIKE 'campus/%'")" 3 "0101, 0102 y 0103 aplicadas"
    r="$(invariantes "$s")"; chk "$P.registro_inicial" "$r" "41:0:0" "41 objetos, 0 repetidos, 0 sin registro"

    # Roles de prueba (solo en el clúster temporal)
    q -c "CREATE ROLE t_editor NOLOGIN; GRANT USAGE ON SCHEMA $s TO t_editor;
          GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA $s TO t_editor;
          CREATE ROLE t_mant NOLOGIN IN ROLE sigtec_mantenimiento_id;
          CREATE ROLE t_nada NOLOGIN;" >/dev/null

    # 1. inserción normal por un rol de edición sin privilegios de secuencia
    chk "$P.editor_sin_privilegio_secuencia" "$(q -c "SELECT has_sequence_privilege('t_editor','$s.objeto_id_seq','USAGE')")" f
    last="$(q -c "SELECT pg_sequence_last_value('$s.objeto_id_seq')")"
    id="$(q -c "SET ROLE t_editor; INSERT INTO $s.puntos_interes(nombre,tipo,geom) VALUES ('T normal','otro',$(pt)) RETURNING id" | tail -1)"
    chk "$P.insercion_normal_id_generado" "$id" "$((base + last + 1))" "id=$id"
    chk "$P.insercion_normal_registrada" "$(q -c "SELECT capa || '/' || origen FROM ops.identificadores_globales WHERE id=$id")" "puntos_interes/insercion"

    # 2. inserciones simultáneas en las ocho capas (8 conexiones, transacciones superpuestas)
    n0="$(q -c "SELECT count(*) FROM ops.identificadores_globales")"
    local i=0 l sql
    for l in $SIGTEC_LAYERS; do
        i=$((i + 1))
        case "$l" in
          edificios)      sql="INSERT INTO $s.edificios(nombre,codigo,area,pisos,geom) SELECT 'T', 'TC-'||g, 10, 1, ST_MakeEnvelope(500000+g,1100000,500001+g,1100001,5367) FROM generate_series(1,25) g;" ;;
          carreteras)     sql="INSERT INTO $s.carreteras(nombre,tipo,superficie,geom) SELECT 'T','interna','asfalto',ST_MakeLine($(pt),ST_SetSRID(ST_MakePoint(500010+g,1100010),5367)) FROM generate_series(1,25) g;" ;;
          aceras)         sql="INSERT INTO $s.aceras(material,ancho,condicion,geom) SELECT 'concreto',2,'buena',ST_MakeLine($(pt),ST_SetSRID(ST_MakePoint(500010+g,1100010),5367)) FROM generate_series(1,25) g;" ;;
          parqueos)       sql="INSERT INTO $s.parqueos(capacidad,tipo,disponibilidad,geom) SELECT 10,'general',5,ST_MakeEnvelope(500000+g,1100000,500001+g,1100001,5367) FROM generate_series(1,25) g;" ;;
          zonas_verdes)   sql="INSERT INTO $s.zonas_verdes(area,tipo_vegetacion,geom) SELECT 10,'cesped',ST_MakeEnvelope(500000+g,1100000,500001+g,1100001,5367) FROM generate_series(1,25) g;" ;;
          puntos_interes) sql="INSERT INTO $s.puntos_interes(nombre,tipo,geom) SELECT 'T','otro',$(pt) FROM generate_series(1,25) g;" ;;
          iluminacion)    sql="INSERT INTO $s.iluminacion(codigo,potencia,estado,geom) SELECT 'TL-'||g,100,'funcional',$(pt) FROM generate_series(1,25) g;" ;;
          accesibilidad)  sql="INSERT INTO $s.accesibilidad(tipo,condicion,geom) SELECT 'rampa','buena',ST_MakeLine($(pt),ST_SetSRID(ST_MakePoint(500010+g,1100010),5367)) FROM generate_series(1,25) g;" ;;
        esac
        sql2="${sql//TC-/TD-}"; sql2="${sql2//TL-/TM-}"
        printf 'BEGIN; SET ROLE t_editor;\n%s\nSELECT pg_sleep(1.5);\n%s\nCOMMIT;\n' "$sql" "$sql2" > "$TMP/c$i.sql"
        bg "$TMP/c$i.out" "$TMP/c$i.sql"
    done
    sleep 0.7
    chk "$P.concurrencia_8_capas_solapadas" "$(q -c "SELECT count(*) FROM pg_stat_activity WHERE state LIKE '%transaction%' OR wait_event = 'PgSleep'")" 8 "8 transacciones abiertas simultáneamente"
    wait
    r="$(grep -h '^rc=' "$TMP"/c*.out | sort | uniq -c | tr -s ' ' | tr '\n' ' ')"
    chk "$P.concurrencia_8_capas_sesiones_ok" "$(grep -h '^rc=0' "$TMP"/c*.out | wc -l | tr -d ' ')" 8 "$r"
    chk "$P.concurrencia_8_capas_ids_registrados" "$(( $(q -c "SELECT count(*) FROM ops.identificadores_globales") - n0 ))" 400 "400 ids nuevos"
    r="$(invariantes "$s")"; chk "$P.concurrencia_8_capas_sin_repetidos" "${r#*:}" "0:0" "objetos:repetidos:sin_registro = $r"

    # 3. mismo id explícito en dos tablas, dos sesiones autorizadas superpuestas
    id="$(( base + $(q -c "SELECT nextval('$s.objeto_id_seq')") ))"
    printf "BEGIN; SET ROLE t_mant; SET LOCAL sigtec.permitir_id_explicito=on;\nINSERT INTO %s.puntos_interes(id,nombre,tipo,geom) VALUES (%s,'T race 1','otro',%s);\nSELECT pg_sleep(3); COMMIT;\n" "$s" "$id" "$(pt)" > "$TMP/r1.sql"
    bg "$TMP/r1.out" "$TMP/r1.sql"
    sleep 1; t0=$(date +%s)
    r="$(err "BEGIN; SET ROLE t_mant; SET LOCAL sigtec.permitir_id_explicito=on; INSERT INTO $s.iluminacion(id,codigo,potencia,estado,geom) VALUES ($id,'T-RACE',100,'funcional',$(pt)); COMMIT;")"
    waited=$(( $(date +%s) - t0 )); wait
    chk "$P.carrera_mismo_id_segunda_rechazada" "$r" 23505 "sesión 2 esperó ${waited}s y recibió $r"
    chk "$P.carrera_mismo_id_primera_confirmada" "$(tail -1 "$TMP/r1.out")" rc=0
    chk "$P.carrera_mismo_id_una_sola_fila" "$(q -c "SELECT (SELECT count(*) FROM $s.puntos_interes WHERE id=$id)+(SELECT count(*) FROM $s.iluminacion WHERE id=$id)")" 1

    # 3b. si la primera sesión revierte, la segunda (bloqueada) sí se confirma
    id="$(( base + $(q -c "SELECT nextval('$s.objeto_id_seq')") ))"
    printf "BEGIN; SET ROLE t_mant; SET LOCAL sigtec.permitir_id_explicito=on;\nINSERT INTO %s.edificios(id,nombre,codigo,area,pisos,geom) VALUES (%s,'T rb','T-RB-1',10,1,ST_MakeEnvelope(500000,1100000,500001,1100001,5367));\nSELECT pg_sleep(2); ROLLBACK;\n" "$s" "$id" > "$TMP/r2.sql"
    bg "$TMP/r2.out" "$TMP/r2.sql"
    sleep 1
    r="$(err "BEGIN; SET ROLE t_mant; SET LOCAL sigtec.permitir_id_explicito=on; INSERT INTO $s.zonas_verdes(id,area,tipo_vegetacion,geom) VALUES ($id,10,'cesped',ST_MakeEnvelope(500000,1100000,500001,1100001,5367)); COMMIT;")"
    wait
    chk "$P.carrera_primera_revierte_segunda_confirma" "$r" NO_ERROR
    chk "$P.carrera_revertida_registro_coherente" "$(q -c "SELECT capa FROM ops.identificadores_globales WHERE id=$id")" zonas_verdes

    # 3c. mismo id explícito, secuencial, en otra capa
    chk "$P.id_explicito_repetido_otra_capa" "$(err "SET ROLE t_mant; SET sigtec.permitir_id_explicito=on; INSERT INTO $s.carreteras(id,nombre,tipo,superficie,geom) VALUES ($id,'T','interna','asfalto',ST_MakeLine($(pt),$(pt 500005))); ")" 23505

    # 4. prefijo de otro campus / campus_id ajeno
    local otro=$(( cid == 5 ? 1 : cid + 1 ))
    chk "$P.rechaza_id_prefijo_otro_campus" "$(err "SET ROLE t_mant; SET sigtec.permitir_id_explicito=on; INSERT INTO $s.puntos_interes(id,nombre,tipo,geom) VALUES ($((otro * 1000000000 + 1)),'T','otro',$(pt))")" 23514
    chk "$P.rechaza_campus_id_ajeno" "$(err "SET ROLE t_editor; INSERT INTO $s.puntos_interes(campus_id,nombre,tipo,geom) VALUES ($otro,'T','otro',$(pt))")" 23514

    # 5-6. inmutabilidad
    id="$(q -c "SELECT min(id) FROM $s.puntos_interes")"
    chk "$P.rechaza_modificar_id" "$(err "SET ROLE t_editor; UPDATE $s.puntos_interes SET id=id+1 WHERE id=$id")" 23514
    chk "$P.rechaza_modificar_campus_id" "$(err "SET ROLE t_editor; UPDATE $s.puntos_interes SET campus_id=$otro WHERE id=$id")" 23514
    chk "$P.rechaza_modificar_id_mantenimiento" "$(err "SET ROLE t_mant; SET sigtec.permitir_id_explicito=on; UPDATE $s.puntos_interes SET id=id+1 WHERE id=$id")" 42501

    # 7. rutas que un rol ordinario podría intentar
    id="$(( base + $(q -c "SELECT nextval('$s.objeto_id_seq')") ))"
    chk "$P.editor_con_guc_rechazado" "$(err "SET ROLE t_editor; SET sigtec.permitir_id_explicito=on; INSERT INTO $s.puntos_interes(id,nombre,tipo,geom) VALUES ($id,'T','otro',$(pt))")" 42501
    chk "$P.editor_no_ejecuta_autorizacion" "$(err "SET ROLE t_editor; SELECT $s.sigtec_id_autorizar_explicito($id)")" 42501
    chk "$P.editor_no_escribe_registro" "$(err "SET ROLE t_editor; INSERT INTO ops.identificadores_globales(id,campus_id,capa,origen) VALUES ($id,$cid,'edificios','insercion')")" 42501
    chk "$P.editor_no_borra_registro" "$(err "SET ROLE t_editor; DELETE FROM ops.identificadores_globales")" 42501
    chk "$P.editor_no_usa_secuencia" "$(err "SET ROLE t_editor; SELECT nextval('$s.objeto_id_seq')")" 42501
    chk "$P.editor_no_desactiva_disparadores" "$(err "SET ROLE t_editor; ALTER TABLE $s.puntos_interes DISABLE TRIGGER USER")" 42501
    chk "$P.editor_no_modo_replica" "$(err "SET ROLE t_editor; SET session_replication_role = replica")" 42501
    chk "$P.editor_no_reutiliza_disparador" "$(err "SET ROLE t_editor; CREATE TEMP TABLE x(id bigint, campus_id smallint); CREATE TRIGGER x AFTER INSERT ON x FOR EACH ROW EXECUTE FUNCTION $s.tg_registrar_identificador()")" 42501
    n="$(q -c "SELECT count(*) FROM ops.identificadores_globales")"
    r="$(err "SET ROLE t_editor; SELECT $s.sigtec_id_siguiente()")"
    chk "$P.siguiente_directo_no_registra" "$r:$(q -c "SELECT count(*) FROM ops.identificadores_globales")" "NO_ERROR:$n" "solo consume un consecutivo (hueco), no reserva ids"
    chk "$P.rol_sin_permisos_no_inserta" "$(err "SET ROLE t_nada; INSERT INTO $s.puntos_interes(nombre,tipo,geom) VALUES ('T','otro',$(pt))")" 42501

    # 8. mantenimiento con permisos: id emitido y libre
    chk "$P.mantenimiento_autorizado_inserta" "$(err "SET ROLE t_mant; SET sigtec.permitir_id_explicito=on; INSERT INTO $s.puntos_interes(id,nombre,tipo,geom) VALUES ($id,'T mant','otro',$(pt))")" NO_ERROR
    chk "$P.mantenimiento_rechaza_id_no_emitido" "$(err "SET ROLE t_mant; SET sigtec.permitir_id_explicito=on; INSERT INTO $s.puntos_interes(id,nombre,tipo,geom) VALUES ($((base + 999999999)),'T','otro',$(pt))")" 23514
    chk "$P.mantenimiento_sin_guc_rechazado" "$(err "SET ROLE t_mant; INSERT INTO $s.puntos_interes(id,nombre,tipo,geom) VALUES ($id,'T','otro',$(pt))")" 23514

    # 10. rollback y posterior inserción
    id="$(q -c "BEGIN; INSERT INTO $s.aceras(material,ancho,condicion,geom) VALUES ('concreto',2,'buena',ST_MakeLine($(pt),$(pt 500005))) RETURNING id; ROLLBACK;" | head -1)"
    chk "$P.rollback_no_deja_registro" "$(q -c "SELECT count(*) FROM ops.identificadores_globales WHERE id=$id")" 0
    r="$(q -c "INSERT INTO $s.aceras(material,ancho,condicion,geom) VALUES ('concreto',2,'buena',ST_MakeLine($(pt),$(pt 500005))) RETURNING id" | tail -1)"
    [ "$r" -gt "$id" ] && rec PASS "$P.rollback_siguiente_id_mayor" "$id revertido -> $r" || rec FAIL "$P.rollback_siguiente_id_mayor" "$id -> $r"
    chk "$P.rollback_id_reinsertable_mantenimiento" "$(err "SET ROLE t_mant; SET sigtec.permitir_id_explicito=on; INSERT INTO $s.aceras(id,material,ancho,condicion,geom) VALUES ($id,'concreto',2,'buena',ST_MakeLine($(pt),$(pt 500005)))")" NO_ERROR

    # 11. eliminación: el id no se reutiliza
    id="$(q -c "INSERT INTO $s.parqueos(capacidad,tipo,disponibilidad,geom) VALUES (5,'general',1,ST_MakeEnvelope(500000,1100000,500001,1100001,5367)) RETURNING id" | tail -1)"
    q -c "DELETE FROM $s.parqueos WHERE id=$id" >/dev/null
    chk "$P.eliminacion_conserva_registro" "$(q -c "SELECT capa FROM ops.identificadores_globales WHERE id=$id")" parqueos
    chk "$P.eliminacion_id_no_reutilizable" "$(err "SET ROLE t_mant; SET sigtec.permitir_id_explicito=on; INSERT INTO $s.parqueos(id,capacidad,tipo,disponibilidad,geom) VALUES ($id,5,'general',1,ST_MakeEnvelope(500000,1100000,500001,1100001,5367))")" 23505
    r="$(q -c "INSERT INTO $s.parqueos(capacidad,tipo,disponibilidad,geom) VALUES (5,'general',1,ST_MakeEnvelope(500000,1100000,500001,1100001,5367)) RETURNING id" | tail -1)"
    [ "$r" -gt "$id" ] && rec PASS "$P.eliminacion_nuevo_id_distinto" "$id eliminado -> nuevo $r" || rec FAIL "$P.eliminacion_nuevo_id_distinto" "$r"

    # 12. reinicio de PostgreSQL
    r="$(invariantes "$s")"
    gosu postgres pg_ctl -D "$TMP/data" -m fast -w restart >/dev/null 2>&1
    chk "$P.reinicio_invariantes" "$(invariantes "$s")" "$r" "objetos:repetidos:sin_registro = $r"
    id="$(q -c "INSERT INTO $s.edificios(nombre,codigo,area,pisos,geom) VALUES ('T rein','T-REIN',10,1,ST_MakeEnvelope(500000,1100000,500001,1100001,5367)) RETURNING id" | tail -1)"
    chk "$P.reinicio_inserta_y_registra" "$(q -c "SELECT count(*) FROM ops.identificadores_globales WHERE id=$id AND capa='edificios'")" 1

    # 13. pg_dump / pg_restore y consistencia de secuencia y registro
    pg_dump -h "$DBH" -U postgres -d sigtec -Fc -f "$TMP/a.dump"
    id="$(q -c "INSERT INTO $s.edificios(nombre,codigo,area,pisos,geom) VALUES ('T tras dump','T-POST',10,1,ST_MakeEnvelope(500000,1100000,500001,1100001,5367)) RETURNING id" | tail -1)"
    q -d postgres -c "CREATE DATABASE sigtec_r" >/dev/null
    pg_restore -h "$DBH" -U postgres -d sigtec_r --exit-on-error "$TMP/a.dump"; chk "$P.restauracion_sin_errores" "$?" 0
    DB=sigtec_r
    chk "$P.restauracion_invariantes" "$(invariantes "$s" | cut -d: -f2-)" "0:0"
    chk "$P.restauracion_disparadores" "$(q -c "SELECT count(*) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='$s' AND NOT t.tgisinternal")" 24
    # procedimiento documentado: 1) ajustar la secuencia al máximo conocido (central), 2) reincorporar
    last="$(DB=sigtec q -c "WITH o AS ($(UNION_IDS "$s")) SELECT max(id) FROM o")"
    chk "$P.restauracion_id_posterior_rechazado_antes_de_ajustar" "$(err "SET sigtec.permitir_id_explicito=on; INSERT INTO $s.edificios(id,nombre,codigo,area,pisos,geom) VALUES ($id,'T tras dump','T-POST',10,1,ST_MakeEnvelope(500000,1100000,500001,1100001,5367))")" 23514 "id $id no emitido según la secuencia restaurada"
    q -v schema="$s" -v campus_id="$cid" -v max_id="$last" -f "$SIGTEC_HOME/sql/templates/ajustar_secuencia_tras_recuperacion.sql" >/dev/null
    chk "$P.restauracion_reincorpora_id_posterior" "$(err "SET sigtec.permitir_id_explicito=on; INSERT INTO $s.edificios(id,nombre,codigo,area,pisos,geom) VALUES ($id,'T tras dump','T-POST',10,1,ST_MakeEnvelope(500000,1100000,500001,1100001,5367))")" NO_ERROR "id $id creado después del respaldo, reincorporado en mantenimiento"
    chk "$P.restauracion_rechaza_duplicado" "$(err "SET sigtec.permitir_id_explicito=on; INSERT INTO $s.puntos_interes(id,nombre,tipo,geom) VALUES ($id,'T','otro',$(pt))")" 23505
    r="$(q -c "INSERT INTO $s.puntos_interes(nombre,tipo,geom) VALUES ('T ajuste','otro',$(pt)) RETURNING id" | tail -1)"
    [ "$r" -gt "$last" ] && rec PASS "$P.restauracion_secuencia_ajustada" "máximo conocido $last -> siguiente $r" || rec FAIL "$P.restauracion_secuencia_ajustada" "$last -> $r"
    DB=sigtec

    # 14. compatibilidad con la replicación lógica futura
    q -c "CREATE PUBLICATION t_pub FOR TABLES IN SCHEMA $s" >/dev/null
    chk "$P.publicacion_ocho_tablas" "$(q -c "SELECT count(*) FROM pg_publication_tables WHERE pubname='t_pub' AND schemaname='$s'")" 8
    chk "$P.publicacion_excluye_ops" "$(q -c "SELECT count(*) FROM pg_publication_tables WHERE pubname='t_pub' AND schemaname='ops'")" 0
    chk "$P.replica_identity_pk" "$(q -c "SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='$s' AND c.relkind='r' AND c.relreplident='d'")" 8
    chk "$P.columnas_sin_cambios" "$(q -c "SELECT count(*) FROM information_schema.columns WHERE table_schema='$s'")" "$(q -c "SELECT 3*8 + 4+3+3+3+2+3+3+3")"

    r="$(invariantes "$s")"; chk "$P.invariantes_finales" "${r#*:}" "0:0" "objetos:repetidos:sin_registro = $r"
    stop_cluster
}

upgrade_path() {   # ruta de actualización desde 0102 con un id repetido entre capas
    local node=cartago s=local_cartago id r
    if ! prepare_node "$node" sin0103; then rec FAIL actualizacion.preparacion "falló"; stop_cluster; return; fi
    chk actualizacion.base_sin_0103 "$(q -c "SELECT count(*) FROM ops.schema_migrations WHERE version LIKE 'campus/0103%'")" 0
    id="$(q -c "SELECT min(id) FROM $s.puntos_interes")"
    q -c "ALTER TABLE $s.iluminacion DISABLE TRIGGER USER;
          INSERT INTO $s.iluminacion(id,campus_id,codigo,potencia,estado,geom) VALUES ($id,1,'T-DUP',100,'funcional',$(pt));
          ALTER TABLE $s.iluminacion ENABLE TRIGGER USER;" >/dev/null
    r="$(bash "$SIGTEC_HOME/scripts/db/migrate.sh" "$node" 2>&1)"; rc=$?
    [ "$rc" != 0 ] && echo "$r" | grep -q "repetido(s) entre capas de $s: $id en iluminacion+puntos_interes" \
        && rec PASS actualizacion.aborta_con_duplicado "rc=$rc, conflicto informado: $id en iluminacion+puntos_interes" \
        || rec FAIL actualizacion.aborta_con_duplicado "rc=$rc"
    chk actualizacion.sin_cambios_parciales "$(q -c "SELECT (to_regclass('ops.identificadores_globales') IS NULL) || ':' || (SELECT count(*) FROM ops.schema_migrations WHERE version LIKE 'campus/0103%') || ':' || (SELECT count(*) FROM pg_trigger WHERE tgname='trg_30_registrar_identificador') || ':' || (SELECT prosecdef FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='$s' AND proname='tg_asignar_identificador')")" "true:0:0:true" "registro:0103:trg30:secdef"
    chk actualizacion.datos_intactos "$(q -c "SELECT count(*) FROM $s.iluminacion WHERE id=$id") $(q -c "SELECT count(*) FROM $s.puntos_interes WHERE id=$id")" "1 1" "no borró ni renumeró"
    q -c "DELETE FROM $s.iluminacion WHERE codigo='T-DUP'" >/dev/null
    bash "$SIGTEC_HOME/scripts/db/migrate.sh" "$node" > /dev/null 2>&1; chk actualizacion.aplica_tras_resolver "$?" 0
    r="$(invariantes "$s")"; chk actualizacion.registro_completo "$r" "41:0:0"
    chk actualizacion.idempotente "$(bash "$SIGTEC_HOME/scripts/db/migrate.sh" "$node" 2>&1 | grep -c 'aplicada campus/0103')" 0 "un segundo migrate no reaplica 0103"
    stop_cluster
}

nodes="$(nodes_expand "${@:-campus}")"
for node in $nodes; do node_is_campus "$node" && run_campus "$node"; done
upgrade_path

pass="$(grep -c '^PASS|' "$RESULTS")"; fail="$(grep -c '^FAIL|' "$RESULTS")"
echo "----"
echo "RESUMEN identificadores: $pass PASS, $fail FAIL"
rm -f "$RESULTS"
[ "$fail" = 0 ]
