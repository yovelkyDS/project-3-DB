-- =====================================================================
-- SIG-TEC · definición COMÚN de las ocho capas geográficas de un campus
--
-- Variables psql requeridas:
--   :schema     esquema local del campus (local_cartago, local_san_jose, ...)
--   :campus_id  1..5
--
-- Este archivo es la ÚNICA fuente de la estructura de las tablas. Lo usan:
--   * sql/migrations/campus/0101_capas_locales.sql  -> tablas originales en cada campus
--   * sql/templates/central_copias_locales.sql      -> tablas destino equivalentes en el
--                                                      nodo central (Integrante 2)
-- Así, origen y destino de la replicación lógica conservan el mismo nombre
-- calificado, las mismas columnas, tipos y clave primaria.
--
-- Reglas propias de las tablas ORIGINALES (secuencia, asignación de id,
-- inmutabilidad) están en sql/migrations/campus/0102_identificadores.sql y no
-- se aplican a las copias.
--
-- Unidades: coordenadas y longitudes en metros (EPSG:5367 CR05 / CRTM05);
-- áreas en m²; anchos en m; potencia en W.
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS :"schema";
REVOKE ALL ON SCHEMA :"schema" FROM PUBLIC;

-- ---------------------------------------------------------------------
-- 1. edificios (Polygon)
-- ---------------------------------------------------------------------
CREATE TABLE :"schema".edificios (
    id         bigint        NOT NULL,
    campus_id  smallint      NOT NULL DEFAULT :campus_id,
    nombre     varchar(120)  NOT NULL,
    codigo     varchar(30)   NOT NULL,
    area       numeric(12,2) NOT NULL,
    pisos      smallint      NOT NULL,
    geom       geometry(Polygon, 5367) NOT NULL,
    CONSTRAINT edificios_pkey            PRIMARY KEY (id),
    CONSTRAINT edificios_codigo_uk       UNIQUE (codigo),
    CONSTRAINT edificios_campus_ck       CHECK (campus_id = :campus_id),
    CONSTRAINT edificios_id_formato_ck   CHECK (id BETWEEN campus_id::bigint * 1000000000 + 1
                                                     AND campus_id::bigint * 1000000000 + 999999999),
    CONSTRAINT edificios_nombre_ck       CHECK (btrim(nombre) <> ''),
    CONSTRAINT edificios_codigo_ck       CHECK (btrim(codigo) <> ''),
    CONSTRAINT edificios_area_ck         CHECK (area > 0),
    CONSTRAINT edificios_pisos_ck        CHECK (pisos BETWEEN 1 AND 30),
    CONSTRAINT edificios_geom_ck         CHECK (NOT ST_IsEmpty(geom) AND ST_IsValid(geom))
);
CREATE INDEX edificios_geom_gix ON :"schema".edificios USING gist (geom);

-- ---------------------------------------------------------------------
-- 2. carreteras (LineString)
-- ---------------------------------------------------------------------
CREATE TABLE :"schema".carreteras (
    id          bigint       NOT NULL,
    campus_id   smallint     NOT NULL DEFAULT :campus_id,
    nombre      varchar(120) NOT NULL,
    tipo        varchar(30)  NOT NULL,
    superficie  varchar(30)  NOT NULL,
    geom        geometry(LineString, 5367) NOT NULL,
    CONSTRAINT carreteras_pkey           PRIMARY KEY (id),
    CONSTRAINT carreteras_campus_ck      CHECK (campus_id = :campus_id),
    CONSTRAINT carreteras_id_formato_ck  CHECK (id BETWEEN campus_id::bigint * 1000000000 + 1
                                                      AND campus_id::bigint * 1000000000 + 999999999),
    CONSTRAINT carreteras_nombre_ck      CHECK (btrim(nombre) <> ''),
    CONSTRAINT carreteras_tipo_ck        CHECK (tipo IN ('principal','secundaria','interna','servicio','acceso')),
    CONSTRAINT carreteras_superficie_ck  CHECK (superficie IN ('asfalto','concreto','lastre','adoquin','tierra')),
    CONSTRAINT carreteras_geom_ck        CHECK (NOT ST_IsEmpty(geom) AND ST_IsValid(geom) AND ST_Length(geom) > 0)
);
CREATE INDEX carreteras_geom_gix ON :"schema".carreteras USING gist (geom);

