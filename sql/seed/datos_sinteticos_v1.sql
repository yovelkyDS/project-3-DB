-- =====================================================================
-- SIG-TEC · datos de prueba SINTÉTICOS v1 (un campus por ejecución)
--
-- IMPORTANTE: estas geometrías NO representan infraestructura real del TEC.
-- Son un trazado esquemático de prueba (41 objetos por campus) ubicado
-- alrededor de una coordenada de referencia aproximada de cada campus.
--
-- Transformación de coordenadas (requisito del enunciado):
--   la referencia se recibe en EPSG:4326 (longitud, latitud), se le asigna el
--   SRID de origen con ST_SetSRID y se transforma a EPSG:5367 con ST_Transform.
--   Los objetos se dibujan en metros relativos a esa referencia (ST_Translate).
--
-- Variables psql: :schema :campus_id :campus_lon :campus_lat :campus_code :campus_corto
-- La idempotencia la controla scripts/db/seed.sh mediante ops.seed_runs.
-- El id NO se envía: lo asigna el disparador del campus (id global).
-- =====================================================================

CREATE TEMP TABLE _origen ON COMMIT DROP AS
SELECT round(ST_X(p)::numeric)::float8 AS x,
       round(ST_Y(p)::numeric)::float8 AS y,
       p_wgs
FROM (SELECT ST_SetSRID(ST_MakePoint(:campus_lon, :campus_lat), 4326) AS p_wgs) AS w
CROSS JOIN LATERAL (SELECT ST_Transform(w.p_wgs, 5367) AS p) AS t;

CREATE TEMP TABLE _sufijo ON COMMIT DROP AS
SELECT ' (' || :'campus_corto' || ', sintético)' AS txt, :'campus_code'::text AS cod;

-- 1. edificios ---------------------------------------------------------
INSERT INTO :"schema".edificios (nombre, codigo, area, pisos, geom)
SELECT v.nombre || s.txt, s.cod || '-' || v.codigo,
       round(ST_Area(g.geom)::numeric, 2), v.pisos, g.geom
FROM _origen o CROSS JOIN _sufijo s
CROSS JOIN (VALUES
  (1, 'Biblioteca',               'E01', 3, 'POLYGON((0 0,45 0,45 30,0 30,0 0))'),
  (2, 'Escuela de Computación',   'E02', 2, 'POLYGON((70 0,120 0,120 25,70 25,70 0))'),
  (3, 'Laboratorios',             'E03', 2, 'POLYGON((0 60,35 60,35 95,0 95,0 60))'),
  (4, 'Edificio Administrativo',  'E04', 4, 'POLYGON((70 60,130 60,130 85,70 85,70 60))'),
  (5, 'Soda comedor',             'E05', 1, 'POLYGON((160 0,190 0,190 20,160 20,160 0))'),
  (6, 'Edificio de Aulas',        'E06', 3, 'POLYGON((160 60,220 60,220 80,180 80,180 110,160 110,160 60))')
) AS v(orden, nombre, codigo, pisos, wkt)
CROSS JOIN LATERAL (SELECT ST_Translate(ST_GeomFromText(v.wkt, 5367), o.x, o.y) AS geom) AS g
ORDER BY v.orden;

-- 2. carreteras --------------------------------------------------------
INSERT INTO :"schema".carreteras (nombre, tipo, superficie, geom)
SELECT v.nombre || s.txt, v.tipo, v.superficie, g.geom
FROM _origen o CROSS JOIN _sufijo s
CROSS JOIN (VALUES
  (1, 'Vía principal de acceso', 'principal', 'asfalto',  'LINESTRING(-60 -20,100 -20,260 -20)'),
  (2, 'Calle interna norte',     'interna',   'asfalto',  'LINESTRING(-60 130,100 130,260 130)'),
  (3, 'Calle de servicio',       'servicio',  'concreto', 'LINESTRING(260 -20,260 55,260 130)'),
  (4, 'Acceso a parqueos',       'acceso',    'lastre',   'LINESTRING(-60 -20,-60 55,-60 130)')
) AS v(orden, nombre, tipo, superficie, wkt)
CROSS JOIN LATERAL (SELECT ST_Translate(ST_GeomFromText(v.wkt, 5367), o.x, o.y) AS geom) AS g
ORDER BY v.orden;

-- 3. aceras ------------------------------------------------------------
INSERT INTO :"schema".aceras (material, ancho, condicion, geom)
SELECT v.material, v.ancho, v.condicion, g.geom
FROM _origen o
CROSS JOIN (VALUES
  (1, 'concreto', 2.00, 'buena',   'LINESTRING(0 -10,120 -10)'),
  (2, 'concreto', 1.80, 'buena',   'LINESTRING(55 0,55 45,55 95)'),
  (3, 'adoquin',  1.50, 'regular', 'LINESTRING(145 0,145 110)'),
  (4, 'concreto', 2.50, 'buena',   'LINESTRING(0 45,110 45,220 45)'),
  (5, 'asfalto',  1.20, 'mala',    'LINESTRING(190 10,240 10)')
) AS v(orden, material, ancho, condicion, wkt)
CROSS JOIN LATERAL (SELECT ST_Translate(ST_GeomFromText(v.wkt, 5367), o.x, o.y) AS geom) AS g
ORDER BY v.orden;

