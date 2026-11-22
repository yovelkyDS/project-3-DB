-- SIG-TEC · función temporal pg_temp.sigtec_validar(esquema, campus_id)
-- La usan sql/checks/validacion_capas.sql y tests/sql/20_modelo.sql.
CREATE OR REPLACE FUNCTION pg_temp.sigtec_validar(p_schema text, p_campus smallint)
RETURNS TABLE (capa text, filas bigint, geom_nula bigint, geom_vacia bigint, srid_incorrecto bigint,
               tipo_incorrecto bigint, geom_invalida bigint, campus_incorrecto bigint,
               id_fuera_formato bigint, ids_duplicados bigint, estado text)
LANGUAGE plpgsql AS $fn$
DECLARE
    r record;
BEGIN
    FOR r IN SELECT * FROM (VALUES
        ('edificios','ST_Polygon'), ('carreteras','ST_LineString'), ('aceras','ST_LineString'),
        ('parqueos','ST_Polygon'), ('zonas_verdes','ST_Polygon'), ('puntos_interes','ST_Point'),
        ('iluminacion','ST_Point'), ('accesibilidad','ST_LineString')) AS t(tabla, tipo)
    LOOP
        RETURN QUERY EXECUTE format($q$
            SELECT %L::text,
                   count(*),
                   count(*) FILTER (WHERE geom IS NULL),
                   count(*) FILTER (WHERE geom IS NOT NULL AND ST_IsEmpty(geom)),
                   count(*) FILTER (WHERE ST_SRID(geom) <> 5367),
                   count(*) FILTER (WHERE GeometryType(geom) IS DISTINCT FROM upper(substr(%L, 4))),
                   count(*) FILTER (WHERE NOT ST_IsValid(geom)),
                   count(*) FILTER (WHERE campus_id IS DISTINCT FROM %s),
                   count(*) FILTER (WHERE id NOT BETWEEN %s::bigint * 1000000000 + 1 AND %s::bigint * 1000000000 + 999999999),
                   count(*) - count(DISTINCT id),
                   NULL::text
            FROM %I.%I $q$, r.tabla, r.tipo, p_campus, p_campus, p_campus, p_schema, r.tabla);
    END LOOP;
END
$fn$;