-- ---------------------------------------------------------------------
-- 3. aceras (LineString)
-- ---------------------------------------------------------------------
CREATE TABLE :"schema".aceras (
    id         bigint       NOT NULL,
    campus_id  smallint     NOT NULL DEFAULT :campus_id,
    material   varchar(30)  NOT NULL,
    ancho      numeric(5,2) NOT NULL,
    condicion  varchar(20)  NOT NULL,
    geom       geometry(LineString, 5367) NOT NULL,
    CONSTRAINT aceras_pkey           PRIMARY KEY (id),
    CONSTRAINT aceras_campus_ck      CHECK (campus_id = :campus_id),
    CONSTRAINT aceras_id_formato_ck  CHECK (id BETWEEN campus_id::bigint * 1000000000 + 1
                                                  AND campus_id::bigint * 1000000000 + 999999999),
    CONSTRAINT aceras_material_ck    CHECK (material IN ('concreto','adoquin','asfalto','lastre','otro')),
    CONSTRAINT aceras_ancho_ck       CHECK (ancho > 0 AND ancho <= 20),
    CONSTRAINT aceras_condicion_ck   CHECK (condicion IN ('buena','regular','mala')),
    CONSTRAINT aceras_geom_ck        CHECK (NOT ST_IsEmpty(geom) AND ST_IsValid(geom) AND ST_Length(geom) > 0)
);
CREATE INDEX aceras_geom_gix ON :"schema".aceras USING gist (geom);

-- ---------------------------------------------------------------------
-- 4. parqueos (Polygon)
-- ---------------------------------------------------------------------
CREATE TABLE :"schema".parqueos (
    id              bigint      NOT NULL,
    campus_id       smallint    NOT NULL DEFAULT :campus_id,
    capacidad       integer     NOT NULL,
    tipo            varchar(30) NOT NULL,
    disponibilidad  integer     NOT NULL,
    geom            geometry(Polygon, 5367) NOT NULL,
    CONSTRAINT parqueos_pkey              PRIMARY KEY (id),
    CONSTRAINT parqueos_campus_ck         CHECK (campus_id = :campus_id),
    CONSTRAINT parqueos_id_formato_ck     CHECK (id BETWEEN campus_id::bigint * 1000000000 + 1
                                                       AND campus_id::bigint * 1000000000 + 999999999),
    CONSTRAINT parqueos_capacidad_ck      CHECK (capacidad > 0),
    CONSTRAINT parqueos_tipo_ck           CHECK (tipo IN ('general','estudiantes','funcionarios','visitantes',
                                                           'motocicletas','bicicletas','discapacidad')),
    CONSTRAINT parqueos_disponibilidad_ck CHECK (disponibilidad BETWEEN 0 AND capacidad),
    CONSTRAINT parqueos_geom_ck           CHECK (NOT ST_IsEmpty(geom) AND ST_IsValid(geom))
);
CREATE INDEX parqueos_geom_gix ON :"schema".parqueos USING gist (geom);

-- ---------------------------------------------------------------------
-- 5. zonas_verdes (Polygon)
-- ---------------------------------------------------------------------
CREATE TABLE :"schema".zonas_verdes (
    id               bigint        NOT NULL,
    campus_id        smallint      NOT NULL DEFAULT :campus_id,
    area             numeric(12,2) NOT NULL,
    tipo_vegetacion  varchar(30)   NOT NULL,
    geom             geometry(Polygon, 5367) NOT NULL,
    CONSTRAINT zonas_verdes_pkey           PRIMARY KEY (id),
    CONSTRAINT zonas_verdes_campus_ck      CHECK (campus_id = :campus_id),
    CONSTRAINT zonas_verdes_id_formato_ck  CHECK (id BETWEEN campus_id::bigint * 1000000000 + 1
                                                        AND campus_id::bigint * 1000000000 + 999999999),
    CONSTRAINT zonas_verdes_area_ck        CHECK (area > 0),
    CONSTRAINT zonas_verdes_tipo_ck        CHECK (tipo_vegetacion IN ('cesped','jardin','arbustos','arboles','bosque','mixta')),
    CONSTRAINT zonas_verdes_geom_ck        CHECK (NOT ST_IsEmpty(geom) AND ST_IsValid(geom))
);
CREATE INDEX zonas_verdes_geom_gix ON :"schema".zonas_verdes USING gist (geom);

