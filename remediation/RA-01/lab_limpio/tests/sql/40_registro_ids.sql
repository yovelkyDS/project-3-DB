-- SIG-TEC · pruebas del registro global de identificadores y de la
-- autorización del modo de mantenimiento (corrección F-02, migración 0103).
-- Se ejecuta dentro de una transacción que se REVIERTE: no deja datos ni
-- roles (los roles de prueba se crean y se descartan en la transacción).
-- La concurrencia con conexiones independientes se prueba en
-- tests/container/test_ids_aislado.sh (clústeres temporales).
-- Variables: :node :schema :campus_id
BEGIN;

-- Estructura -------------------------------------------------------------
SELECT pg_temp.t(:'node' || '.registro_existe_con_pk',
                 EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'ops.identificadores_globales'::regclass
                          AND contype = 'p' AND conname = 'identificadores_globales_pkey'),
                 'ops.identificadores_globales (id PRIMARY KEY)');
SELECT pg_temp.t(:'node' || '.registro_sin_acceso_publico',
                 NOT has_table_privilege('public', 'ops.identificadores_globales', 'INSERT')
                 AND NOT has_table_privilege('public', 'ops.identificadores_globales', 'DELETE')
                 AND NOT has_schema_privilege('public', 'ops', 'USAGE'),
                 'PUBLIC sin INSERT/DELETE ni USAGE en ops');
SELECT pg_temp.t(:'node' || '.disparador_registro_8_capas', count(*) = 8, count(*) || ' tablas')
FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = :'schema' AND t.tgname = 'trg_30_registrar_identificador' AND t.tgenabled = 'O';
SELECT pg_temp.t(:'node' || '.asignacion_security_invoker', NOT p.prosecdef, 'tg_asignar_identificador SECURITY INVOKER')
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = :'schema' AND p.proname = 'tg_asignar_identificador';
SELECT pg_temp.t(:'node' || '.funciones_definer_search_path_seguro',
                 bool_and(p.prosecdef AND p.proconfig @> ARRAY['search_path=pg_catalog, pg_temp']),
                 string_agg(p.proname, ',' ORDER BY p.proname))
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = :'schema' AND p.proname IN ('sigtec_id_siguiente', 'sigtec_id_autorizar_explicito', 'tg_registrar_identificador');
SELECT pg_temp.t(:'node' || '.autorizacion_solo_mantenimiento',
                 has_function_privilege('sigtec_mantenimiento_id', (:'schema' || '.sigtec_id_autorizar_explicito(bigint)'), 'EXECUTE')
                 AND NOT has_function_privilege('public', (:'schema' || '.sigtec_id_autorizar_explicito(bigint)'), 'EXECUTE')
                 AND NOT has_function_privilege('public', (:'schema' || '.tg_registrar_identificador()'), 'EXECUTE'),
                 'EXECUTE de la autorización solo para sigtec_mantenimiento_id');
SELECT pg_temp.t(:'node' || '.rol_mantenimiento_sin_login',
                 NOT rolcanlogin AND NOT rolsuper AND NOT rolbypassrls, 'sigtec_mantenimiento_id NOLOGIN')
FROM pg_roles WHERE rolname = 'sigtec_mantenimiento_id';

-- Datos existentes: todos registrados, ninguno repetido entre capas ------
SELECT set_config('sigtec.chk_schema', :'schema', true) AS _s \gset
DO $v$
DECLARE s text := current_setting('sigtec.chk_schema'); u text;
BEGIN
    SELECT string_agg(format('SELECT id, %L::text AS capa FROM %I.%I', c, s, c), ' UNION ALL ') INTO u
      FROM unnest(ARRAY['edificios','carreteras','aceras','parqueos','zonas_verdes',
                        'puntos_interes','iluminacion','accesibilidad']) c;
    EXECUTE format('CREATE TEMP VIEW _obj AS %s', u);   -- se descarta con el ROLLBACK
END
$v$;
SELECT pg_temp.t(:'node' || '.ids_unicos_entre_capas', count(*) = 0, count(*) || ' ids repetidos entre capas')
FROM (SELECT id FROM _obj GROUP BY id HAVING count(*) > 1) d;
SELECT pg_temp.t(:'node' || '.todos_los_objetos_registrados', count(*) = 0,
                 (SELECT count(*) FROM _obj) || ' objetos; ' || count(*) || ' sin registro o con otra capa')
FROM _obj o LEFT JOIN ops.identificadores_globales g USING (id) WHERE g.id IS NULL OR g.capa <> o.capa;
SELECT pg_temp.t(:'node' || '.secuencia_cubre_registro',
                 coalesce(max(id) - :campus_id::bigint * 1000000000, 0)
                   <= coalesce(pg_sequence_last_value((:'schema' || '.objeto_id_seq')::regclass), 0),
                 'máximo consecutivo registrado ' || coalesce(max(id) - :campus_id::bigint * 1000000000, 0)
                   || ' <= último de la secuencia ' || coalesce(pg_sequence_last_value((:'schema' || '.objeto_id_seq')::regclass), 0))
FROM ops.identificadores_globales;

-- Comportamiento (roles de prueba creados dentro de la transacción) -------
CREATE ROLE sigtec_t_editor NOLOGIN;
CREATE ROLE sigtec_t_mant NOLOGIN IN ROLE sigtec_mantenimiento_id;
SELECT format('GRANT USAGE ON SCHEMA %1$I TO sigtec_t_editor; GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA %1$I TO sigtec_t_editor', :'schema') AS g \gset
:g;