-- 4. parqueos ----------------------------------------------------------
INSERT INTO :"schema".parqueos (capacidad, tipo, disponibilidad, geom)
SELECT v.capacidad, v.tipo, v.disponibilidad, g.geom
FROM _origen o
CROSS JOIN (VALUES
  (1, 60, 'general',      25, 'POLYGON((-50 0,-10 0,-10 50,-50 50,-50 0))'),
  (2, 40, 'funcionarios', 10, 'POLYGON((-50 70,-10 70,-10 110,-50 110,-50 70))'),
  (3, 30, 'motocicletas', 12, 'POLYGON((200 0,240 0,240 5,200 5,200 0))'),
  (4,  8, 'discapacidad',  3, 'POLYGON((230 60,245 60,245 75,230 75,230 60))')
) AS v(orden, capacidad, tipo, disponibilidad, wkt)
CROSS JOIN LATERAL (SELECT ST_Translate(ST_GeomFromText(v.wkt, 5367), o.x, o.y) AS geom) AS g
ORDER BY v.orden;

-- 5. zonas_verdes ------------------------------------------------------
INSERT INTO :"schema".zonas_verdes (area, tipo_vegetacion, geom)
SELECT round(ST_Area(g.geom)::numeric, 2), v.tipo, g.geom
FROM _origen o
CROSS JOIN (VALUES
  (1, 'cesped',   'POLYGON((90 95,140 95,140 120,90 120,90 95))'),
  (2, 'jardin',   'POLYGON((5 105,40 105,40 120,5 120,5 105))'),
  (3, 'bosque',   'POLYGON((270 0,330 -10,340 60,300 90,270 60,270 0))'),
  (4, 'arbustos', 'POLYGON((100 -50,150 -50,150 -32,100 -32,100 -50))')
) AS v(orden, tipo, wkt)
CROSS JOIN LATERAL (SELECT ST_Translate(ST_GeomFromText(v.wkt, 5367), o.x, o.y) AS geom) AS g
ORDER BY v.orden;

-- 6. puntos_interes ----------------------------------------------------
-- El primero es la coordenada de referencia WGS84 transformada a EPSG:5367.
INSERT INTO :"schema".puntos_interes (nombre, tipo, descripcion, geom)
SELECT 'Punto de referencia del campus' || s.txt, 'otro',
       format('Coordenada de referencia aproximada (%s, %s) en EPSG:4326 transformada a EPSG:5367. Dato sintético de prueba.',
              ST_X(o.p_wgs), ST_Y(o.p_wgs)),
       ST_Transform(o.p_wgs, 5367)
FROM _origen o CROSS JOIN _sufijo s;

INSERT INTO :"schema".puntos_interes (nombre, tipo, descripcion, geom)
SELECT v.nombre || s.txt, v.tipo, v.descripcion || ' Dato sintético de prueba.', g.geom
FROM _origen o CROSS JOIN _sufijo s
CROSS JOIN (VALUES
  (1, 'Cajero automático',      'cajero',      'Cajero junto a la biblioteca.',          'POINT(50 32)'),
  (2, 'Laboratorio de cómputo', 'laboratorio', 'Laboratorio en el edificio de laboratorios.', 'POINT(17 78)'),
  (3, 'Soda',                   'soda',        'Servicio de alimentación.',               'POINT(175 10)'),
  (4, 'Entrada de biblioteca',  'biblioteca',  'Acceso principal de la biblioteca.',      'POINT(22 -2)'),
  (5, 'Parada de autobús',      'parada_bus',  'Parada sobre la vía principal.',          'POINT(-40 -25)')
) AS v(orden, nombre, tipo, descripcion, wkt)
CROSS JOIN LATERAL (SELECT ST_Translate(ST_GeomFromText(v.wkt, 5367), o.x, o.y) AS geom) AS g
ORDER BY v.orden;

-- 7. iluminacion -------------------------------------------------------
INSERT INTO :"schema".iluminacion (codigo, potencia, estado, geom)
SELECT s.cod || '-L' || lpad(n::text, 2, '0'),
       CASE WHEN n % 2 = 0 THEN 150 ELSE 100 END,
       CASE n WHEN 3 THEN 'averiada' WHEN 6 THEN 'mantenimiento' ELSE 'funcional' END,
       ST_Translate(ST_SetSRID(ST_MakePoint((n - 1) * 40, -26), 5367), o.x, o.y)
FROM _origen o CROSS JOIN _sufijo s
CROSS JOIN generate_series(1, 8) AS n
ORDER BY n;

-- 8. accesibilidad -----------------------------------------------------
INSERT INTO :"schema".accesibilidad (tipo, condicion, descripcion, geom)
SELECT v.tipo, v.condicion, v.descripcion || ' Dato sintético de prueba.', g.geom
FROM _origen o
CROSS JOIN (VALUES
  (1, 'rampa',          'buena',   'Rampa de acceso a la biblioteca.',          'LINESTRING(10 -10,10 0)'),
  (2, 'paso_accesible', 'buena',   'Paso peatonal accesible sobre la vía principal.', 'LINESTRING(60 -28,60 -12)'),
  (3, 'ruta_accesible', 'regular', 'Ruta desde el parqueo general.',            'LINESTRING(-10 25,0 25,0 15)'),
  (4, 'rampa',          'mala',    'Rampa del edificio administrativo.',        'LINESTRING(100 50,100 60)')
) AS v(orden, tipo, condicion, descripcion, wkt)
CROSS JOIN LATERAL (SELECT ST_Translate(ST_GeomFromText(v.wkt, 5367), o.x, o.y) AS geom) AS g
ORDER BY v.orden;