-- ---------------------------------------------------------------------
-- 6. puntos_interes (Point)
-- ---------------------------------------------------------------------
CREATE TABLE :"schema".puntos_interes (
    id           bigint       NOT NULL,
    campus_id    smallint     NOT NULL DEFAULT :campus_id,
    nombre       varchar(120) NOT NULL,
    tipo         varchar(30)  NOT NULL,
    descripcion  text         NULL,
    geom         geometry(Point, 5367) NOT NULL,
    CONSTRAINT puntos_interes_pkey           PRIMARY KEY (id),
    CONSTRAINT puntos_interes_campus_ck      CHECK (campus_id = :campus_id),
    CONSTRAINT puntos_interes_id_formato_ck  CHECK (id BETWEEN campus_id::bigint * 1000000000 + 1
                                                          AND campus_id::bigint * 1000000000 + 999999999),
    CONSTRAINT puntos_interes_nombre_ck      CHECK (btrim(nombre) <> ''),
    CONSTRAINT puntos_interes_tipo_ck        CHECK (tipo IN ('cajero','laboratorio','soda','biblioteca','auditorio',
                                                             'oficina','parada_bus','servicio_medico','otro')),
    CONSTRAINT puntos_interes_geom_ck        CHECK (NOT ST_IsEmpty(geom) AND ST_IsValid(geom))
);
CREATE INDEX puntos_interes_geom_gix ON :"schema".puntos_interes USING gist (geom);

-- ---------------------------------------------------------------------
-- 7. iluminacion (Point)
-- ---------------------------------------------------------------------
CREATE TABLE :"schema".iluminacion (
    id         bigint      NOT NULL,
    campus_id  smallint    NOT NULL DEFAULT :campus_id,
    codigo     varchar(30) NOT NULL,
    potencia   integer     NOT NULL,
    estado     varchar(20) NOT NULL,
    geom       geometry(Point, 5367) NOT NULL,
    CONSTRAINT iluminacion_pkey           PRIMARY KEY (id),
    CONSTRAINT iluminacion_codigo_uk      UNIQUE (codigo),
    CONSTRAINT iluminacion_campus_ck      CHECK (campus_id = :campus_id),
    CONSTRAINT iluminacion_id_formato_ck  CHECK (id BETWEEN campus_id::bigint * 1000000000 + 1
                                                       AND campus_id::bigint * 1000000000 + 999999999),
    CONSTRAINT iluminacion_codigo_ck      CHECK (btrim(codigo) <> ''),
    CONSTRAINT iluminacion_potencia_ck    CHECK (potencia BETWEEN 1 AND 2000),
    CONSTRAINT iluminacion_estado_ck      CHECK (estado IN ('funcional','averiada','mantenimiento','fuera_servicio')),
    CONSTRAINT iluminacion_geom_ck        CHECK (NOT ST_IsEmpty(geom) AND ST_IsValid(geom))
);
CREATE INDEX iluminacion_geom_gix ON :"schema".iluminacion USING gist (geom);

-- ---------------------------------------------------------------------
-- 8. accesibilidad (LineString)
-- ---------------------------------------------------------------------
CREATE TABLE :"schema".accesibilidad (
    id           bigint      NOT NULL,
    campus_id    smallint    NOT NULL DEFAULT :campus_id,
    tipo         varchar(30) NOT NULL,
    condicion    varchar(20) NOT NULL,
    descripcion  text        NULL,
    geom         geometry(LineString, 5367) NOT NULL,
    CONSTRAINT accesibilidad_pkey           PRIMARY KEY (id),
    CONSTRAINT accesibilidad_campus_ck      CHECK (campus_id = :campus_id),
    CONSTRAINT accesibilidad_id_formato_ck  CHECK (id BETWEEN campus_id::bigint * 1000000000 + 1
                                                         AND campus_id::bigint * 1000000000 + 999999999),
    CONSTRAINT accesibilidad_tipo_ck        CHECK (tipo IN ('rampa','paso_accesible','ruta_accesible',
                                                            'ascensor','pasamanos','guia_podotactil')),
    CONSTRAINT accesibilidad_condicion_ck   CHECK (condicion IN ('buena','regular','mala')),
    CONSTRAINT accesibilidad_geom_ck        CHECK (NOT ST_IsEmpty(geom) AND ST_IsValid(geom) AND ST_Length(geom) > 0)
);
CREATE INDEX accesibilidad_geom_gix ON :"schema".accesibilidad USING gist (geom);

-- ---------------------------------------------------------------------
-- Comentarios (diccionario de datos embebido en el catálogo)
-- ---------------------------------------------------------------------
SELECT set_config('sigtec.schema', :'schema', false) AS _sigtec_schema \gset
DO $doc$
DECLARE
    s text := current_setting('sigtec.schema');
    c record;
