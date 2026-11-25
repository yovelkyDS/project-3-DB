-- SIG-TEC · pruebas del modelo geográfico (cada campus)
-- Variables: :node :schema :campus_id :code_prefix
\ir ../../sql/checks/fn_validar_capas.sql

CREATE TEMP TABLE _esperado (tabla text, tipo text) ON COMMIT PRESERVE ROWS;
INSERT INTO _esperado VALUES
  ('edificios','POLYGON'), ('carreteras','LINESTRING'), ('aceras','LINESTRING'), ('parqueos','POLYGON'),
  ('zonas_verdes','POLYGON'), ('puntos_interes','POINT'), ('iluminacion','POINT'), ('accesibilidad','LINESTRING');

SELECT pg_temp.t(:'node' || '.ocho_tablas',
                 count(*) = 8, string_agg(c.relname, ',' ORDER BY c.relname))
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = :'schema' AND c.relkind = 'r' AND c.relname IN (SELECT tabla FROM _esperado);

SELECT pg_temp.t(:'node' || '.solo_tablas_de_capas',
                 count(*) = 0, coalesce(string_agg(c.relname, ','), 'ninguna extra'))
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = :'schema' AND c.relkind IN ('r','p','v','m','f') AND c.relname NOT IN (SELECT tabla FROM _esperado);

SELECT pg_temp.t(:'node' || '.tipos_y_srid_declarados',
                 count(*) = 8, string_agg(gc.f_table_name || ':' || gc.type || '/' || gc.srid, ',' ORDER BY gc.f_table_name))
FROM geometry_columns gc JOIN _esperado e ON e.tabla = gc.f_table_name
WHERE gc.f_table_schema = :'schema' AND gc.f_geometry_column = 'geom' AND gc.type = e.tipo AND gc.srid = 5367;

SELECT pg_temp.t(:'node' || '.pk_id_bigint',
                 count(*) = 8, count(*) || ' tablas con PK(id bigint)')
FROM pg_constraint k
JOIN pg_class c ON c.oid = k.conrelid JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum = ALL (k.conkey)
WHERE n.nspname = :'schema' AND k.contype = 'p' AND array_length(k.conkey, 1) = 1
  AND a.attname = 'id' AND a.atttypid = 'bigint'::regtype;

SELECT pg_temp.t(:'node' || '.campus_id_smallint_not_null',
                 count(*) = 8, count(*) || ' tablas')
FROM information_schema.columns
WHERE table_schema = :'schema' AND column_name = 'campus_id' AND data_type = 'smallint' AND is_nullable = 'NO';

SELECT pg_temp.t(:'node' || '.secuencia_unica_compartida',
                 (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                   WHERE n.nspname = :'schema' AND c.relkind = 'S') = 1
                 AND count(DISTINCT encode(t.tgargs, 'escape')) = 1 AND count(*) = 8,
                 string_agg(DISTINCT replace(encode(t.tgargs, 'escape'), E'\\000', ' '), ';'))
FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = :'schema' AND t.tgname = 'trg_10_asignar_identificador';

SELECT pg_temp.t(:'node' || '.disparador_inmutabilidad', count(*) = 8, count(*) || ' tablas')
FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = :'schema' AND t.tgname = 'trg_20_proteger_identificador' AND t.tgenabled = 'O';

SELECT pg_temp.t(:'node' || '.id_sin_default', count(*) = 0, coalesce(string_agg(table_name, ','), 'ninguna tabla con DEFAULT en id'))
FROM information_schema.columns WHERE table_schema = :'schema' AND column_name = 'id' AND column_default IS NOT NULL;

SELECT pg_temp.t(:'node' || '.indices_espaciales', count(*) = 8, count(*) || ' índices GiST')
FROM pg_indexes WHERE schemaname = :'schema' AND indexdef ILIKE '%USING gist (geom)%';

SELECT pg_temp.t(:'node' || '.datos_prueba_registrados', count(*) = 1,
                 coalesce(max(filas)::text || ' objetos cargados', 'sin registro'))
FROM ops.seed_runs WHERE seed_name = 'datos_sinteticos_v1';

