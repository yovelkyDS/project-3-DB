-- SIG-TEC · pruebas de identificadores globales y restricciones (cada campus)
-- Se ejecuta dentro de una transacción que se REVIERTE: no deja datos.
-- (Las secuencias no son transaccionales: cada corrida consume unos pocos consecutivos.)
-- Variables: :node :schema :campus_id
BEGIN;

SELECT set_config('sigtec_test.base', (:campus_id::bigint * 1000000000)::text, true);
SELECT set_config('sigtec_test.seq0', coalesce(pg_sequence_last_value((:'schema' || '.objeto_id_seq')::regclass), 0)::text, true);

-- Inserciones sin id en dos capas distintas: comparten la secuencia del campus
CREATE TEMP TABLE _ins (orden int, capa text, id bigint, campus_id smallint) ON COMMIT DROP;
WITH a AS (
    INSERT INTO :"schema".puntos_interes (nombre, tipo, descripcion, geom)
    SELECT 'PRUEBA id 1', 'otro', 'prueba automática', ST_Translate(geom, 5, 5)
    FROM :"schema".puntos_interes ORDER BY id LIMIT 1
    RETURNING id, campus_id)
INSERT INTO _ins SELECT 1, 'puntos_interes', id, campus_id FROM a;
WITH b AS (
    INSERT INTO :"schema".iluminacion (codigo, potencia, estado, geom)
    SELECT 'PRUEBA-L99', 120, 'funcional', ST_Translate(geom, 7, 7)
    FROM :"schema".iluminacion ORDER BY id LIMIT 1
    RETURNING id, campus_id)
INSERT INTO _ins SELECT 2, 'iluminacion', id, campus_id FROM b;
WITH c AS (
    INSERT INTO :"schema".accesibilidad (id, tipo, condicion, geom)
    SELECT NULL, 'rampa', 'buena', ST_Translate(geom, 3, 3)
    FROM :"schema".accesibilidad ORDER BY id LIMIT 1
    RETURNING id, campus_id)
INSERT INTO _ins SELECT 3, 'accesibilidad (id NULL explícito)', id, campus_id FROM c;

SELECT pg_temp.t(:'node' || '.id_formula_campus',
                 bool_and(id / 1000000000 = :campus_id AND id % 1000000000 BETWEEN 1 AND 999999999),
                 string_agg(capa || '=' || id, ' ' ORDER BY orden))
FROM _ins;
SELECT pg_temp.t(:'node' || '.secuencia_compartida_entre_capas',
                 (SELECT id FROM _ins WHERE orden = 1) = current_setting('sigtec_test.base')::bigint + current_setting('sigtec_test.seq0')::bigint + 1
                 AND (SELECT id FROM _ins WHERE orden = 2) = (SELECT id FROM _ins WHERE orden = 1) + 1
                 AND (SELECT id FROM _ins WHERE orden = 3) = (SELECT id FROM _ins WHERE orden = 2) + 1,
                 format('consecutivo previo %s -> %s', current_setting('sigtec_test.seq0'),
                        (SELECT string_agg((id % 1000000000)::text, ',' ORDER BY orden) FROM _ins)));
SELECT pg_temp.t(:'node' || '.campus_id_asignado', bool_and(campus_id = :campus_id), string_agg(DISTINCT campus_id::text, ','))
FROM _ins;

-- Rechazos esperados -----------------------------------------------------
SELECT set_config('sigtec_test.id1', (SELECT id FROM _ins WHERE orden = 1)::text, true);
SELECT set_config('sigtec_test.otro_campus', (CASE WHEN :campus_id = 5 THEN 1 ELSE :campus_id + 1 END)::text, true);

SELECT pg_temp.t(:'node' || '.rechaza_cambio_de_id', r LIKE '23514:%inmutable%', r)
FROM pg_temp.expect_error(format('UPDATE %I.puntos_interes SET id = id + 1 WHERE id = %s',
                                 :'schema', current_setting('sigtec_test.id1'))) r;
SELECT pg_temp.t(:'node' || '.rechaza_cambio_de_campus', r LIKE '23514:%', r)
FROM pg_temp.expect_error(format('UPDATE %I.puntos_interes SET campus_id = %s WHERE id = %s',
                                 :'schema', current_setting('sigtec_test.otro_campus'), current_setting('sigtec_test.id1'))) r;
SELECT pg_temp.t(:'node' || '.rechaza_insertar_otro_campus', r LIKE '23514:%no pertenece%', r)
FROM pg_temp.expect_error(format($$INSERT INTO %I.puntos_interes (campus_id, nombre, tipo, geom)
                                   VALUES (%s, 'X', 'otro', ST_SetSRID(ST_MakePoint(450000, 1100000), 5367))$$,
                                 :'schema', current_setting('sigtec_test.otro_campus'))) r;
SELECT pg_temp.t(:'node' || '.rechaza_id_explicito', r LIKE '23514:%lo asigna PostgreSQL%', r)
FROM pg_temp.expect_error(format($$INSERT INTO %I.puntos_interes (id, nombre, tipo, geom)
                                   VALUES (%s, 'X', 'otro', ST_SetSRID(ST_MakePoint(450000, 1100000), 5367))$$,
                                 :'schema', :campus_id::bigint * 1000000000 + 999999999)) r;
