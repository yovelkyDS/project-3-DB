-- =====================================================================
-- SIG-TEC · verificación de la unicidad GLOBAL de identificadores de un campus
--   psql -v schema=local_san_carlos -f sql/checks/verificar_registro_ids.sql
-- Una fila: objetos en las ocho capas, ids repetidos ENTRE capas, objetos sin
-- registro (o registrados en otra capa) en ops.identificadores_globales e
-- ids registrados sin objeto (eliminados: válido, no se reutilizan).
-- estado = OK si repetidos = 0 y sin_registro = 0. Sirve también para un
-- nodo recuperado o restaurado. Requiere la migración 0103.
-- =====================================================================
SELECT set_config('sigtec.chk_schema', :'schema', false) AS _sigtec_chk \gset
DO $v$
DECLARE s text := current_setting('sigtec.chk_schema'); u text;
BEGIN
    SELECT string_agg(format('SELECT id, %L::text AS capa FROM %I.%I', c, s, c), ' UNION ALL ') INTO u
      FROM unnest(ARRAY['edificios','carreteras','aceras','parqueos','zonas_verdes',
                        'puntos_interes','iluminacion','accesibilidad']) c;
    EXECUTE format('CREATE OR REPLACE TEMP VIEW _sigtec_objetos AS %s', u);
END
$v$;
SELECT (SELECT count(*) FROM _sigtec_objetos)                                         AS objetos,
       (SELECT count(*) FROM (SELECT id FROM _sigtec_objetos GROUP BY id HAVING count(*) > 1) d) AS repetidos_entre_capas,
       (SELECT count(*) FROM _sigtec_objetos o LEFT JOIN ops.identificadores_globales g USING (id)
         WHERE g.id IS NULL OR g.capa <> o.capa)                                      AS sin_registro,
       (SELECT count(*) FROM ops.identificadores_globales g
         WHERE NOT EXISTS (SELECT 1 FROM _sigtec_objetos o WHERE o.id = g.id))        AS registrados_eliminados,
       CASE WHEN (SELECT count(*) FROM (SELECT id FROM _sigtec_objetos GROUP BY id HAVING count(*) > 1) d) = 0
             AND (SELECT count(*) FROM _sigtec_objetos o LEFT JOIN ops.identificadores_globales g USING (id)
                   WHERE g.id IS NULL OR g.capa <> o.capa) = 0
            THEN 'OK' ELSE 'ERROR' END                                                AS estado_ids;