SELECT set_config('sigtec_test.base', (:campus_id::bigint * 1000000000)::text, true);
-- consecutivo emitido y sin usar (las secuencias no son transaccionales: consume uno)
SELECT set_config('sigtec_test.libre',
       (:campus_id::bigint * 1000000000 + nextval((:'schema' || '.objeto_id_seq')::regclass))::text, true);

SELECT pg_temp.t(:'node' || '.editor_inserta_sin_privilegio_secuencia', r = 'NO_ERROR', r)
FROM pg_temp.expect_error(format($$SET LOCAL ROLE sigtec_t_editor;
    INSERT INTO %I.puntos_interes (nombre, tipo, geom) VALUES ('PRUEBA registro', 'otro', ST_SetSRID(ST_MakePoint(450000, 1100000), 5367))$$,
    :'schema')) r;
SELECT pg_temp.t(:'node' || '.editor_con_guc_no_inserta_id_explicito', r LIKE '42501:%no está autorizado%', r)
FROM pg_temp.expect_error(format($$SET LOCAL ROLE sigtec_t_editor; SET LOCAL sigtec.permitir_id_explicito = on;
    INSERT INTO %I.puntos_interes (id, nombre, tipo, geom) VALUES (%s, 'X', 'otro', ST_SetSRID(ST_MakePoint(450000, 1100000), 5367))$$,
    :'schema', current_setting('sigtec_test.libre'))) r;
SELECT pg_temp.t(:'node' || '.editor_no_invoca_autorizacion', r LIKE '42501:%', r)
FROM pg_temp.expect_error(format($$SET LOCAL ROLE sigtec_t_editor; SELECT %I.sigtec_id_autorizar_explicito(%s)$$,
    :'schema', current_setting('sigtec_test.libre'))) r;
SELECT pg_temp.t(:'node' || '.editor_no_escribe_registro', r LIKE '42501:%', r)
FROM pg_temp.expect_error(format($$SET LOCAL ROLE sigtec_t_editor;
    INSERT INTO ops.identificadores_globales (id, campus_id, capa, origen) VALUES (%s, %s, 'edificios', 'insercion')$$,
    current_setting('sigtec_test.libre'), :campus_id)) r;
SELECT pg_temp.t(:'node' || '.editor_no_desactiva_disparadores', r LIKE '42501:%', r)
FROM pg_temp.expect_error(format($$SET LOCAL ROLE sigtec_t_editor; ALTER TABLE %I.puntos_interes DISABLE TRIGGER USER$$, :'schema')) r;
SELECT pg_temp.t(:'node' || '.editor_no_activa_modo_replica', r LIKE '42501:%', r)
FROM pg_temp.expect_error($$SET LOCAL ROLE sigtec_t_editor; SET LOCAL session_replication_role = replica$$) r;

-- Mantenimiento autorizado: id emitido y libre -> se acepta; el mismo id en otra capa -> 23505
SELECT pg_temp.t(:'node' || '.mantenimiento_autorizado_y_unicidad_entre_capas',
                 r = '23505', r)
FROM (SELECT left(pg_temp.expect_error(format($$SET LOCAL ROLE sigtec_t_mant; SET LOCAL sigtec.permitir_id_explicito = on;
    INSERT INTO %1$I.puntos_interes (id, nombre, tipo, geom) VALUES (%2$s, 'PRUEBA mant', 'otro', ST_SetSRID(ST_MakePoint(450000, 1100000), 5367));
    INSERT INTO %1$I.iluminacion (id, codigo, potencia, estado, geom) VALUES (%2$s, 'PRUEBA-MANT', 100, 'funcional', ST_SetSRID(ST_MakePoint(450000, 1100000), 5367))$$,
    :'schema', current_setting('sigtec_test.libre'))), 5) AS r) x;
SELECT pg_temp.t(:'node' || '.mantenimiento_autorizado_inserta', r = 'NO_ERROR', r)
FROM pg_temp.expect_error(format($$SET LOCAL ROLE sigtec_t_mant; SET LOCAL sigtec.permitir_id_explicito = on;
    INSERT INTO %I.puntos_interes (id, nombre, tipo, geom) VALUES (%s, 'PRUEBA mant', 'otro', ST_SetSRID(ST_MakePoint(450000, 1100000), 5367))$$,
    :'schema', current_setting('sigtec_test.libre'))) r;
SELECT pg_temp.t(:'node' || '.mantenimiento_no_modifica_ids', r LIKE '42501:%', r)
FROM pg_temp.expect_error(format($$SET LOCAL ROLE sigtec_t_mant; UPDATE %I.puntos_interes SET nombre = nombre$$, :'schema')) r;

-- Un id ya registrado (objeto existente) no puede reutilizarse en otra capa
SELECT pg_temp.t(:'node' || '.id_existente_no_reutilizable', r LIKE '23505:%ya existe en el registro%', r)
FROM pg_temp.expect_error(format($$SET LOCAL sigtec.permitir_id_explicito = on;
    INSERT INTO %I.accesibilidad (id, tipo, condicion, geom) VALUES (%s, 'rampa', 'buena', ST_GeomFromText('LINESTRING(450000 1100000,450005 1100005)', 5367))$$,
    :'schema', (SELECT min(id) FROM ops.identificadores_globales))) r;

ROLLBACK;