-- Modo mantenimiento: un id emitido pero ya usado en OTRA capa se rechaza (unicidad entre capas)
SELECT pg_temp.t(:'node' || '.mantenimiento_rechaza_id_repetido_entre_capas', r LIKE '23505:%ya existe%', r)
FROM pg_temp.expect_error(format($$SET LOCAL sigtec.permitir_id_explicito = on;
                                   INSERT INTO %I.edificios (id, nombre, codigo, area, pisos, geom)
                                   VALUES (%s, 'X', 'PRUEBA-X', 10, 1, ST_MakeEnvelope(450000, 1100000, 450010, 1100010, 5367))$$,
                                 :'schema', current_setting('sigtec_test.id1'))) r;
SELECT pg_temp.t(:'node' || '.mantenimiento_rechaza_id_futuro', r LIKE '23514:%no fue emitido%', r)
FROM pg_temp.expect_error(format($$SET LOCAL sigtec.permitir_id_explicito = on;
                                   INSERT INTO %I.edificios (id, nombre, codigo, area, pisos, geom)
                                   VALUES (%s, 'X', 'PRUEBA-Y', 10, 1, ST_MakeEnvelope(450000, 1100000, 450010, 1100010, 5367))$$,
                                 :'schema', :campus_id::bigint * 1000000000 + 999999999)) r;
SELECT pg_temp.t(:'node' || '.rechaza_srid_distinto', r LIKE '22023:%SRID%', r)
FROM pg_temp.expect_error(format($$INSERT INTO %I.puntos_interes (nombre, tipo, geom)
                                   VALUES ('X', 'otro', ST_SetSRID(ST_MakePoint(-84.5, 10.3), 4326))$$, :'schema')) r;
SELECT pg_temp.t(:'node' || '.rechaza_tipo_geometrico', r LIKE '22023:%type%', r)
FROM pg_temp.expect_error(format($$INSERT INTO %I.edificios (nombre, codigo, area, pisos, geom)
                                   VALUES ('X', 'PRUEBA-Z', 10, 1, ST_SetSRID(ST_MakePoint(450000, 1100000), 5367))$$, :'schema')) r;
SELECT pg_temp.t(:'node' || '.rechaza_geometria_invalida', r LIKE '23514:%geom_ck%', r)
FROM pg_temp.expect_error(format($$INSERT INTO %I.zonas_verdes (area, tipo_vegetacion, geom)
                                   VALUES (10, 'cesped', ST_GeomFromText('POLYGON((0 0,10 10,10 0,0 10,0 0))', 5367))$$, :'schema')) r;
SELECT pg_temp.t(:'node' || '.rechaza_geometria_nula', r LIKE '23502:%', r)
FROM pg_temp.expect_error(format($$INSERT INTO %I.carreteras (nombre, tipo, superficie, geom)
                                   VALUES ('X', 'interna', 'asfalto', NULL)$$, :'schema')) r;
SELECT pg_temp.t(:'node' || '.rechaza_atributo_obligatorio', r LIKE '23502:%', r)
FROM pg_temp.expect_error(format($$INSERT INTO %I.edificios (nombre, codigo, area, pisos, geom)
                                   VALUES (NULL, 'PRUEBA-W', 10, 1, ST_MakeEnvelope(450000, 1100000, 450010, 1100010, 5367))$$, :'schema')) r;
SELECT pg_temp.t(:'node' || '.rechaza_dominio_invalido', r LIKE '23514:%tipo_ck%', r)
FROM pg_temp.expect_error(format($$INSERT INTO %I.carreteras (nombre, tipo, superficie, geom)
                                   VALUES ('X', 'autopista', 'asfalto', ST_GeomFromText('LINESTRING(0 0,1 1)', 5367))$$, :'schema')) r;
SELECT pg_temp.t(:'node' || '.rechaza_disponibilidad_mayor_capacidad', r LIKE '23514:%disponibilidad_ck%', r)
FROM pg_temp.expect_error(format($$INSERT INTO %I.parqueos (capacidad, tipo, disponibilidad, geom)
                                   VALUES (5, 'general', 6, ST_MakeEnvelope(450000, 1100000, 450010, 1100010, 5367))$$, :'schema')) r;

-- Actualización y eliminación normales siguen permitidas
SELECT pg_temp.t(:'node' || '.permite_actualizar_atributos', r = 'NO_ERROR', r)
FROM pg_temp.expect_error(format($$UPDATE %I.puntos_interes SET descripcion = 'actualizada', geom = ST_Translate(geom, 1, 1) WHERE id = %s$$,
                                 :'schema', current_setting('sigtec_test.id1'))) r;
SELECT pg_temp.t(:'node' || '.permite_eliminar', r = 'NO_ERROR', r)
FROM pg_temp.expect_error(format('DELETE FROM %I.puntos_interes WHERE id = %s', :'schema', current_setting('sigtec_test.id1'))) r;

ROLLBACK;