-- Validación espacial y de identificadores, capa por capa
SELECT pg_temp.t(:'node' || '.capa.' || v.capa,
                 v.filas >= CASE WHEN EXISTS (SELECT 1 FROM ops.seed_runs WHERE seed_name = 'datos_osm_v1') THEN 1 ELSE 4 END
                   AND v.geom_nula + v.geom_vacia + v.srid_incorrecto + v.tipo_incorrecto
                   + v.geom_invalida + v.campus_incorrecto + v.id_fuera_formato + v.ids_duplicados = 0,
                 format('filas=%s nulas=%s vacias=%s srid_mal=%s tipo_mal=%s invalidas=%s campus_mal=%s id_mal=%s dup=%s',
                        v.filas, v.geom_nula, v.geom_vacia, v.srid_incorrecto, v.tipo_incorrecto, v.geom_invalida,
                        v.campus_incorrecto, v.id_fuera_formato, v.ids_duplicados))
FROM pg_temp.sigtec_validar(:'schema', :campus_id::smallint) v;

-- Unicidad del id entre las ocho capas del campus
WITH ids AS (
            SELECT id FROM :"schema".edificios      UNION ALL SELECT id FROM :"schema".carreteras
  UNION ALL SELECT id FROM :"schema".aceras         UNION ALL SELECT id FROM :"schema".parqueos
  UNION ALL SELECT id FROM :"schema".zonas_verdes   UNION ALL SELECT id FROM :"schema".puntos_interes
  UNION ALL SELECT id FROM :"schema".iluminacion    UNION ALL SELECT id FROM :"schema".accesibilidad)
SELECT pg_temp.t(:'node' || '.id_unico_entre_capas', count(*) = count(DISTINCT id),
                 format('%s ids, %s distintos, rango %s..%s', count(*), count(DISTINCT id), min(id), max(id)))
FROM ids;

-- Ejemplo del contrato: el primer objeto cargado del campus tiene consecutivo 1.
-- Se consulta el registro permanente: el objeto puede haberse sustituido por datos reales.
SELECT pg_temp.t(:'node' || '.primer_objeto_consecutivo_1', count(*) = 1 AND max(capa) = 'edificios',
                 'id=' || max(id) || ' en ' || max(capa))
FROM ops.identificadores_globales WHERE id = :campus_id::bigint * 1000000000 + 1;

-- Coherencia geográfica: todo dentro de Costa Rica (CRTM05) y cerca de la referencia del campus
-- (punto sintético de referencia o, con datos reales, centro de los edificios)
WITH ref AS (SELECT ST_Centroid(ST_Collect(geom)) AS geom FROM :"schema".edificios),
geoms AS (
            SELECT geom FROM :"schema".edificios      UNION ALL SELECT geom FROM :"schema".carreteras
  UNION ALL SELECT geom FROM :"schema".aceras         UNION ALL SELECT geom FROM :"schema".parqueos
  UNION ALL SELECT geom FROM :"schema".zonas_verdes   UNION ALL SELECT geom FROM :"schema".puntos_interes
  UNION ALL SELECT geom FROM :"schema".iluminacion    UNION ALL SELECT geom FROM :"schema".accesibilidad)
SELECT pg_temp.t(:'node' || '.coherencia_geografica',
                 bool_and(ST_Within(g.geom, ST_MakeEnvelope(270000, 880000, 700000, 1260000, 5367)))
                 AND bool_and(ST_DWithin(g.geom, r.geom, 1000)),
                 format('extensión %s; distancia máx. a la referencia %s m',
                        ST_AsText(ST_SnapToGrid(ST_Envelope(ST_Collect(g.geom)), 1)),
                        round(max(ST_Distance(g.geom, r.geom))::numeric, 1)))
FROM geoms g CROSS JOIN ref r;

-- En un campus solo existe su propio esquema local (las copias de otros campus irán a "global")
SELECT pg_temp.t(:'node' || '.solo_esquema_local_propio',
                 count(*) = 1, string_agg(nspname, ','))
FROM pg_namespace WHERE nspname LIKE 'local\_%';
