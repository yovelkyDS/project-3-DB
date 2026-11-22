-- =====================================================================
-- SIG-TEC · comprobación de que la migración 0103 (registro global de
-- identificadores) está aplicada y operativa en un esquema de campus.
-- Sirve para los cinco campus y para un nodo recuperado (pg-recovery).
--   psql -v schema=local_san_carlos -v campus_id=3 -f sql/checks/verificar_0103.sql
-- Salida: una línea por criterio,  PASS|<criterio>|<detalle>  o  FAIL|…
-- Solo lectura. Si 0103 no está aplicada, la primera línea es FAIL y el resto
-- no se evalúa (no hay registro que consultar).
-- =====================================================================
\set QUIET on
\pset tuples_only on
\pset format unaligned
SELECT (to_regclass('ops.identificadores_globales') IS NOT NULL
        AND EXISTS (SELECT 1 FROM ops.schema_migrations WHERE version = 'campus/0103_registro_identificadores')) AS sigtec_0103 \gset
\if :sigtec_0103
\else
SELECT 'FAIL|0103_aplicada|ops.identificadores_globales o el registro de la migración no existen';
\quit
\endif

CREATE TEMP VIEW _sigtec_obj AS
          SELECT id, 'edificios'::text      AS capa FROM :"schema".edificios
UNION ALL SELECT id, 'carreteras'            FROM :"schema".carreteras
UNION ALL SELECT id, 'aceras'                FROM :"schema".aceras
UNION ALL SELECT id, 'parqueos'              FROM :"schema".parqueos
UNION ALL SELECT id, 'zonas_verdes'          FROM :"schema".zonas_verdes
UNION ALL SELECT id, 'puntos_interes'        FROM :"schema".puntos_interes
UNION ALL SELECT id, 'iluminacion'           FROM :"schema".iluminacion
UNION ALL SELECT id, 'accesibilidad'         FROM :"schema".accesibilidad;

SELECT 'PASS|0103_aplicada|registrada ' || to_char(applied_at, 'YYYY-MM-DD HH24:MI:SS')
FROM ops.schema_migrations WHERE version = 'campus/0103_registro_identificadores';

SELECT CASE WHEN count(*) = 1 THEN 'PASS' ELSE 'FAIL' END || '|registro_primary_key|' || coalesce(string_agg(pg_get_constraintdef(oid), ''), 'sin PRIMARY KEY')
FROM pg_constraint WHERE conrelid = 'ops.identificadores_globales'::regclass AND contype = 'p'
  AND pg_get_constraintdef(oid) = 'PRIMARY KEY (id)';

SELECT CASE WHEN n = 0 THEN 'PASS' ELSE 'FAIL' END || '|ids_unicos_entre_capas|' || n || ' ids repetidos'
FROM (SELECT count(*) AS n FROM (SELECT id FROM _sigtec_obj GROUP BY id HAVING count(*) > 1) d) x;

SELECT CASE WHEN n = 0 THEN 'PASS' ELSE 'FAIL' END || '|objetos_registrados|'
       || (SELECT count(*) FROM _sigtec_obj) || ' objetos; ' || n || ' sin registro o con otra capa'
FROM (SELECT count(*) AS n FROM _sigtec_obj o LEFT JOIN ops.identificadores_globales g USING (id)
       WHERE g.id IS NULL OR g.capa <> o.capa) x;

SELECT CASE WHEN n = 0 THEN 'PASS' ELSE 'FAIL' END || '|registro_campus_y_formato|' || n || ' filas con otro campus o fuera de formato'
FROM (SELECT count(*) AS n FROM ops.identificadores_globales
       WHERE campus_id <> :campus_id OR id / 1000000000 <> :campus_id) x;