BEGIN
    FOR c IN
        SELECT * FROM (VALUES
          ('edificios',      NULL,              'Capa Edificios (Polygon, EPSG:5367). Huella de cada edificio.'),
          ('edificios',      'nombre',          'Nombre del edificio.'),
          ('edificios',      'codigo',          'Código institucional del edificio, único dentro del campus.'),
          ('edificios',      'area',            'Área de la huella en m².'),
          ('edificios',      'pisos',           'Cantidad de pisos (1..30).'),
          ('carreteras',     NULL,              'Capa Carreteras (LineString, EPSG:5367). Eje de vías vehiculares.'),
          ('carreteras',     'nombre',          'Nombre de la vía.'),
          ('carreteras',     'tipo',            'principal | secundaria | interna | servicio | acceso.'),
          ('carreteras',     'superficie',      'asfalto | concreto | lastre | adoquin | tierra.'),
          ('aceras',         NULL,              'Capa Aceras (LineString, EPSG:5367). Eje de aceras peatonales.'),
          ('aceras',         'material',        'concreto | adoquin | asfalto | lastre | otro.'),
          ('aceras',         'ancho',           'Ancho útil en metros (0 < ancho <= 20).'),
          ('aceras',         'condicion',       'buena | regular | mala.'),
          ('parqueos',       NULL,              'Capa Parqueos (Polygon, EPSG:5367). Área de estacionamiento.'),
          ('parqueos',       'capacidad',       'Espacios totales (> 0).'),
          ('parqueos',       'tipo',            'general | estudiantes | funcionarios | visitantes | motocicletas | bicicletas | discapacidad.'),
          ('parqueos',       'disponibilidad',  'Espacios disponibles (0..capacidad).'),
          ('zonas_verdes',   NULL,              'Capa Zonas verdes (Polygon, EPSG:5367).'),
          ('zonas_verdes',   'area',            'Área en m².'),
          ('zonas_verdes',   'tipo_vegetacion', 'cesped | jardin | arbustos | arboles | bosque | mixta.'),
          ('puntos_interes', NULL,              'Capa Puntos de interés (Point, EPSG:5367): cajeros, laboratorios, sodas, etc.'),
          ('puntos_interes', 'nombre',          'Nombre del punto de interés.'),
          ('puntos_interes', 'tipo',            'cajero | laboratorio | soda | biblioteca | auditorio | oficina | parada_bus | servicio_medico | otro.'),
          ('puntos_interes', 'descripcion',     'Descripción libre.'),
          ('iluminacion',    NULL,              'Capa Iluminación (Point, EPSG:5367). Luminarias.'),
          ('iluminacion',    'codigo',          'Código de la luminaria, único dentro del campus.'),
          ('iluminacion',    'potencia',        'Potencia en vatios (1..2000 W).'),
          ('iluminacion',    'estado',          'funcional | averiada | mantenimiento | fuera_servicio.'),
          ('accesibilidad',  NULL,              'Capa Accesibilidad (LineString, EPSG:5367): rampas y pasos accesibles.'),
          ('accesibilidad',  'tipo',            'rampa | paso_accesible | ruta_accesible | ascensor | pasamanos | guia_podotactil.'),
          ('accesibilidad',  'condicion',       'buena | regular | mala.'),
          ('accesibilidad',  'descripcion',     'Descripción libre.')
        ) AS t(tabla, columna, texto)
    LOOP
        IF c.columna IS NULL THEN
            EXECUTE format('COMMENT ON TABLE %I.%I IS %L', s, c.tabla, c.texto);
        ELSE
            EXECUTE format('COMMENT ON COLUMN %I.%I.%I IS %L', s, c.tabla, c.columna, c.texto);
        END IF;
    END LOOP;

    FOR c IN SELECT unnest(ARRAY['edificios','carreteras','aceras','parqueos','zonas_verdes',
                                  'puntos_interes','iluminacion','accesibilidad']) AS tabla
    LOOP
        EXECUTE format('COMMENT ON COLUMN %I.%I.id IS %L', s, c.tabla,
            'Identificador global: campus_id × 1 000 000 000 + consecutivo local (1..999 999 999). Inmutable.');
        EXECUTE format('COMMENT ON COLUMN %I.%I.campus_id IS %L', s, c.tabla,
            'Campus propietario (1 Cartago, 2 San José, 3 San Carlos, 4 Alajuela, 5 Limón). Inmutable.');
        EXECUTE format('COMMENT ON COLUMN %I.%I.geom IS %L', s, c.tabla,
            'Geometría en EPSG:5367 (CR05 / CRTM05), metros.');
    END LOOP;
END
$doc$;