SELECT CASE WHEN count(*) = 24 AND bool_and(t.tgenabled = 'O') THEN 'PASS' ELSE 'FAIL' END
       || '|disparadores_habilitados|' || count(*) || ' (esperado 24: trg_10, trg_20, trg_30 × 8 capas); deshabilitados: '
       || count(*) FILTER (WHERE t.tgenabled <> 'O')
FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
WHERE c.relnamespace = :'schema'::regnamespace AND NOT t.tgisinternal
  AND t.tgname IN ('trg_10_asignar_identificador', 'trg_20_proteger_identificador', 'trg_30_registrar_identificador')
  AND c.relname IN ('edificios','carreteras','aceras','parqueos','zonas_verdes','puntos_interes','iluminacion','accesibilidad');

SELECT CASE WHEN bool_and(CASE p.proname WHEN 'tg_asignar_identificador' THEN NOT p.prosecdef
                                         ELSE p.prosecdef AND p.proconfig @> ARRAY['search_path=pg_catalog, pg_temp'] END)
             AND count(*) = 4 THEN 'PASS' ELSE 'FAIL' END
       || '|modo_de_seguridad_funciones|'
       || string_agg(p.proname || '=' || CASE WHEN p.prosecdef THEN 'DEFINER' ELSE 'INVOKER' END, ' ' ORDER BY p.proname)
FROM pg_proc p
WHERE p.pronamespace = :'schema'::regnamespace
  AND p.proname IN ('tg_asignar_identificador', 'sigtec_id_siguiente', 'sigtec_id_autorizar_explicito', 'tg_registrar_identificador');

SELECT CASE WHEN r.rolname IS NOT NULL AND NOT r.rolcanlogin AND NOT r.rolsuper
             AND has_function_privilege('sigtec_mantenimiento_id', :'schema' || '.sigtec_id_autorizar_explicito(bigint)', 'EXECUTE')
             AND NOT has_function_privilege('public', :'schema' || '.sigtec_id_autorizar_explicito(bigint)', 'EXECUTE')
             AND NOT has_function_privilege('public', :'schema' || '.tg_registrar_identificador()', 'EXECUTE')
             AND NOT has_table_privilege('public', 'ops.identificadores_globales', 'INSERT')
             AND NOT has_table_privilege('public', 'ops.identificadores_globales', 'DELETE')
            THEN 'PASS' ELSE 'FAIL' END
       || '|permisos_mantenimiento|rol sigtec_mantenimiento_id NOLOGIN; autorización solo para ese rol; PUBLIC sin escritura en el registro'
FROM (SELECT 1) one LEFT JOIN pg_roles r ON r.rolname = 'sigtec_mantenimiento_id';

SELECT CASE WHEN s.ultimo >= greatest(o.max_obj, g.max_reg) THEN 'PASS' ELSE 'FAIL' END
       || '|secuencia_cubre_ids|último consecutivo emitido ' || s.ultimo
       || ' >= máximo usado ' || greatest(o.max_obj, g.max_reg) || ' (objetos ' || o.max_obj || ', registro ' || g.max_reg || ')'
FROM (SELECT CASE WHEN is_called THEN last_value ELSE last_value - 1 END AS ultimo FROM :"schema".objeto_id_seq) s,
     (SELECT coalesce(max(id) - :campus_id::bigint * 1000000000, 0) AS max_obj FROM _sigtec_obj) o,
     (SELECT coalesce(max(id) - :campus_id::bigint * 1000000000, 0) AS max_reg FROM ops.identificadores_globales) g;

SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM ops.identificadores_globales WHERE id = nxt)
             AND NOT EXISTS (SELECT 1 FROM _sigtec_obj WHERE id = nxt) THEN 'PASS' ELSE 'FAIL' END
       || '|siguiente_id_libre|el próximo id automático sería ' || nxt
FROM (SELECT :campus_id::bigint * 1000000000 + CASE WHEN is_called THEN last_value + 1 ELSE last_value END AS nxt
      FROM :"schema".objeto_id_seq) x;

DROP VIEW _sigtec_obj;
